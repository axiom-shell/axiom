.pragma library
// Drives' timelines: removable drives. Each event (DrivesManager.lastEvent:
// what happens to a drive, a mount by a file manager too, never a drive
// there at login) is its card: the drive's name and what happened. Its card
// takes a click (the watcher's activate: DrivesManager.activate opens the
// drive, asks for its passphrase, or shows the Drives module). The tile is
// lit and unusual while a drive is plugged in, hidden with none, so a drive
// ejected and gone shows only as it changes.
//
// State by key (DrivesWatch):
//   drive  { available (DrivesManager.available: udisks2 answers), count
//          (drives plugged in), event (DrivesManager.lastEvent: { kind:
//          "added" | "locked" | "mounted" | "unmounted" | "ejected" |
//          "removed" | "pulled" | "busy" | "ejectFailed", driveId, name,
//          mountPoint, serial }, or null), seq }
//
// decided: Drives' activate(change) returns "" (the watcher's own
//   activate runs DrivesManager.activate(lastEvent)): not expressible as
//   rows; the card's `clickable` is.

function d(count, kind, name, mountPoint, seq) {
  return { "available": true, "count": count, "event": kind ? { "kind": kind, "driveId": "sdb1", "name": name || "STICK", "mountPoint": mountPoint || "", "serial": seq } : null, "seq": seq || 0 };
}

function look(kind, count, icon, role) {
  return {
    "name": kind + ": " + role,
    "steps": [
      { "at": 0, "state": { "drive": d(1, "added", "STICK", "", 1) } },
      { "at": 3000, "state": { "drive": d(count, kind, "STICK", "", 2) },
        "expect": { "key": "drive", "show": "card", "kind": "event",
          "card": { "icon": icon, "title": "STICK", "role": role, "detail": "", "clickable": true }, "host": "open" } }
    ]
  };
}

var rows = [
  {
    "name": "the first reading shows nothing, a drive there at login",
    "steps": [
      { "at": 0, "state": { "drive": d(1, "mounted", "STICK", "/run/media/u/STICK", 4) } }
    ]
  },
  {
    "name": "plugged in: Connected, the tile lit and unusual",
    "steps": [
      { "at": 0, "state": { "drive": d(0) } },
      { "at": 3000, "state": { "drive": d(1, "added", "SD", "", 1) },
        "expect": { "key": "drive", "show": "card", "kind": "event",
          "tile": { "icon": "usb", "on": true, "notable": true, "hidden": false, "slash": false },
          "card": { "icon": "usb", "title": "SD", "role": "Connected", "detail": "", "clickable": true }, "host": "open" } }
    ]
  },
  {
    "name": "mounted: the mount point as its detail",
    "steps": [
      { "at": 0, "state": { "drive": d(1, "added", "STICK", "", 1) } },
      { "at": 3000, "state": { "drive": d(1, "mounted", "STICK", "/run/media/u/STICK", 2) },
        "expect": { "key": "drive", "show": "card", "card": { "icon": "usb", "title": "STICK", "role": "Mounted", "detail": "/run/media/u/STICK", "clickable": true } } }
    ]
  },
  {
    "name": "ejected and gone: Safe to remove, the tile hidden (shown only as it changes)",
    "steps": [
      { "at": 0, "state": { "drive": d(1, "mounted", "STICK", "/run/media/u/STICK", 1) } },
      { "at": 3000, "state": { "drive": d(0, "ejected", "STICK", "", 2) },
        "expect": { "key": "drive", "show": "card", "tile": { "on": false, "notable": false, "hidden": true }, "card": { "icon": "eject", "role": "Safe to remove", "detail": "" } } }
    ]
  },
  look("locked", 1, "lock", "Encrypted: click to unlock"),
  look("unmounted", 1, "usb", "Unmounted"),
  look("removed", 0, "usb_off", "Disconnected"),
  look("pulled", 0, "warning", "Unplugged without ejecting"),
  look("busy", 1, "warning", "In use: close what's using it"),
  look("ejectFailed", 1, "warning", "Couldn't eject"),
  {
    "name": "mounted from the Drives module: still its card, the user's",
    "steps": [
      { "at": 0, "state": { "drive": d(1, "added", "STICK", "", 1) } },
      { "at": 3000, "byUser": true, "state": { "drive": d(1, "mounted", "STICK", "/run/media/u/STICK", 2) },
        "expect": { "key": "drive", "show": "card", "byUser": true } }
    ]
  },
  {
    "name": "the same event again (a new seq): its card again",
    "steps": [
      { "at": 0, "state": { "drive": d(1, "busy", "STICK", "", 1) } },
      { "at": 3000, "state": { "drive": d(1, "busy", "STICK", "", 2) },
        "expect": { "key": "drive", "show": "card", "card": { "role": "In use: close what's using it" } } }
    ]
  },
  {
    "name": "the count changing alone: nothing",
    "steps": [
      { "at": 0, "state": { "drive": d(1, "added", "STICK", "", 1) } },
      { "at": 3000, "state": { "drive": { "available": true, "count": 2, "event": { "kind": "added", "driveId": "sdb1", "name": "STICK", "mountPoint": "", "serial": 1 }, "seq": 1 } } }
    ]
  },
  {
    "name": "the event cleared: nothing",
    "steps": [
      { "at": 0, "state": { "drive": d(1, "added", "STICK", "", 1) } },
      { "at": 3000, "state": { "drive": d(1) } }
    ]
  },
  {
    "name": "no udisks2: nothing",
    "steps": [
      { "at": 0, "state": { "drive": { "available": false, "count": 0, "event": null, "seq": 0 } } },
      { "at": 3000, "state": { "drive": { "available": false, "count": 1, "event": { "kind": "added", "driveId": "sdb1", "name": "STICK", "mountPoint": "", "serial": 1 }, "seq": 1 } } }
    ]
  },
  {
    "name": "mounted just after Connected: its card replaces",
    "steps": [
      { "at": 0, "state": { "drive": d(0) } },
      { "at": 3000, "state": { "drive": d(1, "added", "STICK", "", 1) },
        "expect": { "key": "drive", "show": "card", "host": "open" } },
      { "at": 3600, "state": { "drive": d(1, "mounted", "STICK", "/run/media/u/STICK", 2) },
        "expect": { "key": "drive", "show": "card", "card": { "role": "Mounted" }, "host": "replace" } }
    ]
  }
];
