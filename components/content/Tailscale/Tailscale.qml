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
// overlay card (compact: devices online).
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

  // Something that needs the user before the rest works (operator rights,
  // a login): a tinted box with what and why, and one small button
  component Notice: Rectangle {
    id: notice
    property string icon
    property string title
    property string detail
    property string action
    property color tint: Theme.warning
    // The button works (not while another action runs, by default)
    property bool ready: !TailscaleManager.busy
    signal triggered

    Layout.fillWidth: true
    implicitHeight: noticeRow.implicitHeight + Widget.padding
    radius: Widget.radius
    color: Qt.alpha(notice.tint, 0.12)
    border.color: Qt.alpha(notice.tint, 0.4)
    border.width: Appearance.borderWidth

    RowLayout {
      id: noticeRow
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding / 2
      spacing: Widget.padding
      StyledIcon {
        text: notice.icon
        textColor: notice.tint
        textSize: Appearance.fontSizeBy(2)
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
          Layout.fillWidth: true
          text: notice.title
          wrapMode: Text.Wrap
          font.bold: true
          textSize: Appearance.fontSizeBy(-1)
        }
        StyledText {
          Layout.fillWidth: true
          visible: notice.detail !== ""
          text: notice.detail
          wrapMode: Text.Wrap
          textSize: Appearance.fontSizeBy(-3)
          textColor: Theme.foregroundAlt
        }
      }
      StyledTextButton {
        enabled: notice.ready
        opacity: enabled ? 1 : 0.5
        text: notice.action
        textSize: Appearance.fontSizeBy(-2)
        textPadding: Widget.smallPadding
        backgroundColor: notice.tint
        textColor: Theme.background
        onClicked: notice.triggered()
      }
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
        textColor: foldRow.hovered && fold.foldable ? Theme.accent : Theme.foregroundAlt
      }
      StyledText {
        text: fold.label
        textSize: Appearance.fontSizeBy(-1)
      }
      StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: fold.value
        elide: Text.ElideRight
        textSize: Appearance.fontSizeBy(-2)
        textColor: Theme.foregroundAlt
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
  component ChoiceRow: Rectangle {
    id: choice
    property string icon
    property string title
    property string subtitle
    property bool chosen: false
    signal picked

    Layout.fillWidth: true
    implicitHeight: Math.max(choiceColumn.implicitHeight, Widget.iconButton) + Widget.spacing
    radius: Widget.radius
    color: choiceHover.hovered && choiceArea.enabled ? Qt.alpha(Theme.backgroundHighlight, 0.5) : Qt.alpha(Theme.backgroundHighlight, 0)

    ColorGlide on color {}

    HoverHandler {
      id: choiceHover
    }
    MouseArea {
      id: choiceArea
      anchors.fill: parent
      enabled: !choice.chosen && !TailscaleManager.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.picked()
    }
    RowLayout {
      anchors.fill: parent
      anchors.rightMargin: Widget.padding
      spacing: Widget.spacing
      StyledIcon {
        Layout.preferredWidth: Widget.iconButton
        horizontalAlignment: Text.AlignHCenter
        text: choice.chosen ? "check" : choice.icon
        textColor: choice.chosen ? Theme.accent : Theme.foregroundAlt
      }
      ColumnLayout {
        id: choiceColumn
        Layout.fillWidth: true
        spacing: 0
        StyledText {
          Layout.fillWidth: true
          text: choice.title
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-1)
          textColor: choice.chosen ? Theme.accent : Theme.foreground
        }
        StyledText {
          Layout.fillWidth: true
          visible: choice.subtitle !== ""
          text: choice.subtitle
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-3)
          textColor: Theme.foregroundAlt
        }
      }
    }
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

    StyledText {
      Layout.fillWidth: true
      text: pref.label
      elide: Text.ElideRight
      textSize: Appearance.fontSizeBy(-2)
    }
    StyledSwitch {
      id: prefSwitch
      enabled: !TailscaleManager.busy
      opacity: enabled ? 1 : 0.5
      checked: TailscaleManager.prefs[pref.key] ?? false
      onToggled: TailscaleManager.setPref(pref.key, checked)
    }
  }

  // Without operator rights tailscaled refuses every change: polkit can
  // grant them (`tailscale set --operator=$USER`). First, so it's by the
  // bar whichever way the popout grows.
  Notice {
    visible: root.canAct && TailscaleManager.profilesDenied
    icon: "admin_panel_settings"
    title: I18n.tr("Tailscale needs your permission")
    detail: I18n.tr("Allow your user to connect, switch accounts and change options.")
    action: I18n.tr("Grant access")
    onTriggered: TailscaleManager.grantOperator()
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
    // Connected or not; while connecting or disconnecting, where it's going
    StyledSwitch {
      id: connectSwitch
      visible: root.canAct
      enabled: !TailscaleManager.busy && !TailscaleManager.profilesDenied
      opacity: enabled ? 1 : 0.5
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
    icon: "login"
    tint: Theme.accent
    title: I18n.tr("Log in to Tailscale")
    detail: TailscaleManager.authURL ? I18n.tr("Finish logging in in your browser.") : I18n.tr("This machine isn't logged in.")
    action: I18n.tr("Log in")
    // Opening a link doesn't wait for `tailscale up` to give up
    ready: TailscaleManager.authURL !== "" || !TailscaleManager.busy
    onTriggered: TailscaleManager.authURL ? TailscaleManager.openLogin() : TailscaleManager.connect()
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
      text: TailscaleManager.version ? I18n.tr("Tailscale {0}", TailscaleManager.version) : ""
      visible: text !== ""
      textSize: Appearance.fontSizeBy(-2)
      textColor: Theme.foregroundAlt
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
          icon: "person"
          title: profile ? (profile.nickname || profile.account) : ""
          subtitle: profile ? [profile.nickname && profile.nickname !== profile.account ? profile.account : "", profile.tailnet].filter(s => s).join(" · ") : ""
          chosen: profile?.selected ?? false
          onPicked: TailscaleManager.switchAccount(profile.id)
        }
      }
      ChoiceRow {
        icon: "person_add"
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
        icon: "block"
        title: I18n.tr("None")
        chosen: TailscaleManager.exitNodeIP === ""
        onPicked: TailscaleManager.setExitNode("")
      }
      Repeater {
        // A count, so the rows outlive each state
        model: root.exitOptions.length
        ChoiceRow {
          required property int index
          readonly property var peer: root.exitOptions[index] ?? null
          icon: "public"
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
        wrapMode: Text.Wrap
        text: TailscaleManager.health[index] ?? ""
        textSize: Appearance.fontSizeBy(-2)
        textColor: Theme.warning
      }
    }
  }
  StyledText {
    visible: !isNaN(root.keyDays) && root.keyDays < 7
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: root.keyDays <= 0 ? I18n.tr("This machine's key has expired: log in again.") : I18n.tr("This machine's key expires in {0} days.", Math.ceil(root.keyDays))
    textSize: Appearance.fontSizeBy(-2)
    textColor: Theme.warning
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
