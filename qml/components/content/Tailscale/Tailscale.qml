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
// version), tailscaled's warnings and the key's coming expiry, a login
// link when it needs one, Connect / Disconnect, folds for the account
// (switch, add), the exit node and the node's switches
// (TailscaleConfig.actions, which need operator rights: a Grant access
// button asks polkit for them), and the tailnet's devices, online first;
// clicking one copies its address. The Tailscale widget's popout, and an
// overlay card (compact: devices online; a click on it connects or
// disconnects).
Panel {
  id: root

  readonly property bool canAct: TailscaleConfig.actions && TailscaleManager.available && TailscaleManager.backendState !== ""
  readonly property var exitOptions: TailscaleManager.peers.filter(p => p.exitNodeOption && (p.online || p.exitNode))
  property bool accountOpen: false
  property bool exitOpen: false
  property bool optionsOpen: false
  // Days until this machine's key expires (NaN when it never does)
  readonly property real keyDays: {
    void TailscaleManager.peers;
    return TailscaleManager.keyExpiry ? (Date.parse(TailscaleManager.keyExpiry) - Date.now()) / 86400000 : NaN;
  }
  readonly property var shownPeers: TailscaleConfig.showOffline ? TailscaleManager.peers : TailscaleManager.peers.filter(p => p.online)
  // Re-read on every state, so "seen … ago" stays current
  readonly property real now: {
    void TailscaleManager.peers;
    return Date.now();
  }

  spacing: Widget.padding
  implicitWidth: Widget.textPx(380)
  fullMinWidth: Appearance.fontSize * 14
  fullMinHeight: Appearance.fontSize * 11
  // In a popout the list grows away from the controls, which stay by the
  // bar (Panel.growth)
  flips: true
  maxImplicitHeight: root.implicitHeight + list.growRoom

  Component.onCompleted: {
    TailscaleManager.acquire(root);
    TailscaleManager.acquireDetails(root);
  }
  Component.onDestruction: {
    TailscaleManager.release(root);
    TailscaleManager.releaseDetails(root);
  }

  compactContent: CompactFigure {
    icon: TailscaleManager.connected ? "vpn_lock" : "signal_disconnected"
    iconColor: TailscaleManager.connected ? Style.accent : Style.textMuted
    value: TailscaleManager.connected ? String(TailscaleManager.onlineCount) : ""
    label: !TailscaleManager.known ? "" : TailscaleManager.connected ? I18n.tr("online") : TailscaleManager.available ? TailscaleManager.stateText : I18n.tr("not installed")
    clickable: root.canAct && !TailscaleManager.busy && !TailscaleManager.profilesDenied
    onClicked: TailscaleManager.connected ? TailscaleManager.disconnect() : TailscaleManager.connect()
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

  // Online peers read as connected, without the connected row's highlight
  component PeerRow: DeviceRow {
    id: row
    required property int index
    readonly property var peer: root.shownPeers[index] ?? null
    property bool copied: false
    // What a click copies: the DNS name when the card asks and it has one, else the address
    readonly property string copyValue: root.embedded && root.properties.copyValue === "dnsName" && row.peer?.dnsName ? row.peer.dnsName : row.peer?.ips[0] ?? ""

    rowHeight: list.rowHeight
    connectable: false
    icon: root.osIcon(row.peer?.os ?? "")
    title: row.peer?.name ?? ""
    status: row.copied ? I18n.tr("Copied {0}", row.copyValue) : row.peer ? root.peerStatus(row.peer) : ""
    statusColor: row.copied ? Style.textAccent : Style.textMuted
    connected: row.peer?.online ?? false
    onPeerChanged: row.copied = false
    onActivated: {
      if (row.copyValue === "")
        return;
      ClipboardManager.copyText(row.copyValue);
      row.copied = true;
    }

    Timer {
      running: row.copied
      interval: 2000
      onTriggered: row.copied = false
    }
  }

  // A section that folds open (account, exit node, options): its icon,
  // name and current value on one row, the body built only while open,
  // on the side away from the bar so the row never moves (Panel.flips)
  component Fold: ColumnLayout {
    id: fold
    property string icon
    property string label
    property string value
    property bool open: false
    property bool foldable: true
    property Component body
    signal toggled

    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    property LayoutOrder _order: LayoutOrder {
      layout: fold
      reversed: root.flips && root.growsUp
    }

    FoldRow {
      id: foldRow
      Layout.preferredHeight: Widget.iconButton
      foldable: fold.foldable
      open: fold.open && fold.foldable
      onToggled: fold.toggled()

      StyledIcon {
        Layout.preferredWidth: Widget.iconButton
        horizontalAlignment: Text.AlignHCenter
        text: fold.icon
        tone: foldRow.hovered && fold.foldable ? "accent" : "muted"
      }
      StyledLabel {
        text: fold.label
        role: "caption"
      }
      StyledLabel {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: fold.value
        overflow: "line"
        role: "caption"
        tone: "muted"
      }
    }
    Loader {
      Layout.fillWidth: true
      active: fold.open && fold.foldable
      visible: active
      sourceComponent: fold.body
    }
  }

  // One choice in a fold (an account, an exit node, adding one): a check
  // on the chosen one, a click picks another
  component ChoiceRow: ItemRow {
    id: choice
    // The row's icon while it isn't the chosen one (a check)
    property string glyph
    property bool chosen: false
    signal picked

    icon: choice.chosen ? "check" : choice.glyph
    marked: choice.chosen
    clickable: !choice.chosen && !TailscaleManager.busy
    onActivated: choice.picked()
  }

  // One of the node's switches (TailscaleManager.prefs[key]): toggling
  // runs `tailscale set`, the switch following the state again once it
  // comes back (or the action failed)
  component PrefRow: RowLayout {
    id: pref
    property string key
    property string label

    Layout.fillWidth: true
    Layout.leftMargin: Widget.iconButton + Widget.spacing
    spacing: Widget.spacing

    function follow() {
      prefSwitch.checked = Qt.binding(() => TailscaleManager.prefs[pref.key] ?? false);
    }

    Connections {
      target: TailscaleManager
      function onPrefsChanged() {
        pref.follow();
      }
      function onBusyChanged() {
        if (!TailscaleManager.busy && TailscaleManager.lastError !== "")
          pref.follow();
      }
    }

    StyledLabel {
      Layout.fillWidth: true
      text: pref.label
      overflow: "line"
      role: "caption"
    }
    StyledSwitch {
      id: prefSwitch
      enabled: !TailscaleManager.busy
      opacity: enabled ? 1 : Style.opacityDisabled
      checked: TailscaleManager.prefs[pref.key] ?? false
      onToggled: TailscaleManager.setPref(pref.key, checked)
    }
  }

  // Without operator rights tailscaled refuses every change: polkit can
  // grant them (`tailscale set --operator=$USER`). First, so it's by the
  // bar whichever way the popout grows.
  Notice {
    visible: root.canAct && TailscaleManager.profilesDenied
    status: "warning"
    enabled: !TailscaleManager.busy
    icon: "admin_panel_settings"
    title: I18n.tr("Tailscale needs your permission")
    text: I18n.tr("Allow your user to connect, switch accounts and change options.")
    actionText: I18n.tr("Grant access")
    onTriggered: TailscaleManager.grantOperator()
  }

  ModuleHeader {
    icon: "vpn_lock"
    iconColor: TailscaleManager.connected ? Style.accent : Style.textMuted
    title: TailscaleManager.tailnetName || I18n.tr("Tailscale")

    StyledText {
      visible: TailscaleManager.available
      text: TailscaleManager.stateText
      role: "caption"
      tone: TailscaleManager.connected ? "accent" : "muted"
      Layout.maximumWidth: Widget.textPx(160)
      overflow: "line"
    }
    // Connected or not; while connecting or disconnecting, where it's going
    StyledSwitch {
      id: connectSwitch
      visible: root.canAct
      enabled: !TailscaleManager.busy && !TailscaleManager.profilesDenied
      opacity: enabled ? 1 : Style.opacityDisabled
      checked: TailscaleManager.pending === "tailscale.up" || TailscaleManager.pending !== "tailscale.down" && TailscaleManager.connected
      onToggled: {
        if (checked)
          TailscaleManager.connect();
        else
          TailscaleManager.disconnect();
        connectSwitch.checked = Qt.binding(() => TailscaleManager.pending === "tailscale.up" || TailscaleManager.pending !== "tailscale.down" && TailscaleManager.connected);
      }
    }
  }

  // A pending login's link opens for anyone; without one, logging in runs
  // `tailscale up`, an action (TailscaleConfig.actions) needing the rights
  Notice {
    visible: TailscaleManager.needsLogin && (TailscaleManager.authURL !== "" || root.canAct && !TailscaleManager.profilesDenied)
    status: "accent"
    icon: "login"
    title: I18n.tr("Log in to Tailscale")
    text: TailscaleManager.authURL ? I18n.tr("Finish logging in in your browser.") : I18n.tr("This machine isn't logged in.")
    actionText: I18n.tr("Log in")
    // Opening a link doesn't wait for `tailscale up` to give up
    enabled: TailscaleManager.authURL !== "" || !TailscaleManager.busy
    onTriggered: TailscaleManager.logIn()
  }

  // This machine
  ColumnLayout {
    visible: TailscaleManager.available && TailscaleManager.hostName !== ""
    Layout.fillWidth: true
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing
      StyledLabel {
        text: TailscaleManager.hostName
        font.weight: Style.weightStrong
      }
      StyledLabel {
        Layout.fillWidth: true
        text: TailscaleManager.dnsName
        overflow: "line"
        role: "caption"
        tone: "muted"
      }
    }
    StyledText {
      id: ipText
      property bool copied: false
      visible: TailscaleManager.ips.length > 0
      Layout.fillWidth: true
      overflow: "line"
      text: ipText.copied ? I18n.tr("Copied {0}", TailscaleManager.ip) : TailscaleManager.ips.join(" · ")
      role: "caption"
      tone: ipText.copied ? "accent" : "text"

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
      overflow: "line"
      text: TailscaleManager.version ? I18n.tr("Tailscale {0}", TailscaleManager.version) : ""
      visible: text !== ""
      role: "caption"
      tone: "muted"
    }
  }

  Fold {
    visible: root.canAct && (TailscaleManager.profiles.length > 0 || TailscaleManager.account.loginName !== "")
    icon: "account_circle"
    label: I18n.tr("Account")
    value: TailscaleManager.account.displayName || TailscaleManager.account.loginName || I18n.tr("Not logged in")
    foldable: !TailscaleManager.profilesDenied
    open: root.accountOpen
    onToggled: root.accountOpen = !root.accountOpen
    body: ColumnLayout {
      spacing: 0
      Repeater {
        // A count, so the rows outlive each state
        model: TailscaleManager.profiles.length
        ChoiceRow {
          required property int index
          readonly property var profile: TailscaleManager.profiles[index] ?? null
          glyph: "person"
          title: profile ? (profile.nickname || profile.account) : ""
          subtitle: profile ? [profile.nickname && profile.nickname !== profile.account ? profile.account : "", profile.tailnet].filter(s => s).join(" · ") : ""
          chosen: profile?.selected ?? false
          onPicked: TailscaleManager.switchAccount(profile.id)
        }
      }
      ChoiceRow {
        glyph: "person_add"
        title: I18n.tr("Add account")
        onPicked: TailscaleManager.addAccount()
      }
    }
  }

  Fold {
    visible: root.canAct && TailscaleManager.connected && (root.exitOptions.length > 0 || TailscaleManager.exitNode !== "")
    icon: "alt_route"
    label: I18n.tr("Exit node")
    value: TailscaleManager.exitNode || I18n.tr("None")
    foldable: !TailscaleManager.profilesDenied
    open: root.exitOpen
    onToggled: root.exitOpen = !root.exitOpen
    body: ColumnLayout {
      spacing: 0
      ChoiceRow {
        glyph: "block"
        title: I18n.tr("None")
        chosen: TailscaleManager.exitNode === ""
        onPicked: TailscaleManager.setExitNode("")
      }
      Repeater {
        // A count, so the rows outlive each state
        model: root.exitOptions.length
        ChoiceRow {
          required property int index
          readonly property var peer: root.exitOptions[index] ?? null
          glyph: "public"
          title: peer?.name ?? ""
          subtitle: peer ? (peer.online ? peer.ips[0] ?? "" : I18n.tr("Offline")) : ""
          chosen: peer?.exitNode ?? false
          onPicked: TailscaleManager.setExitNode(peer.ips[0] ?? "")
        }
      }
      PrefRow {
        visible: TailscaleManager.prefs.known
        key: "exitNodeAllowLAN"
        label: I18n.tr("Allow local network access")
      }
    }
  }

  Fold {
    visible: root.canAct && TailscaleManager.connected && TailscaleManager.prefs.known
    icon: "tune"
    label: I18n.tr("Options")
    // I18n.tr("Subnet routes") I18n.tr("Tailscale DNS") I18n.tr("Shields up")
    value: [TailscaleManager.prefs.acceptRoutes ? "Subnet routes" : "", TailscaleManager.prefs.acceptDNS ? "Tailscale DNS" : "", TailscaleManager.prefs.shieldsUp ? "Shields up" : ""].filter(s => s).map(s => I18n.tr(s)).join(" · ")
    foldable: !TailscaleManager.profilesDenied
    open: root.optionsOpen
    onToggled: root.optionsOpen = !root.optionsOpen
    body: ColumnLayout {
      spacing: Widget.spacing / 2
      PrefRow {
        key: "acceptRoutes"
        label: I18n.tr("Use subnet routes")
      }
      PrefRow {
        key: "acceptDNS"
        label: I18n.tr("Use Tailscale DNS")
      }
      PrefRow {
        key: "shieldsUp"
        label: I18n.tr("Shields up (block incoming connections)")
      }
    }
  }

  // Warnings while connected (stopped, tailscaled only repeats the state),
  // in a column of its own, so the panel's column can flip (Panel.flips)
  ColumnLayout {
    visible: TailscaleManager.connected && TailscaleManager.health.length > 0
    Layout.fillWidth: true
    spacing: root.spacing
    Repeater {
      // a count, so the rows outlive each state
      model: TailscaleManager.health.length
      StyledText {
        required property int index
        Layout.fillWidth: true
        overflow: "wrap"
        text: TailscaleManager.health[index] ?? ""
        role: "caption"
        tone: "warning"
      }
    }
  }
  StyledText {
    visible: !isNaN(root.keyDays) && root.keyDays < 7
    Layout.fillWidth: true
    overflow: "wrap"
    text: root.keyDays <= 0 ? I18n.tr("This machine's key has expired: log in again.") : I18n.tr("This machine's key expires in {0} days.", Math.ceil(root.keyDays))
    role: "caption"
    tone: "warning"
  }
  StyledText {
    visible: TailscaleManager.lastError !== ""
    Layout.fillWidth: true
    overflow: "wrap"
    text: TailscaleManager.lastError
    role: "caption"
    tone: "error"
  }

  StyledSeparator {
    visible: TailscaleManager.known
    Layout.fillWidth: true
  }

  // Grows to list every device (from compact, to the full layout)
  wantedHeight: !TailscaleManager.connected ? 0 : root.compact ? 1 : root.height > 0 ? root.height + list.overflow : 0

  Skeleton {
    visible: !TailscaleManager.known
    Layout.fillWidth: true
    lines: 3
  }

  DeviceList {
    id: list
    visible: TailscaleManager.known
    embedded: root.embedded
    on: TailscaleManager.available && TailscaleManager.connected
    offIcon: "signal_disconnected"
    offMessage: !TailscaleManager.available ? I18n.tr("Tailscale isn't installed") : I18n.tr("Not connected")
    count: root.shownPeers.length
    emptyText: I18n.tr("No other devices")
    delegate: PeerRow {}
  }
}
