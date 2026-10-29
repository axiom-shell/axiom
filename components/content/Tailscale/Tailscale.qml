pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.services.system
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Tailscale (from TailscaleManager): this machine (name, addresses,
// version), the exit node in use, tailscaled's warnings, a login link when
// it needs one, Connect / Disconnect (TailscaleConfig.actions) and the
// tailnet's devices, online first; clicking one copies its address. The
// Tailscale widget's popout, and an overlay card (compact: devices online).
Panel {
  id: root

  readonly property var shownPeers: TailscaleConfig.showOffline ? TailscaleManager.peers : TailscaleManager.peers.filter(p => p.online)
  // I18n.tr("Connected") I18n.tr("Stopped") I18n.tr("Needs login") I18n.tr("Starting…") I18n.tr("Not running")
  readonly property var stateLabels: ({
      "Running": "Connected",
      "Stopped": "Stopped",
      "NeedsLogin": "Needs login",
      "NeedsMachineAuth": "Needs login",
      "Starting": "Starting…",
      "": "Not running"
    })
  readonly property string stateText: I18n.tr(root.stateLabels[TailscaleManager.backendState] ?? TailscaleManager.backendState)
  // Re-read on every state, so "seen … ago" stays current
  readonly property real now: {
    void TailscaleManager.peers;
    return Date.now();
  }

  spacing: Widget.padding
  implicitWidth: Widget.px(380)
  fullMinWidth: Appearance.fontSize * 14
  fullMinHeight: Appearance.fontSize * 11
  // In a popout the list grows away from the controls, which stay by the
  // bar (Panel.growth)
  flips: true
  maxImplicitHeight: root.implicitHeight + list.growRoom

  Component.onCompleted: TailscaleManager.acquire(root)
  Component.onDestruction: TailscaleManager.release(root)

  compactContent: CompactFigure {
    icon: TailscaleManager.connected ? "vpn_lock" : "signal_disconnected"
    iconColor: TailscaleManager.connected ? Theme.accent : Theme.foregroundAlt
    value: TailscaleManager.connected ? String(TailscaleManager.onlineCount) : ""
    label: TailscaleManager.connected ? I18n.tr("online") : TailscaleManager.available ? root.stateText : I18n.tr("not installed")
  }

  function ago(iso) {
    const minutes = Math.max(0, Math.round((root.now - Date.parse(iso)) / 60000));
    if (isNaN(minutes))
      return "";
    if (minutes < 60)
      return I18n.tr("{0}m ago", minutes);
    if (minutes < 1440)
      return I18n.tr("{0}h ago", Math.floor(minutes / 60));
    return I18n.tr("{0}d ago", Math.floor(minutes / 1440));
  }
  function osIcon(os) {
    const o = String(os).toLowerCase();
    return o === "android" || o === "ios" ? "smartphone" : o === "macos" ? "laptop_mac" : o === "windows" ? "desktop_windows" : o === "linux" ? "computer" : "devices";
  }
  function peerStatus(peer) {
    if (!peer.online)
      return peer.lastSeen ? I18n.tr("Offline · seen {0}", root.ago(peer.lastSeen)) : I18n.tr("Offline");
    const parts = [peer.ips[0] ?? ""];
    if (peer.exitNode)
      parts.push(I18n.tr("exit node"));
    if (peer.active)
      parts.push(peer.direct ? I18n.tr("direct") : I18n.tr("relay {0}", peer.relay));
    if (peer.rxBytes > 0 || peer.txBytes > 0)
      parts.push("↓" + Utils.formatBytes(peer.rxBytes) + " ↑" + Utils.formatBytes(peer.txBytes));
    return parts.filter(s => s).join(" · ");
  }

  component PeerRow: Rectangle {
    id: row
    required property int index
    readonly property var peer: root.shownPeers[index] ?? null
    property bool copied: false

    width: ListView.view?.width ?? implicitWidth
    implicitHeight: list.rowHeight
    radius: Widget.radius
    color: rowHover.hovered ? Qt.alpha(Theme.backgroundHighlight, 0.5) : Qt.alpha(Theme.backgroundHighlight, 0)
    onPeerChanged: row.copied = false

    ColorGlide on color {}

    HoverHandler {
      id: rowHover
    }
    Timer {
      running: row.copied
      interval: 2000
      onTriggered: row.copied = false
    }
    MouseArea {
      anchors.fill: parent
      enabled: (row.peer?.ips.length ?? 0) > 0
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        ClipboardManager.copyText(row.peer.ips[0]);
        row.copied = true;
      }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding
      spacing: Widget.padding

      StyledIcon {
        Layout.preferredWidth: Widget.iconButton
        horizontalAlignment: Text.AlignHCenter
        text: root.osIcon(row.peer?.os ?? "")
        textSize: Appearance.fontSize * 1.4
        textColor: row.peer?.online ? Theme.accent : Theme.foregroundAlt
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
          Layout.fillWidth: true
          text: row.peer?.name ?? ""
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-1)
          textColor: row.peer?.online ? Theme.foreground : Theme.foregroundAlt
        }
        StyledText {
          Layout.fillWidth: true
          text: row.copied ? I18n.tr("Copied {0}", row.peer?.ips[0] ?? "") : row.peer ? root.peerStatus(row.peer) : ""
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-3)
          textColor: row.copied ? Theme.accent : Theme.foregroundAlt
        }
      }
    }
  }

  ModuleHeader {
    icon: "vpn_lock"
    iconColor: TailscaleManager.connected ? Theme.accent : Theme.foregroundAlt
    title: TailscaleManager.tailnetName || I18n.tr("Tailscale")

    StyledText {
      visible: TailscaleManager.available
      text: root.stateText
      textSize: Appearance.fontSizeBy(-2)
      textColor: TailscaleManager.connected ? Theme.accent : Theme.foregroundAlt
    }
    StyledTextButton {
      visible: TailscaleConfig.actions && TailscaleManager.available && TailscaleManager.backendState !== ""
      enabled: !TailscaleManager.busy
      opacity: enabled ? 1 : 0.5
      text: TailscaleManager.connected ? I18n.tr("Disconnect") : I18n.tr("Connect")
      onClicked: TailscaleManager.connected ? TailscaleManager.disconnect() : TailscaleManager.connect()
    }
  }

  // This machine
  ColumnLayout {
    visible: TailscaleManager.available && TailscaleManager.hostName !== ""
    Layout.fillWidth: true
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing
      StyledText {
        text: TailscaleManager.hostName
        font.bold: true
      }
      StyledText {
        Layout.fillWidth: true
        text: TailscaleManager.dnsName
        elide: Text.ElideRight
        textSize: Appearance.fontSizeBy(-2)
        textColor: Theme.foregroundAlt
      }
    }
    StyledText {
      id: ipText
      property bool copied: false
      visible: TailscaleManager.ips.length > 0
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: ipText.copied ? I18n.tr("Copied {0}", TailscaleManager.ip) : TailscaleManager.ips.join(" · ")
      textSize: Appearance.fontSizeBy(-2)
      textColor: ipText.copied ? Theme.accent : Theme.foreground

      Timer {
        running: ipText.copied
        interval: 2000
        onTriggered: ipText.copied = false
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          ClipboardManager.copyText(TailscaleManager.ip);
          ipText.copied = true;
        }
      }
    }
    StyledText {
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: [TailscaleManager.version ? I18n.tr("Tailscale {0}", TailscaleManager.version) : "", TailscaleManager.exitNode ? I18n.tr("Exit node: {0}", TailscaleManager.exitNode) : ""].filter(s => s).join(" · ")
      visible: text !== ""
      textSize: Appearance.fontSizeBy(-2)
      textColor: Theme.foregroundAlt
    }
  }

  // Login, warnings and the last action's failure
  RowLayout {
    visible: TailscaleManager.needsLogin
    Layout.fillWidth: true
    spacing: Widget.spacing
    StyledText {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: TailscaleManager.authURL ? I18n.tr("This machine needs to log in.") : I18n.tr("This machine needs to log in: press Connect.")
      textSize: Appearance.fontSizeBy(-2)
      textColor: Theme.warning
    }
    StyledTextButton {
      visible: TailscaleManager.authURL !== ""
      text: I18n.tr("Log in")
      onClicked: TailscaleManager.openLogin()
    }
  }
  // In a column of its own, so the panel's column can flip (Panel.flips)
  ColumnLayout {
    visible: TailscaleManager.health.length > 0
    Layout.fillWidth: true
    spacing: root.spacing
    Repeater {
      // a count, so the rows outlive each state
      model: TailscaleManager.health.length
      StyledText {
        required property int index
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: TailscaleManager.health[index] ?? ""
        textSize: Appearance.fontSizeBy(-2)
        textColor: Theme.warning
      }
    }
  }
  StyledText {
    visible: TailscaleManager.lastError !== ""
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: TailscaleManager.lastError
    textSize: Appearance.fontSizeBy(-2)
    textColor: Theme.error
  }

  StyledSeparator {
    Layout.fillWidth: true
    separatorColor: Theme.backgroundHighlight
  }

  // Grows to list every device (from compact, to the full layout)
  wantedHeight: !TailscaleManager.connected ? 0 : root.compact ? 1 : root.height > 0 ? root.height + list.overflow : 0

  DeviceList {
    id: list
    embedded: root.embedded
    on: TailscaleManager.available && TailscaleManager.connected
    offIcon: "signal_disconnected"
    offMessage: !TailscaleManager.available ? I18n.tr("Tailscale isn't installed") : I18n.tr("Not connected")
    count: root.shownPeers.length
    emptyText: I18n.tr("No other devices")
    delegate: PeerRow {}
  }
}
