pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Removable drives on the OSD: each thing done to a drive (connected,
// locked, mounted, unmounted, ejected, removed, unplugged without
// ejecting, in use, couldn't eject: DrivesManager.lastEvent, a mount by a
// file manager too, never a drive there at login) is its card, the
// drive's name and what happened; a click on it opens the drive, asks for
// its passphrase or shows the Drives module (DrivesWatch's activate). The
// tile is lit and unusual while a drive is plugged in, hidden with none
// (or no udisks2), so a drive ejected and gone shows only as it changes
OSDSystem {
  model: "event"
  onAdd: "card"

  // I18n.tr("Removable drives")
  exposes: [
    {
      "key": "drive",
      "part": "tile",
      "icon": "usb",
      "label": "Removable drives"
    }
  ]

  // Each event's card: its icon and what happened (OSDCard translates
  // the role)
  readonly property var _cards: ({
      "added": {
        "icon": "usb",
        "role": "Connected"
      },
      "locked": {
        "icon": "lock",
        "role": "Encrypted: click to unlock"
      },
      "mounted": {
        "icon": "usb",
        "role": "Mounted"
      },
      "unmounted": {
        "icon": "usb",
        "role": "Unmounted"
      },
      "ejected": {
        "icon": "eject",
        "role": "Safe to remove"
      },
      "removed": {
        "icon": "usb_off",
        "role": "Disconnected"
      },
      "pulled": {
        "icon": "warning",
        "role": "Unplugged without ejecting"
      },
      "busy": {
        "icon": "warning",
        "role": "In use: close what's using it"
      },
      "ejectFailed": {
        "icon": "warning",
        "role": "Couldn't eject"
      }
    })

  // state: { available (udisks2 answers), count (drives plugged in),
  // event (DrivesManager.lastEvent: { kind, driveId, name, mountPoint }),
  // seq }
  function tile(key, state) {
    const count = state?.count ?? 0;
    return {
      "name": state?.event?.name ?? "",
      "on": count > 0,
      "notable": count > 0,
      "hidden": state?.available !== true || count === 0
    };
  }

  // The drive's name, what happened, and where it was mounted
  // I18n.tr("Connected") I18n.tr("Disconnected") I18n.tr("Mounted") I18n.tr("Safe to remove") I18n.tr("Unmounted") I18n.tr("Unplugged without ejecting") I18n.tr("In use: close what's using it") I18n.tr("Couldn't eject") I18n.tr("Encrypted: click to unlock")
  function card(change, state) {
    const e = state.drive?.event ?? null;
    const look = _cards[e?.kind] ?? _cards.added;
    return {
      "icon": look.icon,
      "title": e?.name ?? "",
      "role": look.role,
      "detail": e?.kind === "mounted" ? (e.mountPoint ?? "") : "",
      "clickable": true
    };
  }
}
