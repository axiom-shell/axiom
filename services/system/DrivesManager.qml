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
// (ask, always a notification), a mount (never while the screen is
// locked: it waits for the unlock), or nothing. Every other event is
// said once (_say) where the OSD's `drive` status or Drives.notify puts
// it (NotificationManager.announce): the OSD's card, a notification, or
// nothing; a click on either runs
// activate(). The Drives widget, module and popout, the OSD's `drive`
// status and /eject read it. Inert on the login screen.
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
  // "added", "locked" (an encrypted drive plugged in), "mounted" /
  // "unmounted" (by anyone, seen in the state), "ejected", "removed"
  // (unplugged), "pulled" (unplugged while mounted), "busy",
  // "ejectFailed". Set only when the OSD says it (_say)
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
      root.askUnlock(v.id, true);
      break;
    }
  }

  // rpc: drives.mount
  // Mounts a volume (an unlocked container's cleartext one); opens it
  // after with `andOpen`
  function mount(drive, volume, andOpen) {
    if (!drive || !volume || root._inert)
      return;
    if (DriveInfo.locked(volume)) {
      root.askUnlock(volume.id, andOpen);
      return;
    }
    const target = DriveInfo.effective(volume);
    root._pend(drive, "mounting");
    BackendManager.call("drives.mount", {
      "id": target.id
    }, (error, result) => {
      root._settle(drive, "drives.mount", error);
      const point = result?.mountPoint ?? "";
      if (!error && point !== "" && andOpen === true)
        root._openFolder(point);
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

  // Shows the passphrase field of a locked volume (in a Drives module or
  // popout shown; activate() opens one); opens it once unlocked with
  // `andOpen`
  function askUnlock(volumeId, andOpen) {
    root.unlockError = "";
    root._openAfterUnlock = andOpen === true;
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
        root._say(error.kind === "busy" ? "busy" : "ejectFailed", drive, {
          "name": name,
          "error": error.kind
        });
        return;
      }
      if (root._seen[drive.id])
        root._seen[drive.id].ejected = true;
      root._say("ejected", drive, {
        "name": name
      });
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

  // A click on a drive event (the OSD's card, a notification; lastEvent's
  // shape, { kind, driveId }): what DriveInfo.clickAction says. Opens
  // the drive's folder, or asks for its passphrase, else shows the drives
  function activate(event) {
    if (!event || root._inert)
      return;
    const drive = root.driveById(event.driveId);
    switch (DriveInfo.clickAction(event.kind)) {
    case "open":
      if (drive) {
        root.open(drive);
        return;
      }
      break;
    case "unlock":
      {
        const pick = DriveInfo.pick(drive);
        if (pick?.action === "unlock")
          root.askUnlock(pick.volume.id);
        break;
      }
    }
    root.showDrives();
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
  // driveId -> { name, mounted, mountedIds, ejected }: each drive as last
  // seen (DriveInfo.mountedIds), so its mount coming or going (by anyone:
  // the shell, a file manager) is said, and an unplug knows its name and
  // whether it was pulled while mounted
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
    const notice = root._notice(summary, body, icon, actions, onAction);
    NotificationManager.sendNotification("axiom", notice.summary, notice.body, notice.opts);
  }

  // Something that happened to a drive (`kind`, lastEvent's), where the
  // OSD's `drive` status or Drives.notify puts it (NotificationManager.
  // announce): the OSD's card, a notification, or nothing. `opts`:
  // { name (a drive gone's, as last seen), mountPoint, error (an axerr
  // kind) }
  function _say(kind, drive, opts) {
    const name = opts?.name ?? root.nameOf(drive);
    const notice = root._eventNotice(kind, drive, name, opts ?? {});
    if (notice && NotificationManager.announce("drive", DrivesConfig.notify, notice.summary, notice.body, notice.opts) === "osd")
      root._event(kind, drive, opts?.mountPoint ?? "", name);
  }

  // A notification's summary, body and sendNotification options
  // (_notify's; `kept`: one that stays until it's read, without the
  // drives' desktop entry, which an unplug or eject clears)
  function _notice(summary, body, icon, actions, onAction, kept) {
    return {
      "summary": summary,
      "body": body,
      "opts": kept === true ? {
        "icon": icon
      } : {
        "icon": icon,
        "desktopEntry": root._desktopEntry,
        "actions": actions ?? [],
        "onAction": onAction ?? null
      }
    };
  }

  // An event as a notification (_notice), with buttons where they help:
  // Open and Eject on a mount, Unlock on an encrypted drive; a click on
  // it runs activate(). Safe to remove and a pulled drive's warning stay
  // until read (kept)
  function _eventNotice(kind, drive, name, opts) {
    const id = drive.id;
    const click = action => {
      const now = root.driveById(id);
      if (action === "eject")
        root.eject(now);
      else
        root.activate({
          "kind": kind,
          "driveId": id
        });
    };
    switch (kind) {
    case "added":
      return root._notice(I18n.tr("{0} plugged in", name), root._detail(drive), "drive-removable-media");
    case "locked":
      return root._notice(I18n.tr("{0} is encrypted", name), root._detail(drive), "drive-removable-media", [
        {
          // A click on it (never a button)
          "id": "default",
          "label": I18n.tr("Unlock")
        },
        {
          "id": "unlock",
          "label": I18n.tr("Unlock")
        }
      ], click);
    case "mounted":
      return root._notice(I18n.tr("{0} mounted", name), Paths.shortenHome(opts.mountPoint ?? ""), "drive-removable-media", [
        {
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
      ], click);
    case "unmounted":
      return root._notice(I18n.tr("{0} unmounted", name), "", "drive-removable-media");
    case "ejected":
      // Without the drives' desktop entry: powered off, the drive leaves
      // udisks at once (often after this answer), and that would clear it
      return root._notice(I18n.tr("Safe to remove"), I18n.tr("{0} can be unplugged now.", name), "media-eject", null, null, true);
    case "removed":
      return root._notice(I18n.tr("{0} disconnected", name), "", "drive-removable-media");
    case "pulled":
      // Kept: not cleared as another drive is unplugged
      return root._notice(I18n.tr("{0} was unplugged without ejecting", name), I18n.tr("Eject a drive before unplugging it, or files being written to it can be lost."), "dialog-warning", null, null, true);
    case "busy":
      return root._notice(I18n.tr("{0} is in use", name), I18n.tr("Close the files and apps using it, then eject it again."), "drive-removable-media");
    case "ejectFailed":
      return root._notice(I18n.tr("Couldn't eject {0}", name), root.errorText(opts.error ?? ""), "dialog-warning");
    }
    return null;
  }

  // "SanDisk Ultra · 32 GB" under a plug-in's name: the hardware when the
  // name is a label, and the size
  function _detail(drive) {
    return [DriveInfo.hardware(drive), DriveInfo.size(drive.size)].filter(s => s !== "").join(" · ");
  }

  // Keeps each drive as last seen (_seen); its mount coming or going is
  // said (not a drive's first sighting, nor an eject's unmount)
  function _see(drives) {
    for (const d of drives) {
      const s = root._seen[d.id];
      // A volume gone while mounted stays mounted: the drive is leaving
      const mountedIds = DriveInfo.mountedIds(d, s?.mountedIds ?? []);
      const mounted = mountedIds.length > 0;
      // Ejected until mounted again: a drive neither ejected nor powered
      // off (UDisks2 offers neither) stays listed
      const ejected = (s?.ejected ?? false) && !(mounted && !s.mounted);
      const changed = s && s.mounted !== mounted && root.pending[d.id] !== "ejecting" && !ejected;
      const name = root.nameOf(d);
      if (changed && mounted)
        root._say("mounted", d, {
          "name": name,
          "mountPoint": DriveInfo.mountPoint(d)
        });
      else if (changed && !mounted)
        root._say("unmounted", d, {
          "name": name
        });
      root._seen[d.id] = {
        "name": name,
        "mounted": mounted,
        "mountedIds": mountedIds,
        "ejected": ejected
      };
    }
  }

  // A drive plugged in: what onInsert says. `ask`: the notification
  // asking (always a notification); an encrypted drive otherwise is
  // Locked, `mount` mounts it (its Mounted, seen in the state, says so),
  // else Connected (_say)
  function _arrived(drive) {
    if (!drive || DriveInfo.ignored(drive, DrivesConfig.ignore))
      return;
    const pick = DriveInfo.pick(drive);
    if (pick && pick.action !== "open" && DrivesConfig.onInsert === "ask") {
      root._ask(drive, pick);
      return;
    }
    if (pick?.action === "unlock") {
      root._say("locked", drive);
      return;
    }
    if (pick?.action === "mount" && DrivesConfig.onInsert === "mount") {
      if (!LockManager.builtinLocked) {
        root._mountAll(drive, false);
        return;
      }
      if (!root._queued.includes(drive.id))
        root._queued = root._queued.concat([drive.id]);
    }
    root._say("added", drive);
  }

  // onInsert "ask": a notification offering to mount or open it, or to
  // unlock an encrypted one. Any button removes it; a mount from here is
  // said like any other (Mounted): Open was this notification's offer
  function _ask(drive, pick) {
    const id = drive.id;
    const name = root.nameOf(drive);
    const encrypted = pick.action === "unlock";
    const actions = encrypted ? [
      {
        "id": "unlock",
        "label": I18n.tr("Unlock")
      }
    ] : [
      {
        "id": "mount",
        "label": I18n.tr("Mount")
      },
      {
        "id": "open",
        "label": I18n.tr("Open")
      }
    ];
    root._notify(encrypted ? I18n.tr("{0} is encrypted", name) : I18n.tr("{0} plugged in", name), root._detail(drive), "drive-removable-media", actions.concat([
      {
        "id": "ignore",
        "label": I18n.tr("Ignore")
      }
    ]), action => {
      // Answered: it goes
      NotificationManager.dismissApp(root._desktopEntry);
      const now = root.driveById(id);
      if (action === "mount")
        root._mountAll(now, false);
      else if (action === "open")
        root.open(now);
      else if (action === "unlock")
        root.activate({
          "kind": "locked",
          "driveId": id
        });
    });
  }

  // Mounts every volume to mount (the first opened with `andOpen`)
  function _mountAll(drive, andOpen) {
    if (!drive)
      return;
    let first = true;
    for (const v of DriveInfo.volumes(drive)) {
      if (DriveInfo.action(v) !== "mount")
        continue;
      root.mount(drive, v, andOpen && first);
      first = false;
    }
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
    root._say(pulled ? "pulled" : "removed", {
      "id": driveId
    }, {
      "name": seen.name
    });
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
      queued.map(id => root.driveById(id)).filter(d => d !== null).forEach(d => root._mountAll(d, false));
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
