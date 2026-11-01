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
// (ask), a mount (never while the screen is locked: it waits for the
// unlock), or nothing. The Drives widget, module and popout, the OSD's
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
  // status: { kind: "added" | "mounted" | "ejected", driveId, name,
  // mountPoint, serial }, else null
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
    case "not-authorized":
      return I18n.tr("Not allowed");
    case "wrong-passphrase":
      return I18n.tr("Wrong passphrase");
    case "not-found":
      return I18n.tr("The drive is gone");
    case "unavailable":
      return I18n.tr("udisks isn't running");
    }
    return I18n.tr("That didn't work");
  }

  // The row's click: opens the drive (mounting it first), or asks for the
  // passphrase of a locked one
  function activate(drive) {
    root.open(drive);
  }

  // Opens a volume's folder (the drive's mounted one, else its first one
  // to mount, mounted first); a locked one asks for its passphrase first
  function open(drive, volume) {
    if (!drive || root._inert)
      return;
    const v = volume ?? DriveInfo.pick(drive)?.volume ?? null;
    if (!v)
      return;
    switch (DriveInfo.action(drive, v)) {
    case "open":
      root._openFolder(DriveInfo.effective(drive, v).mountPoints[0]);
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
  // after with `andOpen` or DrivesConfig.openAfterMount
  function mount(drive, volume, andOpen) {
    if (!drive || !volume || root._inert)
      return;
    if (DriveInfo.locked(volume)) {
      root._openAfterUnlock = andOpen === true;
      root.askUnlock(volume.id);
      return;
    }
    const target = DriveInfo.effective(drive, volume);
    root._pend(drive, "mounting");
    BackendManager.call("drives.mount", {
      "id": target.id
    }, (error, result) => {
      root._settle(drive, "drives.mount", error);
      if (error)
        return;
      const point = result?.mountPoint ?? "";
      root._event("mounted", drive, point);
      if (point !== "" && (andOpen === true || DrivesConfig.openAfterMount))
        root._openFolder(point);
    });
  }

  // rpc: drives.unmount
  function unmount(drive, volume) {
    if (!drive || !volume)
      return;
    root._pend(drive, "unmounting");
    BackendManager.call("drives.unmount", {
      "id": DriveInfo.effective(drive, volume).id
    }, error => root._settle(drive, "drives.unmount", error));
  }

  // Unmounts every mounted volume of a drive
  function unmountAll(drive) {
    for (const v of DriveInfo.volumes(drive)) {
      if (DriveInfo.mounted(DriveInfo.effective(drive, v)))
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
      if (error?.kind === "wrong-passphrase") {
        root._settle(drive, "drives.unlock", null);
        root.unlockError = root.errorText(error.kind);
        return;
      }
      root._settle(drive, "drives.unlock", error);
      const andOpen = root._openAfterUnlock;
      if (root.unlockRequest === id)
        root.cancelUnlock();
      if (error || !result?.cleartextId)
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
    root._ejected = root._ejected.concat([drive.id]);
    BackendManager.call("drives.eject", {
      "id": drive.id
    }, error => {
      root._settle(drive, "drives.eject", error);
      NotificationManager.dismissApp(root._desktopEntry);
      if (error) {
        root._ejected = root._ejected.filter(id => id !== drive.id);
        if (error.kind === "busy")
          root._notify(I18n.tr("{0} is in use", name), I18n.tr("Close the files and apps using it, then eject it again."), "drive-removable-media");
        else
          root._notify(I18n.tr("Couldn't eject {0}", name), root.errorText(error.kind), "dialog-warning");
        return;
      }
      root._event("ejected", drive, "");
      root._notify(I18n.tr("Safe to remove"), I18n.tr("{0} can be unplugged now.", name), "media-eject");
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
  // Drives ejected from here, until they're gone: their unplugging keeps
  // the "Safe to remove" notification
  property var _ejected: []
  // Drives that came while the screen was locked, to mount after the
  // unlock (onInsert "mount")
  property var _queued: []
  property bool _openAfterUnlock: false
  property int _serial: 0
  readonly property bool _inert: Paths.greeter
  readonly property string _desktopEntry: "axiom-drives"

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

  function _event(kind, drive, mountPoint) {
    root._serial += 1;
    root.lastEvent = {
      "kind": kind,
      "driveId": drive.id,
      "name": root.nameOf(drive),
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

  // A drive plugged in: DrivesConfig.onInsert
  function _arrived(drive) {
    if (!drive || DriveInfo.ignored(drive, DrivesConfig.ignore))
      return;
    root._event("added", drive, "");
    const id = drive.id;
    const name = root.nameOf(drive);
    const pick = DriveInfo.pick(drive);
    if (!pick || DrivesConfig.onInsert === "nothing")
      return;
    const detail = [DriveInfo.hardware(drive), DriveInfo.size(drive.size)].filter(s => s !== "").join(" · ");
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
        if (action === "unlock") {
          root.askUnlock(pick.volume.id);
          root.showDrives();
        }
      });
      return;
    }
    if (DrivesConfig.onInsert === "mount") {
      if (LockManager.builtinLocked) {
        if (!root._queued.includes(id))
          root._queued = root._queued.concat([id]);
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
      const now = root.driveById(id);
      if (action === "mount")
        root._mountAll(now, false);
      else if (action === "open")
        root.open(now);
    });
  }

  // Mounts every volume to mount (the first opened with `andOpen`)
  function _mountAll(drive, andOpen) {
    if (!drive)
      return;
    let first = true;
    for (const v of DriveInfo.volumes(drive)) {
      if (DriveInfo.action(drive, v) !== "mount")
        continue;
      root.mount(drive, v, andOpen && first);
      first = false;
    }
  }

  // onInsert "mount": mounts it, then says where, offering Open and Eject
  function _mountOnInsert(drive) {
    const id = drive.id;
    const name = root.nameOf(drive);
    const target = DriveInfo.effective(drive, DriveInfo.pick(drive)?.volume);
    if (!target)
      return;
    root._mountAll(drive, false);
    // The first volume's answer says where (mount() opens it if asked)
    const done = root.lastEvent?.serial ?? 0;
    root._mountedNotice = {
      "driveId": id,
      "name": name,
      "after": done
    };
  }

  // A mount on insert waiting for its answer, to say where it went
  property var _mountedNotice: null
  onLastEventChanged: {
    const notice = root._mountedNotice;
    const e = root.lastEvent;
    if (!notice || !e || e.kind !== "mounted" || e.driveId !== notice.driveId || e.serial <= notice.after)
      return;
    root._mountedNotice = null;
    root._notify(I18n.tr("{0} mounted", notice.name), Paths.shortenHome(e.mountPoint), "drive-removable-media", [
      {
        "id": "open",
        "label": I18n.tr("Open")
      },
      {
        "id": "eject",
        "label": I18n.tr("Eject")
      }
    ], action => {
      const now = root.driveById(notice.driveId);
      if (action === "open")
        root.open(now);
      else if (action === "eject")
        root.eject(now);
    });
  }

  function _gone(driveId) {
    root._queued = root._queued.filter(id => id !== driveId);
    root._setError(driveId, "");
    if (root._ejected.includes(driveId)) {
      root._ejected = root._ejected.filter(id => id !== driveId);
      return;
    }
    NotificationManager.dismissApp(root._desktopEntry);
  }

  function _show(state) {
    root.available = state?.available ?? false;
    root._all = state?.drives ?? [];
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
