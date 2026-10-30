pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.system
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Every VPN (VpnManager.rows: NetworkManager's, and Tailscale), each a row
// that connects or disconnects on click and asks for its password inline
// when the VPN needs one; Import asks for a .conf or .ovpn file
// (VpnManager.pickImport), Edit connections runs VpnConfig.editorCommand.
// The Vpn widget's popout, and an overlay card (compact: the VPN up, or
// off).
Panel {
  id: root

  readonly property var vpns: VpnManager.rows

  // A password field is up: keep the keyboard, and the popout open
  wantsKeyboardFocus: VpnManager.secretRequest !== null && root.vpns.some(r => r.id === VpnManager.secretRequest.uuid)
  hovered: pointerInside || wantsKeyboardFocus
  onFocusLost: VpnManager.cancelSecret()

  implicitWidth: Widget.px(360)
  fullMinWidth: Appearance.fontSize * 14
  fullMinHeight: Appearance.fontSize * 9
  // In a popout the list grows away from the header, which stays by the
  // bar (Panel.growth)
  flips: true
  maxImplicitHeight: root.implicitHeight + list.growRoom

  Component.onCompleted: VpnManager.acquire(root)
  Component.onDestruction: VpnManager.release(root)

  compactContent: CompactFigure {
    icon: VpnManager.anyActive ? "vpn_lock" : "vpn_key_off"
    iconColor: VpnManager.anyActive ? Theme.accent : Theme.foregroundAlt
    value: ""
    label: VpnManager.primary?.name ?? I18n.tr("off")
  }

  ModuleHeader {
    icon: VpnManager.anyActive ? "vpn_lock" : "vpn_key_off"
    iconColor: VpnManager.anyActive ? Theme.accent : Theme.foregroundAlt
    title: I18n.tr("VPN")

    StyledText {
      text: VpnManager.anyActive ? I18n.tr("{0} on", VpnManager.activeRows.length) : I18n.tr("Off")
      textSize: Appearance.fontSizeBy(-2)
      textColor: VpnManager.anyActive ? Theme.accent : Theme.foregroundAlt
    }
    FlatIconButton {
      visible: VpnManager.available
      iconText: "upload_file"
      iconColor: VpnManager.importError !== "" ? Theme.error : Theme.foregroundAlt
      tooltipText: VpnManager.importError || I18n.tr("Import a WireGuard (.conf) or OpenVPN (.ovpn) file")
      onClicked: VpnManager.pickImport()
    }
    FlatIconButton {
      visible: VpnConfig.editorCommand !== ""
      iconText: "edit"
      tooltipText: I18n.tr("Edit connections")
      onClicked: CommandManager.runDetached(VpnConfig.editorCommand)
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
    on: VpnManager.available || root.vpns.length > 0
    offIcon: "vpn_key_off"
    offMessage: I18n.tr("NetworkManager isn't running")
    count: root.vpns.length
    emptyText: VpnConfig.editorCommand !== "" ? I18n.tr("No VPNs yet: add one with the edit button") : I18n.tr("No VPNs set up in NetworkManager")
    visibleRows: 6
    delegate: VpnRow {
      required property int index
      rowHeight: list.rowHeight
      vpn: root.vpns[index] ?? null
    }
  }
}
