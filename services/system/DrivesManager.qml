pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.session
import qs.services.ui

// Removable drives (USB sticks, memory cards, discs) from axiom's `drives`
// part (udisks2 on the system bus, internal/udisks: `drives.state` on
// every change, `drives.event` on a real plug or unplug), and what the
// shell does with them: mount, open, unmount, unlock a LUKS volume, eject.
// On a plug-in it follows DrivesConfig.onInsert: a notification asking
// (ask, with notifications on), a mount (never while the screen is
// locked: it waits for the unlock), or nothing. Each event is said once
// (_say): with buttons and notifications on, a notification; else the
// OSD's `drive` card, or with no OSD showing `drive` a notification (with
// notifications on). The Drives widget, module and popout, the OSD's
// `drive` status and /eject read it. Inert on the login screen.
QtObject {
  id: root

  // udisks2 answers (false until axiom says otherwise)
  property bool available: false
  // The drives, without the ignored ones (DrivesConfig.ignore), as the
  // daemon lists them (DriveInfo's shape)
  readonly property var drives: root._all.filter(d => !DriveInfo.ignored(d, DrivesConfig.ignore))
  readonly property int count: drives.length
  readonly property var mountedDrives: drives.filter(d => DriveInfo.driveMounted(d))
  // driveId -> what its call is doing ("mounting" | "unmounting" |
  // "unlocking" | "locking" | "ejecting")
  property var pending: ({})
  // driveId -> the last action's error, said for the user ("" none)
  property var errors: ({})
  // The volume whose passphrase field shows (its id), else ""; set by the
  // row's Unlock and the notification's
  property string unlockRequest: ""
  // The last unlock's error, under the field
  property string unlockError: ""
  // The last thing that happened to a drive, for the OSD's `drive`
  // status: { kind, driveId, name, mountPoint, serial }, else null. Kinds:
  // "added", "mounted" / "unmounted" (by anyone, seen in the state),
  // "ejected", "removed" (unplugged), "pulled" (unplugged while mounted),
  // "busy", "ejectFailed". Set only when the OSD says it (_say)
  property var lastEvent: null

  function driveById(id) {
    return root._all.find(d => d.id === id) ?? null;
  }

  // The drive holding a volume (by its id, a cleartext volume's too)
  function driveOfVolume(id) {
    return root._all.find(d => (d.volumes ?? []).some(v => v.id === id || v.cleartextId === id)) ?? null;
  }

  // A drive's name for text: "SanDisk Ultra", else "Drive"
  function nameOf(drive) {
    return DriveInfo.name(drive) || I18n.tr("Drive");
  }

  // What a drive's row says under its name
  function statusText(drive) {
    if (!drive)
      return "";
    switch (root.pending[drive.id]) {
    case "mounting":
      return I18n.tr("Mounting…");
    case "unmounting":
      return I18n.tr("Unmounting…");
    case "unlocking":
      return I18n.tr("Unlocking…");
    case "locking":
      return I18n.tr("Locking…");
    case "ejecting":
      return I18n.tr("Ejecting…");
    }
    const error = root.errors[drive.id] ?? "";
    if (error !== "")
      return error;
    const point = DriveInfo.mountPoint(drive);
    if (point !== "")
      return I18n.tr("Mounted at {0}", Paths.shortenHome(point));
    if (DriveInfo.driveLocked(drive))
      return I18n.tr("Locked");
    return DriveInfo.volumes(drive).length > 0 ? I18n.tr("Not mounted") : I18n.tr("Nothing to mount");
  }

  // A daemon error (axerr kind) said for the user
  function errorText(kind) {
    switch (kind) {
    case "busy":
      return I18n.tr("In use: close the files and apps using it");
    case "not_authorized":
      return I18n.tr("Not allowed");
    case "wrong_passphrase":
      return I18n.tr("Wrong passphrase");
    case "not_found":
      return I18n.tr("The drive is gone");
    case "unavailable":
      return I18n.tr("udisks isn't running");
    }
    return I18n.tr("That didn't work");
  }

  // Opens a volume's folder (the drive's mounted one, else its first one
  // to mount, mounted first); a locked one asks for its passphrase first
  function open(drive, volume) {
    if (!drive || root._inert)
      return;
    const v = volume ?? DriveInfo.pick(drive)?.volume ?? null;
    if (!v)
      return;
    switch (DriveInfo.action(v)) {
    case "open":
      root._openFolder(DriveInfo.effective(v).mountPoints[0]);
      break;
    case "mount":
      root.mount(drive, v, true);
      break;
    case "unlock":
      root._openAfterUnlock = true;
      root.askUnlock(v.id);
      break;
    }
  }

  // rpc: drives.mount
  // Mounts a volume (an unlocked container's cleartext one); opens it
  // after with `andOpen`, and tells `onMounted` where it went ("" when it
  // failed)
  function mount(drive, volume, andOpen, onMounted) {
    if (!drive || !volume || root._inert)
      return;
    if (DriveInfo.locked(volume)) {
      root._openAfterUnlock = andOpen === true;
      root.askUnlock(volume.id);
      return;
    }
    const target = DriveInfo.effective(volume);
    root._pend(drive, "mounting");
    BackendManager.call("drives.mount", {
      "id": target.id
    }, (error, result) => {
      root._settle(drive, "drives.mount", error);
      if (error) {
        if (onMounted)
          onMounted("");
        return;
      }
      const point = result?.mountPoint ?? "";
      if (point !== "" && andOpen === true)
        root._openFolder(point);
      if (onMounted)
        onMounted(point);
    });
  }

  // rpc: drives.unmount
  function unmount(drive, volume) {
    if (!drive || !volume)
      return;
    root._pend(drive, "unmounting");
    BackendManager.call("drives.unmount", {
      "id": DriveInfo.effective(volume).id
    }, error => root._settle(drive, "drives.unmount", error));
  }

  // Unmounts every mounted volume of a drive
  function unmountAll(drive) {
    for (const v of DriveInfo.volumes(drive)) {
      if (DriveInfo.mounted(DriveInfo.effective(v)))
        root.unmount(drive, v);
    }
  }

  // Shows the passphrase field of a locked volume (in the Drives module or
  // popout: the overlay page or edge menu holding one is opened)
  function askUnlock(volumeId) {
    root.unlockError = "";
    root.unlockRequest = volumeId;
  }

  function cancelUnlock() {
    root.unlockRequest = "";
    root.unlockError = "";
    root._openAfterUnlock = false;
  }

  // rpc: drives.unlock
  // Unlocks the asked volume with a passphrase (sent only in the call's
  // body, never logged), then mounts its cleartext volume
  function unlock(passphrase) {
    const id = root.unlockRequest;
    const drive = root.driveOfVolume(id);
    if (!drive || passphrase === "")
      return;
    root.unlockError = "";
    root._pend(drive, "unlocking");
    BackendManager.call("drives.unlock", {
      "id": id,
      "passphrase": passphrase
    }, (error, result) => {
      if (error?.kind === "wrong_passphrase") {
        root._settle(drive, "drives.unlock", null);
        root.unlockError = root.errorText(error.kind);
        return;
      }
      root._settle(drive, "drives.unlock", error);
      const andOpen = root._openAfterUnlock;
      if (root.unlockRequest === id)
        root.cancelUnlock();
      // Nothing to mount inside (LVM, or no filesystem yet)
      if (error || !result?.cleartextId || !result.mountable)
        return;
      root.mount(drive, {
        "id": result.cleartextId,
        "mountable": true,
        "mountPoints": []
      }, andOpen);
    });
  }

  // rpc: drives.lock
  // Locks an unlocked (and unmounted) LUKS volume
  function lock(drive, volume) {
    if (!drive || !volume)
      return;
    root._pend(drive, "locking");
    BackendManager.call("drives.lock", {
      "id": volume.id
    }, error => root._settle(drive, "drives.lock", error));
  }

  // rpc: drives.eject
  // Unmounts, locks and powers off (or ejects) a drive, then says it's
  // safe to remove, or what's using it
  function eject(drive) {
    if (!drive || root.pending[drive.id] === "ejecting")
      return;
    if (root.unlockRequest !== "" && root.driveOfVolume(root.unlockRequest)?.id === drive.id)
      root.cancelUnlock();
    const name = root.nameOf(drive);
    root._pend(drive, "ejecting");
    BackendManager.call("drives.eject", {
      "id": drive.id
    }, error => {
      root._settle(drive, "drives.eject", error);
      NotificationManager.dismissApp(root._desktopEntry);
      if (error) {
        if (error.kind === "busy")
          root._say("busy", drive, () => root._notify(I18n.tr("{0} is in use", name), I18n.tr("Close the files and apps using it, then eject it again."), "drive-removable-media"));
        else
          root._say("ejectFailed", drive, () => root._notify(I18n.tr("Couldn't eject {0}", name), root.errorText(error.kind), "dialog-warning"));
        return;
      }
      if (root._seen[drive.id])
        root._seen[drive.id].ejected = true;
      // Without the drives' desktop entry: powered off, the drive leaves
      // udisks at once (often after this answer), and that would clear it
      root._say("ejected", drive, () => root._notifyKept(I18n.tr("Safe to remove"), I18n.tr("{0} can be unplugged now.", name), "media-eject"));
    });
  }

  function ejectAll() {
    root.drives.forEach(d => root.eject(d));
  }

  // Shows the drives: the overlay page or edge menu holding a Drives
  // module; false with none
  function showDrives() {
    return !Paths.greeter && ShellManager.openModule(["Drives"]);
  }

  // -- Private --
  property var _all: []
  // Drives that came while the screen was locked, to mount after the
  // unlock (onInsert "mount")
  property var _queued: []
  property bool _openAfterUnlock: false
  property int _serial: 0
  readonly property bool _inert: Paths.greeter
  readonly property string _desktopEntry: "axiom-drives"
  // An OSD shows the `drive` status: it says everything without buttons
  readonly property bool _osd: OSDConfig.showsStatus("drive")
  // What plugging in does: onInsert, its ask only with notifications on
  // (the question is a notification)
  readonly property string _insert: DrivesConfig.onInsert === "ask" && !DrivesConfig.notifications ? "nothing" : DrivesConfig.onInsert
  // driveId -> { name, mounted, mountedIds, ejected, quiet }: each drive
  // as last seen (DriveInfo.mountedIds), so its mount coming or going (by
  // anyone: the shell, a file manager) is said, and an unplug knows its
  // name and whether it was pulled while mounted. `quiet`: a mount on
  // insert, which its own notification says
  property var _seen: ({})

  function _pend(drive, what) {
    const next = Object.assign({}, root.pending);
    next[drive.id] = what;
    root.pending = next;
    root._setError(drive.id, "");
  }

  function _settle(drive, method, error) {
    const next = Object.assign({}, root.pending);
    delete next[drive.id];
    root.pending = next;
    if (!error)
      return;
    // Never the params: an unlock's hold the passphrase
    console.warn(`[DrivesManager] ${method} ${drive.id}: ${error.kind}: ${error.message}`);
    root._setError(drive.id, root.errorText(error.kind));
  }

  function _setError(id, text) {
    if ((root.errors[id] ?? "") === text)
      return;
    const next = Object.assign({}, root.errors);
    if (text === "")
      delete next[id];
    else
      next[id] = text;
    root.errors = next;
  }

  // `name`: a drive gone's, as last seen
  function _event(kind, drive, mountPoint, name) {
    root._serial += 1;
    root.lastEvent = {
      "kind": kind,
      "driveId": drive.id,
      "name": name ?? root.nameOf(drive),
      "mountPoint": mountPoint,
      "serial": root._serial
    };
  }

  // The file manager (Apps.fileManager, given the folder) or the
  // desktop's default for folders
  function _openFolder(path) {
    if (!path)
      return;
    if (Apps.fileManager !== "")
      CommandManager.runDetached(["sh", "-c", Apps.fileManager + " \"$1\"", "sh", path]);
    else
      CommandManager.runDetached(["xdg-open", path]);
  }

  function _notify(summary, body, icon, actions, onAction) {
    NotificationManager.sendNotification("axiom", summary, body, {
      "icon": icon,
      "desktopEntry": root._desktopEntry,
      "actions": actions ?? [],
      "onAction": onAction ?? null
    });
  }

  // A notification that stays until it's read: without the drives'
  // desktop entry, which an unplug or eject clears
  function _notifyKept(summary, body, icon) {
    NotificationManager.sendNotification("axiom", summary, body, {
      "icon": icon
    });
  }

  // Something without buttons (`kind`, an OSD event): the OSD's card, else
  // (no OSD showing `drive`), with notifications on, `notify`
  function _say(kind, drive, notify, name, mountPoint) {
    if (root._osd)
      root._event(kind, drive, mountPoint ?? "", name);
    else if (DrivesConfig.notifications)
      notify();
  }

  // Keeps each drive as last seen (_seen); its mount coming or going is
  // said (not a drive's first sighting, an eject's unmount, nor a mount on
  // insert, which its notification says)
  function _see(drives) {
    for (const d of drives) {
      const s = root._seen[d.id];
      // A volume gone while mounted stays mounted: the drive is leaving
      const mountedIds = DriveInfo.mountedIds(d, s?.mountedIds ?? []);
      const mounted = mountedIds.length > 0;
      const changed = s && s.mounted !== mounted && root.pending[d.id] !== "ejecting" && !s.ejected;
      const name = root.nameOf(d);
      if (changed && mounted && !s.quiet) {
        const point = DriveInfo.mountPoint(d);
        root._say("mounted", d, () => root._notify(I18n.tr("{0} mounted", name), Paths.shortenHome(point), "drive-removable-media"), name, point);
      } else if (changed && !mounted)
        root._say("unmounted", d, () => root._notify(I18n.tr("{0} unmounted", name), "", "drive-removable-media"), name);
      root._seen[d.id] = {
        "name": name,
        "mounted": mounted,
        "mountedIds": mountedIds,
        "ejected": s?.ejected ?? false,
        // Spent by the mount it was for
        "quiet": (s?.quiet ?? false) && !(changed && mounted)
      };
    }
  }

  // A drive plugged in: what onInsert says. One thing says so: the
  // notification asking (ask, or an encrypted one, with notifications
  // on), a mount on insert's, else Connected (_say)
  function _arrived(drive) {
    if (!drive || DriveInfo.ignored(drive, DrivesConfig.ignore))
      return;
    const id = drive.id;
    const name = root.nameOf(drive);
    const pick = DriveInfo.pick(drive);
    const detail = [DriveInfo.hardware(drive), DriveInfo.size(drive.size)].filter(s => s !== "").join(" · ");
    const connected = () => root._say("added", drive, () => root._notify(I18n.tr("{0} plugged in", name), detail, "drive-removable-media"));
    if (!pick || root._insert === "nothing" || (pick.action === "unlock" && !DrivesConfig.notifications) || (root._insert === "mount" && pick.action === "open")) {
      connected();
      return;
    }
    if (pick.action === "unlock") {
      root._notify(I18n.tr("{0} is encrypted", name), detail, "drive-removable-media", [
        {
          "id": "unlock",
          "label": I18n.tr("Unlock")
        },
        {
          "id": "ignore",
          "label": I18n.tr("Ignore")
        }
      ], action => {
        // Answered: it goes
        NotificationManager.dismissApp(root._desktopEntry);
        if (action === "unlock") {
          root.askUnlock(pick.volume.id);
          root.showDrives();
        }
      });
      return;
    }
    if (root._insert === "mount") {
      if (LockManager.builtinLocked) {
        if (!root._queued.includes(id))
          root._queued = root._queued.concat([id]);
        connected();
        return;
      }
      root._mountOnInsert(drive);
      return;
    }
    root._notify(I18n.tr("{0} plugged in", name), detail, "drive-removable-media", [
      {
        "id": "mount",
        "label": I18n.tr("Mount")
      },
      {
        "id": "open",
        "label": I18n.tr("Open")
      },
      {
        "id": "ignore",
        "label": I18n.tr("Ignore")
      }
    ], action => {
      // Answered: it goes. A mount from here is said like any other (the
      // OSD's Mounted card): Open was this notification's offer
      NotificationManager.dismissApp(root._desktopEntry);
      const now = root.driveById(id);
      if (action === "mount")
        root._mountAll(now, false);
      else if (action === "open")
        root.open(now);
    });
  }

  // Mounts every volume to mount (the first opened with `andOpen`, and
  // its mount point told to `onFirstMounted`)
  function _mountAll(drive, andOpen, onFirstMounted) {
    if (!drive)
      return;
    let first = true;
    for (const v of DriveInfo.volumes(drive)) {
      if (DriveInfo.action(v) !== "mount")
        continue;
      root.mount(drive, v, andOpen && first, first ? onFirstMounted : null);
      first = false;
    }
  }

  // onInsert "mount": mounts it, then (with notifications on) a
  // notification says where (the first volume's answer), opening it on a
  // click and offering Open and Eject, in place of the Mounted the state
  // would say (_seen's `quiet`); without, that Mounted (_see)
  function _mountOnInsert(drive) {
    const id = drive.id;
    const name = root.nameOf(drive);
    if (!DrivesConfig.notifications) {
      root._mountAll(drive, false);
      return;
    }
    root._seen[id] = Object.assign(root._seen[id] ?? {
      "name": name,
      "mounted": false,
      "mountedIds": [],
      "ejected": false
    }, {
      "quiet": true
    });
    root._mountAll(drive, false, point => {
      // Failed: nothing to say, and a later mount is said again
      if (point === "") {
        if (root._seen[id])
          root._seen[id].quiet = false;
        return;
      }
      root._notify(I18n.tr("{0} mounted", name), Paths.shortenHome(point), "drive-removable-media", [
        {
          // A click on it (never a button)
          "id": "default",
          "label": I18n.tr("Open")
        },
        {
          "id": "open",
          "label": I18n.tr("Open")
        },
        {
          "id": "eject",
          "label": I18n.tr("Eject")
        }
      ], action => {
        const now = root.driveById(id);
        if (action === "default" || action === "open")
          root.open(now);
        else if (action === "eject")
          root.eject(now);
      });
    });
  }

  // Unplugged: Disconnected, or a warning when it was pulled while mounted
  // (DrivesConfig.warnUnplugged) (_say)
  function _gone(driveId) {
    root._queued = root._queued.filter(id => id !== driveId);
    root._setError(driveId, "");
    NotificationManager.dismissApp(root._desktopEntry);
    const seen = root._seen[driveId];
    if (!seen)
      return;
    // Still mounted as it left: pulled (its volumes leave udisks first,
    // still mounted, which _see keeps as mounted). Not one being unmounted
    // or ejected
    const pulled = DrivesConfig.warnUnplugged && seen.mounted && !root.pending[driveId];
    delete root._seen[driveId];
    // Ejected: powered off, it leaves at once; its Safe to remove card
    // stays
    if (seen.ejected || root.pending[driveId] === "ejecting")
      return;
    const gone = {
      "id": driveId
    };
    if (!pulled) {
      root._say("removed", gone, () => root._notify(I18n.tr("{0} disconnected", seen.name), "", "drive-removable-media"), seen.name);
      return;
    }
    // Kept: not cleared as another drive is unplugged
    root._say("pulled", gone, () => root._notifyKept(I18n.tr("{0} was unplugged without ejecting", seen.name), I18n.tr("Eject a drive before unplugging it, or files being written to it can be lost."), "dialog-warning"), seen.name);
  }

  function _show(state) {
    root.available = state?.available ?? false;
    root._all = state?.drives ?? [];
    root._see(root.drives);
    // A request for a volume gone with its drive
    if (root.unlockRequest !== "" && !root.driveOfVolume(root.unlockRequest))
      root.cancelUnlock();
  }

  function _onEvent(e) {
    if (e?.kind === "added")
      // The state may follow the event: read it once both are in
      Qt.callLater(() => root._arrived(e.drive ?? root.driveById(e.driveId)));
    else if (e?.kind === "removed")
      root._gone(e.driveId);
  }

  function _fetch() {
    BackendManager.call("drives.get", {}, (error, state) => {
      if (!error)
        root._show(state);
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    enabled: !root._inert
    function onGreeted() {
      root._fetch();
    }
  }

  // Mounts what came while locked, once unlocked
  property Connections _lock: Connections {
    target: LockManager
    function onBuiltinLockedChanged() {
      if (LockManager.builtinLocked || root._queued.length === 0)
        return;
      const queued = root._queued;
      root._queued = [];
      queued.map(id => root.driveById(id)).filter(d => d !== null).forEach(d => root._mountOnInsert(d));
    }
  }

  Component.onCompleted: {
    if (root._inert)
      return;
    NotificationManager.registerHandler(root._desktopEntry, () => root.showDrives());
    BackendManager.listen("drives.state", state => root._show(state));
    BackendManager.listen("drives.event", e => root._onEvent(e));
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._fetch();
  }

  property IpcTarget _ipc: IpcTarget {
    target: "drives"

    // The drives as JSON: [{ id, name, mounted, mountPoint }]
    function list(): string {
      return JSON.stringify(root.drives.map(d => ({
            "id": d.id,
            "name": DriveInfo.displayName(d, root.nameOf(d)),
            "mounted": DriveInfo.driveMounted(d),
            "mountPoint": DriveInfo.mountPoint(d)
          })));
    }

    // Mounts a drive (by its id: every volume) or one volume (by its id)
    function mount(id: string): void {
      const drive = root.driveById(id);
      if (drive) {
        root._mountAll(drive, false);
        return;
      }
      const owner = root.driveOfVolume(id);
      const volume = (owner?.volumes ?? []).find(v => v.id === id);
      if (volume)
        root.mount(owner, volume, false);
    }

    function eject(id: string): void {
      root.eject(root.driveById(id));
    }

    function ejectAll(): void {
      root.ejectAll();
    }
  }
}
