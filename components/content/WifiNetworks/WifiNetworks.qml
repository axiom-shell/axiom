pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.services.system
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Wi-Fi menu for the Network widget: radio switch, the current connection
// (address and throughput), the VPNs (those up and the last used, all on
// Show all; none without any), and the networks in range (scanning while
// shown). Click a network to connect or disconnect; a secured new one asks
// for its password inline, and saved ones can be forgotten on hover. The
// popout keeps one size and rows keep their order, as in BluetoothDevices.
Panel {
  id: root

  readonly property var info: NetworkingManager.netInfo
  readonly property var networks: NetworkingManager.networks
  readonly property bool radioOn: NetworkingManager.wifiEnabled && NetworkingManager.available
  readonly property string offMessage: I18n.tr(!NetworkingManager.available ? "No Wi-Fi adapter found" : NetworkingManager.hardwareBlocked ? "Wi-Fi is blocked (rfkill)" : "Wi-Fi is off")
  readonly property string kindIcon: info.kind === "wifi" ? NetworkingManager.signalIcon(info.signal / 100) : info.kind === "ethernet" ? "lan" : "signal_wifi_0_bar"

  // VPN rows: all of them, or those up, the last used and the one asking
  // for a password
  property bool allVpns: false
  readonly property var vpns: root.allVpns ? VpnManager.rows : VpnManager.rows.filter(r => r.state !== "off" || r.id === VpnManager.lastRow?.id || r.id === VpnManager.secretRequest?.uuid)

  // A password field is up: keep the keyboard, and the popout open
  wantsKeyboardFocus: NetworkingManager.passwordFor !== null || (VpnManager.secretRequest !== null && root.vpns.some(r => r.id === VpnManager.secretRequest.uuid))
  hovered: pointerInside || wantsKeyboardFocus
  onFocusLost: {
    NetworkingManager.cancelPassword();
    VpnManager.cancelSecret();
  }

  implicitWidth: Widget.px(380)
  // The switch, the connection and a row or two, else the figure
  fullMinWidth: Appearance.fontSize * 15
  fullMinHeight: Appearance.fontSize * 12
  // In a popout the list grows away from the controls, which stay by the
  // bar (Panel.growth)
  flips: true
  maxImplicitHeight: root.implicitHeight + list.growRoom

  Component.onCompleted: {
    NetworkingManager.acquireScan(root);
    NetworkingManager.refreshIp();
    VpnManager.acquire(root);
    SystemManager.acquire(root, {
      "metrics": ["net"],
      "interval": 2000
    });
  }
  Component.onDestruction: {
    NetworkingManager.releaseScan(root);
    NetworkingManager.cancelPassword();
    VpnManager.release(root);
    SystemManager.release(root);
  }

  compactContent: CompactFigure {
    icon: root.radioOn ? root.kindIcon : "signal_wifi_0_bar"
    iconColor: root.info.kind !== "" ? Theme.accent : Theme.foregroundAlt
    value: ""
    label: root.info.name || I18n.tr(root.radioOn ? "Disconnected" : "off")
  }

  component NetworkRow: DeviceRow {
    id: row
    required property int index
    readonly property var network: root.networks[index] ?? null
    readonly property bool asking: network !== null && NetworkingManager.passwordFor === network

    rowHeight: list.rowHeight
    icon: NetworkingManager.signalIcon(row.network?.signalStrength ?? 0)
    title: row.network?.name ?? ""
    status: NetworkingManager.networkStatus(row.network)
    failed: NetworkingManager.failed(row.network)
    connected: row.network?.connected ?? false
    known: row.network?.known ?? false
    busy: row.network?.stateChanging ?? false
    selected: row.asking
    expanded: row.asking
    onNetworkChanged: row.reset()
    onActivated: {
      if (row.asking)
        NetworkingManager.cancelPassword();
      else
        NetworkingManager.toggleNetwork(row.network);
    }
    onConnectClicked: NetworkingManager.toggleNetwork(row.network)
    onForgetConfirmed: NetworkingManager.forget(row.network)

    titleExtras: StyledIcon {
      visible: NetworkingManager.isSecure(row.network)
      text: "lock"
      textSize: Appearance.fontSizeBy(-3)
      textColor: Theme.foregroundAlt
    }

    // The password, for a secured network not saved yet: built only while
    // asked for (each new ask starts empty), as every row would carry one
    Loader {
      width: parent.width
      active: row.asking

      sourceComponent: RowLayout {
        spacing: Widget.spacing

        StyledTextEntry {
          id: passwordField
          Layout.fillWidth: true
          placeholderText: I18n.tr("Password")
          input.echoMode: TextInput.Password
          input.wrapMode: Text.NoWrap
          onAccepted: NetworkingManager.connectWithPsk(row.network, passwordField.text)
          // The field leaves Escape to its parents
          Keys.onEscapePressed: NetworkingManager.cancelPassword()
          Component.onCompleted: Qt.callLater(() => passwordField.input.forceActiveFocus())
        }

        StyledRectButton {
          size: Widget.iconButton
          enabled: passwordField.text !== ""
          opacity: enabled ? 1 : 0.5
          iconText: "link"
          iconColor: Theme.accent
          backgroundColor: "transparent"
          borderHoverColor: Theme.accent
          tooltipText: I18n.tr("Connect")
          onClicked: NetworkingManager.connectWithPsk(row.network, passwordField.text)
        }
      }
    }
  }

  RadioHeader {
    title: I18n.tr("Wi-Fi")
    scanning: NetworkingManager.scanning
    checked: NetworkingManager.wifiEnabled
    switchEnabled: NetworkingManager.available && !NetworkingManager.hardwareBlocked
    onToggled: checked => NetworkingManager.setWifiEnabled(checked)
  }

  // The primary connection (wired or wireless): address and throughput
  RowLayout {
    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Widget.padding

    StyledIcon {
      Layout.preferredWidth: Widget.iconButton
      horizontalAlignment: Text.AlignHCenter
      text: root.kindIcon
      textSize: Appearance.fontSize * 1.4
      textColor: root.info.kind !== "" ? Theme.accent : Theme.foregroundAlt
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      StyledText {
        Layout.fillWidth: true
        text: root.info.name || I18n.tr("Disconnected")
        elide: Text.ElideRight
        textSize: Appearance.fontSizeBy(-1)
      }
      StyledText {
        Layout.fillWidth: true
        visible: root.info.kind !== ""
        text: root.info.ip !== "" ? `${root.info.ip} · ${root.info.device}` : root.info.device
        elide: Text.ElideRight
        textSize: Appearance.fontSizeBy(-3)
        textColor: Theme.foregroundAlt
      }
    }

    ColumnLayout {
      visible: root.info.kind !== ""
      spacing: 0

      RateLabel {
        Layout.alignment: Qt.AlignRight
        rate: SystemManager.netRx
        textColor: Theme.accentAlt
        textSize: Appearance.fontSizeBy(-3)
      }
      RateLabel {
        Layout.alignment: Qt.AlignRight
        direction: "up"
        rate: SystemManager.netTx
        textColor: Theme.accent
        textSize: Appearance.fontSizeBy(-3)
      }
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
    separatorColor: Theme.backgroundHighlight
  }

  // The VPNs: built only when there are some
  Loader {
    Layout.fillWidth: true
    active: VpnManager.rows.length > 0
    visible: active

    sourceComponent: ColumnLayout {
      spacing: 2

      FontMetrics {
        id: vpnTitle
        font.family: Appearance.fontFamily
        font.pixelSize: Appearance.fontSizeBy(-1)
      }
      FontMetrics {
        id: vpnStatus
        font.family: Appearance.fontFamily
        font.pixelSize: Appearance.fontSizeBy(-3)
      }

      // The title, as RadioHeader's; with VPNs left out, the whole row
      // folds them in and out under a chevron, as FoldHeader's
      Item {
        id: vpnHeader
        readonly property int hidden: VpnManager.rows.length - root.vpns.length
        readonly property bool foldable: root.allVpns || hidden > 0
        Layout.fillWidth: true
        implicitHeight: vpnHeaderRow.implicitHeight

        MouseArea {
          id: vpnHeaderArea
          anchors.fill: parent
          enabled: vpnHeader.foldable
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.allVpns = !root.allVpns
        }

        RowLayout {
          id: vpnHeaderRow
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Widget.spacing

          StyledText {
            Layout.fillWidth: true
            text: I18n.tr("VPN")
            font.bold: true
            textColor: Theme.accent
          }
          StyledText {
            visible: vpnHeader.hidden > 0
            text: I18n.tr("{0} more", vpnHeader.hidden)
            textSize: Appearance.fontSizeBy(-2)
            textColor: vpnHeaderArea.containsMouse ? Theme.accent : Theme.foregroundAlt
          }
          StyledIcon {
            visible: vpnHeader.foldable
            text: "expand_more"
            textColor: vpnHeaderArea.containsMouse ? Theme.accent : Theme.foregroundAlt
            rotation: root.allVpns ? 0 : -90

            Glide on rotation {}
          }
        }
      }

      Repeater {
        // A count, so the rows outlive each state
        model: root.vpns.length

        VpnRow {
          required property int index
          Layout.fillWidth: true
          // DeviceList.rowHeight's
          rowHeight: Math.max(vpnTitle.height + vpnStatus.height, Widget.iconButton) + Widget.spacing * 2
          vpn: root.vpns[index] ?? null
        }
      }

      StyledSeparator {
        Layout.fillWidth: true
        Layout.topMargin: Widget.spacing
        separatorColor: Theme.backgroundHighlight
      }
    }
  }

  // Grows to list every row (from compact, to the full layout); off, back
  // to its place
  wantedHeight: !root.radioOn ? 0 : root.compact ? 1 : root.height > 0 ? root.height + list.overflow : 0

  DeviceList {
    id: list
    embedded: root.embedded
    on: root.radioOn
    offIcon: "signal_wifi_0_bar"
    offMessage: root.offMessage
    count: root.networks.length
    emptyText: I18n.tr("Looking for networks…")
    visibleRows: 6
    delegate: NetworkRow {}
  }
}
