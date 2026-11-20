pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.services.apps
import qs.services.core
import qs.services.system
import qs.services.ui
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Wi-Fi menu for the Network widget: radio switch, the connection editor,
// VPN import and airplane mode (icon buttons as high as the switch), the
// current connection (address and throughput, folding open its details,
// folded at first; left out by a card's showConnection), the VPNs (one summary row
// with a toggle for the VPN up or last used, folding open every VPN and
// the public IP check; left out by showVpn / the widget's popoutVpn), the
// networks in range (scanning while shown), and a footer (hidden
// network). Click a
// network to connect or disconnect; a secured new one asks inline for
// what it needs (a password, a WEP key, an enterprise login; a lock on
// the icon says it's secured), and saved ones can be forgotten or kept
// from joining on their own on hover ("manual" in their status). The
// popout keeps one size and rows keep their order, as in BluetoothDevices;
// its window keeps room for whatever folds open. Compact, its figure
// toggles the radio.
Panel {
  id: root

  readonly property var info: NetworkingManager.netInfo
  readonly property var networks: NetworkingManager.networks
  readonly property bool radioOn: NetworkingManager.wifiEnabled && NetworkingManager.available
  readonly property string offMessage: I18n.tr(!NetworkingManager.available ? "No Wi-Fi adapter found" : NetworkingManager.hardwareBlocked ? "Wi-Fi is blocked (rfkill)" : NetworkingManager.airplane ? "Airplane mode is on" : "Wi-Fi is off")
  readonly property string kindIcon: info.kind === "wifi" ? NetworkingManager.signalIcon(info.signal / 100) : info.kind === "ethernet" ? "lan" : "signal_wifi_0_bar"

  // The details: folded until a click opens them
  property bool detailsOpen: false
  onDetailsOpenChanged: {
    if (root.detailsOpen)
      NetworkingManager.refreshDetails();
  }
  // A popout's (the bar widget's popoutVpn); a card reads properties
  property bool vpnShown: true
  readonly property bool showsVpn: root.embedded ? root.properties.showVpn : root.vpnShown
  // The popout's arrives after it's built
  onShowsVpnChanged: {
    if (root.showsVpn)
      VpnManager.acquire(root);
    else
      VpnManager.release(root);
  }
  readonly property bool vpnOpen: !VpnManager.folded
  property bool hiddenOpen: false

  // A field is up: keep the keyboard, and the popout open
  wantsKeyboardFocus: NetworkingManager.passwordFor !== null || hiddenLoader.active
  hovered: pointerInside || wantsKeyboardFocus
  onFocusLost: {
    // The file picker (a CA certificate) took it: the form waits for it
    if (FilePickerManager.running)
      return;
    NetworkingManager.cancelPassword();
    root.hiddenOpen = false;
  }

  implicitWidth: Widget.textPx(380)
  // The switch, the connection and a row or two, else the figure
  fullMinWidth: Appearance.fontSize * 15
  fullMinHeight: Appearance.fontSize * 12
  // In a popout the list grows away from the controls, which stay by the
  // bar (Panel.growth)
  flips: true
  // Room for the list's rows and for whatever folds open (each part's
  // most, less what it shows now), so the window is never resized
  maxImplicitHeight: root.implicitHeight + list.growRoom + Math.max(0, root.detailsRoom - detailsLoader.height) + Math.max(0, root.vpnRoom - vpnLoader.height) + Math.max(0, root.hiddenRoom - hiddenLoader.height)
  readonly property real smallLine: Math.max(smallMetrics.height, Widget.smallHeight)
  // ConnectionDetails' six lines at most
  readonly property real detailsRoom: 6 * root.smallLine + Widget.spacing
  readonly property real vpnRoom: !root.showsVpn || VpnManager.rows.length === 0 ? 0 : (VpnManager.rows.length + 1) * (list.rowHeight + 2) + 2 * root.smallLine + Widget.spacing * 3
  // WifiJoinForm's tallest: a hidden enterprise network with More open
  readonly property real hiddenRoom: (Widget.height + Widget.spacing) * 11

  Component.onCompleted: {
    NetworkingManager.acquireScan(root);
    NetworkingManager.refreshIp();
    if (root.showsVpn)
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

  FontMetrics {
    id: smallMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: Style.typeMicro
  }

  compactContent: CompactFigure {
    icon: root.radioOn ? root.kindIcon : "signal_wifi_0_bar"
    iconColor: root.info.kind !== "" ? Style.accent : Style.textMuted
    value: ""
    label: root.info.name || I18n.tr(root.radioOn ? "Disconnected" : "off")
    clickable: NetworkingManager.available && !NetworkingManager.hardwareBlocked
    onClicked: ActionsManager.run("wifi", {
      "fromScreen": true
    })
  }

  // A flat footer action: an icon and a label, an accent text button
  component FooterAction: StyledTextButton {
    kind: "text"
    textSize: Style.typeCaption
  }

  component NetworkRow: DeviceRow {
    id: row
    required property int index
    readonly property var network: root.networks[index] ?? null
    readonly property bool asking: network !== null && NetworkingManager.passwordFor === network
    readonly property string kind: NetworkingManager.securityKind(row.network)
    readonly property bool autoconnects: NetworkingManager.autoconnects(row.network)

    rowHeight: list.rowHeight
    icon: NetworkingManager.signalIcon(row.network?.signalStrength ?? 0)
    title: row.network?.name ?? ""
    iconBadge: !NetworkingManager.isSecure(row.network) ? "" : row.kind === "eap" || row.kind === "dynamic-wep" || row.kind === "leap" ? "badge" : "lock"
    status: row.known && !row.autoconnects && !row.failed && !row.busy ? I18n.tr("{0} · manual", NetworkingManager.networkStatus(row.network)) : NetworkingManager.networkStatus(row.network)
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
      else {
        ShellManager.onScreen("wifi");
        NetworkingManager.toggleNetwork(row.network);
      }
    }
    onConnectClicked: {
      ShellManager.onScreen("wifi");
      NetworkingManager.toggleNetwork(row.network);
    }
    onForgetConfirmed: NetworkingManager.forget(row.network)

    // Whether it joins on its own when in range
    hoverActions: StyledIconButton {
      size: Widget.iconButton
      kind: "text"
      visible: row.known
      enabled: row.hovered && !row.busy
      iconText: row.autoconnects ? "sync" : "sync_disabled"
      iconColor: row.autoconnects ? Style.accent : Style.textMuted
      tooltipText: row.autoconnects ? I18n.tr("Joins automatically: click to stop") : I18n.tr("Doesn't join automatically: click to allow")
      onClicked: NetworkingManager.setAutoconnect(row.network, !row.autoconnects)
    }

    // What joining it asks for: built only while asked (each new ask
    // starts empty), as every row would carry one. A WPA password goes
    // through Quickshell; anything more through axiom's net.join
    Loader {
      width: parent.width
      active: row.asking
      sourceComponent: WifiJoinForm {
        security: row.kind
        error: NetworkingManager.joinError
        onSubmitted: fields => row.kind === "psk" ? NetworkingManager.connectWithPsk(row.network, fields.password) : NetworkingManager.join(row.network, fields)
        onCancelled: NetworkingManager.cancelPassword()
      }
    }
  }

  RadioHeader {
    title: NetworkingManager.available ? I18n.tr("Wi-Fi") : I18n.tr("Network")
    scanning: NetworkingManager.scanning
    checked: NetworkingManager.wifiEnabled
    switchShown: NetworkingManager.available
    switchEnabled: NetworkingManager.available && !NetworkingManager.hardwareBlocked

    onToggled: checked => ActionsManager.run("wifi", {
        "call": checked ? "open" : "close",
        "fromScreen": true
      })

    FlatIconButton {
      visible: Apps.networkEditor !== ""
      iconText: "settings"
      tooltipText: I18n.tr("Edit connections ({0})", Apps.networkEditor)
      onClicked: CommandManager.runDetached(Apps.networkEditor)
    }
    FlatIconButton {
      visible: root.showsVpn && VpnManager.available
      iconText: "vpn_key"
      iconColor: VpnManager.importError !== "" ? Style.error : Style.textMuted
      tooltipText: VpnManager.importError || I18n.tr("Import a VPN: a WireGuard (.conf) or OpenVPN (.ovpn) file")
      onClicked: VpnManager.pickImport()
    }
    FlatIconButton {
      visible: NetworkingManager.available || BluetoothManager.available
      iconText: "flight"
      iconColor: NetworkingManager.airplane ? Style.accent : Style.textMuted
      tooltipText: NetworkingManager.airplane ? I18n.tr("Airplane mode: on") : I18n.tr("Airplane mode: off")
      onClicked: ActionsManager.run("airplane", {
        "fromScreen": true
      })
    }
  }

  // The primary connection (wired or wireless): address and throughput,
  // folding open its details
  FoldRow {
    id: connectionRow
    visible: root.properties.showConnection
    Layout.fillHeight: false
    foldable: root.info.kind !== ""
    open: root.detailsOpen
    onToggled: root.detailsOpen = !root.detailsOpen

    StyledIcon {
      Layout.preferredWidth: Widget.iconButton
      horizontalAlignment: Text.AlignHCenter
      text: root.kindIcon
      size: "md"
      textColor: root.info.kind !== "" ? Style.accent : Style.textMuted
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      StyledText {
        Layout.fillWidth: true
        text: root.info.name || I18n.tr("Disconnected")
        overflow: "line"
        role: "caption"
      }
      StyledText {
        Layout.fillWidth: true
        visible: root.info.kind !== ""
        text: NetworkingManager.connectivity === "portal" ? I18n.tr("Sign-in needed: open a web page") : NetworkingManager.connectivity === "limited" ? I18n.tr("Connected, no internet") : root.info.ip !== "" ? `${root.info.ip} · ${root.info.device}` : root.info.device
        overflow: "line"
        role: "micro"
        tone: NetworkingManager.connectivity === "portal" ? "accent" : NetworkingManager.connectivity === "limited" ? "warning" : "muted"
      }
    }

    ColumnLayout {
      visible: root.info.kind !== ""
      spacing: 0

      RateLabel {
        Layout.alignment: Qt.AlignRight
        rate: SystemManager.netRx
        textColor: Style.accentAlt
        textSize: Style.typeMicro
      }
      RateLabel {
        Layout.alignment: Qt.AlignRight
        direction: "up"
        rate: SystemManager.netTx
        textColor: Style.accent
        textSize: Style.typeMicro
      }
    }
  }

  // Built only while open
  Loader {
    id: detailsLoader
    Layout.fillWidth: true
    Layout.leftMargin: Widget.iconButton + Widget.padding
    active: root.properties.showConnection && root.detailsOpen && root.info.kind !== ""
    visible: active

    sourceComponent: ConnectionDetails {
      details: NetworkingManager.details
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
  }

  // The VPNs: built only when there are some
  Loader {
    id: vpnLoader
    Layout.fillWidth: true
    active: root.showsVpn && VpnManager.rows.length > 0
    visible: active

    sourceComponent: ColumnLayout {
      id: vpnSection
      spacing: 2

      // The one up, else the one a click brings up
      readonly property var target: VpnManager.primary ?? VpnManager.lastRow

      // Folded, the section's one row: what's up and a toggle for it
      FoldRow {
        id: vpnSummary
        Layout.preferredHeight: Widget.iconButton
        open: root.vpnOpen
        onToggled: VpnManager.setFolded(root.vpnOpen)

        StyledLabel {
          text: I18n.tr("VPN")
          role: "label"
          tone: "accent"
        }
        StyledLabel {
          Layout.fillWidth: true
          text: VpnManager.primary ? `${VpnManager.primary.name} · ${VpnManager.statusText(VpnManager.primary)}` : I18n.tr("Off · {0} saved", VpnManager.rows.length)
          overflow: "line"
          role: "caption"
          textColor: VpnManager.anyActive ? Style.text : vpnSummary.hovered ? Style.textAccent : Style.textMuted
        }
        StyledIconButton {
          readonly property var target: vpnSection.target
          visible: !root.vpnOpen && target !== null
          size: Widget.iconButton
          kind: "text"
          enabled: !VpnManager.busy(target)
          iconText: target?.state === "on" ? "link_off" : "link"
          iconColor: target?.state === "on" ? Style.accent : Style.text
          tooltipText: target?.state === "on" ? I18n.tr("Disconnect {0}", target.name) : I18n.tr("Connect {0}", target?.name ?? "")
          onClicked: {
            ShellManager.onScreen("vpn");
            VpnManager.toggle(target);
          }
        }
      }

      FontMetrics {
        id: vpnTitle
        font.family: Appearance.fontFamily
        font.pixelSize: Style.typeCaption
      }

      // Every VPN: built only while unfolded
      Loader {
        Layout.fillWidth: true
        active: root.vpnOpen
        visible: active

        sourceComponent: ColumnLayout {
          spacing: vpnSection.spacing

          Repeater {
            // A count, so the rows outlive each state
            model: VpnManager.rows.length

            VpnRow {
              required property int index
              Layout.fillWidth: true
              // DeviceList.rowHeight's
              rowHeight: Math.max(vpnTitle.height + smallMetrics.height, Widget.iconButton) + Widget.spacing * 2
              vpn: VpnManager.rows[index] ?? null
            }
          }
        }
      }

      // What the internet sees, to check the traffic goes through the VPN
      PublicIpRow {
        id: ip
        visible: root.vpnOpen && ip.available
        lineHeight: root.smallLine
      }

      // As far below as the panel's separator is above, so the folded row
      // sits centred between them
      StyledSeparator {
        Layout.fillWidth: true
        Layout.topMargin: root.spacing - vpnSection.spacing
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
    offIcon: NetworkingManager.airplane ? "flight" : "signal_wifi_0_bar"
    offMessage: root.offMessage
    count: root.networks.length
    emptyText: I18n.tr("Looking for networks…")
    visibleRows: 6
    delegate: NetworkRow {}
  }

  // A network that doesn't broadcast its name: built only while open
  Loader {
    id: hiddenLoader
    Layout.fillWidth: true
    active: root.hiddenOpen && root.radioOn
    visible: active

    sourceComponent: WifiJoinForm {
      id: hiddenForm
      hidden: true
      onSubmitted: fields => {
        hiddenForm.error = "";
        NetworkingManager.join(null, fields, error => {
          if (error)
            hiddenForm.error = error.message;
          else
            root.hiddenOpen = false;
        });
      }
      onCancelled: root.hiddenOpen = false
    }
  }

  // The footer holds only Hidden network, so it goes with the radio
  StyledSeparator {
    visible: root.radioOn
    Layout.fillWidth: true
  }

  Flow {
    visible: root.radioOn
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    FooterAction {
      iconText: "wifi_find"
      text: I18n.tr("Hidden network")
      onClicked: root.hiddenOpen = !root.hiddenOpen
    }
  }
}
