pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.methods
import qs.services.system
import qs.components.reusable

// One removable drive in the Drives list (DrivesManager.drives): its
// icon, name and size, where it's mounted (or what went wrong), and eject.
// Clicking the row opens it (mounting it first); on hover, unmount and
// lock. A drive of several volumes lists them under it, each with its own
// action, and a locked LUKS volume asked to unlock (DrivesManager
// .unlockRequest) shows its passphrase field there.
DeviceRow {
  id: row

  required property var drive
  readonly property var volumes: DriveInfo.volumes(row.drive)
  readonly property var asked: DrivesManager.unlockRequest !== "" ? row.volumes.find(v => v.id === DrivesManager.unlockRequest) ?? null : null
  readonly property bool asking: row.asked !== null
  readonly property bool mounted: DriveInfo.driveMounted(row.drive)
  // Unlocked LUKS volumes not mounted: they can be locked again
  readonly property var lockable: row.volumes.filter(v => v.encrypted && v.unlocked && !DriveInfo.mounted(DriveInfo.effective(row.drive, v)))

  icon: DriveInfo.icon(row.drive)
  iconBadge: DriveInfo.driveLocked(row.drive) ? "lock" : ""
  title: DriveInfo.displayName(row.drive, I18n.tr("Drive"))
  status: DrivesManager.statusText(row.drive)
  failed: (DrivesManager.errors[row.drive?.id ?? ""] ?? "") !== ""
  connected: row.mounted
  busy: (DrivesManager.pending[row.drive?.id ?? ""] ?? "") !== ""
  selected: row.asking
  expanded: row.asking || row.volumes.length > 1
  actionIcon: "eject"
  actionTip: I18n.tr("Eject")
  onActivated: {
    if (row.asking)
      DrivesManager.cancelUnlock();
    else
      DrivesManager.open(row.drive);
  }
  onConnectClicked: DrivesManager.eject(row.drive)

  hoverActions: [
    FlatIconButton {
      visible: row.mounted
      iconText: "folder_off"
      tooltipText: I18n.tr("Unmount")
      onClicked: DrivesManager.unmountAll(row.drive)
    },
    FlatIconButton {
      visible: row.lockable.length > 0
      iconText: "lock"
      tooltipText: I18n.tr("Lock")
      onClicked: row.lockable.forEach(v => DrivesManager.lock(row.drive, v))
    }
  ]

  // Built only while shown: the volumes, and the passphrase asked for
  Loader {
    width: parent.width
    active: row.expanded

    sourceComponent: ColumnLayout {
      spacing: Widget.spacing / 2

      Repeater {
        model: row.volumes.length > 1 ? row.volumes.length : 0

        RowLayout {
          id: volumeRow
          required property int index
          readonly property var volume: row.volumes[volumeRow.index] ?? null
          readonly property string action: DriveInfo.action(row.drive, volumeRow.volume)
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: [volumeRow.volume?.label || I18n.tr("Volume {0}", volumeRow.index + 1), volumeRow.volume?.fsType ?? "", DriveInfo.size(volumeRow.volume?.size)].filter(s => s !== "").join(" · ")
            textSize: Appearance.fontSizeBy(-2)
            textColor: volumeRow.action === "open" ? Theme.foreground : Theme.foregroundAlt
          }
          FlatIconButton {
            visible: volumeRow.action === "open"
            iconText: "folder_off"
            tooltipText: I18n.tr("Unmount")
            onClicked: DrivesManager.unmount(row.drive, volumeRow.volume)
          }
          FlatIconButton {
            visible: volumeRow.action !== ""
            // I18n.tr("Open") I18n.tr("Mount") I18n.tr("Unlock")
            iconText: volumeRow.action === "open" ? "folder_open" : volumeRow.action === "unlock" ? "lock_open" : "drive_folder_upload"
            tooltipText: volumeRow.action === "open" ? I18n.tr("Open") : volumeRow.action === "unlock" ? I18n.tr("Unlock") : I18n.tr("Mount")
            onClicked: {
              if (volumeRow.action === "unlock")
                DrivesManager.askUnlock(volumeRow.volume.id);
              else
                DrivesManager.open(row.drive, volumeRow.volume);
            }
          }
        }
      }

      Loader {
        Layout.fillWidth: true
        active: row.asking

        sourceComponent: ColumnLayout {
          spacing: Widget.spacing

          SecretField {
            placeholderText: row.volumes.length > 1 ? I18n.tr("Passphrase for {0}", row.asked?.label || row.asked?.device || "") : I18n.tr("Passphrase")
            buttonIcon: "lock_open"
            buttonTip: I18n.tr("Unlock")
            focusOnShow: true
            onSubmitted: DrivesManager.unlock(text)
            onCancelled: DrivesManager.cancelUnlock()
          }

          StyledText {
            Layout.fillWidth: true
            visible: DrivesManager.unlockError !== ""
            text: DrivesManager.unlockError
            wrapMode: Text.WordWrap
            textSize: Appearance.fontSizeBy(-3)
            textColor: Theme.error
          }
        }
      }
    }
  }
}
