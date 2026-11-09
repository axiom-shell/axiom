pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.methods
import qs.services.system
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Every removable drive plugged in (DrivesManager.drives: USB sticks,
// memory cards, discs), each a row that opens it on click (mounting it
// first), ejects it, and asks for a LUKS volume's passphrase inline.
// Eject all in the header. The Drives widget's popout, and an overlay card
// (compact: how many drives, and how many mounted).
Panel {
  id: root

  readonly property var drives: DrivesManager.drives

  // A passphrase field is up: keep the keyboard, and the popout open
  wantsKeyboardFocus: DrivesManager.unlockRequest !== "" && root.drives.some(d => DriveInfo.volumes(d).some(v => v.id === DrivesManager.unlockRequest))
  hovered: pointerInside || wantsKeyboardFocus
  onFocusLost: DrivesManager.cancelUnlock()

  implicitWidth: Widget.px(360)
  fullMinWidth: Appearance.fontSize * 14
  fullMinHeight: Appearance.fontSize * 9
  // In a popout the list grows away from the header, which stays by the
  // bar (Panel.growth)
  flips: true
  maxImplicitHeight: root.implicitHeight + list.growRoom

  compactContent: CompactFigure {
    icon: "usb"
    iconColor: DrivesManager.mountedDrives.length > 0 ? Theme.accent : Theme.foregroundAlt
    value: String(DrivesManager.count)
    label: DrivesManager.count === 0 ? I18n.tr("no drives") : I18n.tr("{0} mounted", DrivesManager.mountedDrives.length)
  }

  ModuleHeader {
    icon: "usb"
    iconColor: DrivesManager.mountedDrives.length > 0 ? Theme.accent : Theme.foregroundAlt
    title: I18n.tr("Drives")

    FlatIconButton {
      visible: DrivesManager.count > 0
      iconText: "eject"
      tooltipText: I18n.tr("Eject all")
      onClicked: DrivesManager.ejectAll()
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
    separatorColor: Theme.backgroundHighlight
  }

  // Grows to list every row (from compact, to the full layout)
  wantedHeight: root.compact ? 1 : root.height > 0 ? root.height + list.overflow : 0

  DeviceList {
    id: list
    embedded: root.embedded
    on: DrivesManager.available || root.drives.length > 0
    offIcon: "usb_off"
    offMessage: I18n.tr("udisks2 isn't running: it's what reaches removable drives")
    count: root.drives.length
    emptyText: I18n.tr("No removable drives plugged in")
    visibleRows: 5
    delegate: DriveRow {
      required property int index
      rowHeight: list.rowHeight
      drive: root.drives[index] ?? null
    }
  }
}
