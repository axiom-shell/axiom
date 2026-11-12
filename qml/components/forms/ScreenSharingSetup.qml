pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.compositor
import qs.services.system
import qs.services.ui
import qs.components.reusable

// Screen sharing set up: which portal shares the screen under this
// compositor and whether it's installed, the line that points it at axiom's
// picker (applied once, on a click), a restart of the portal so it takes
// effect, and a try of the picker. Under niri there is no hookup and no
// restart: the daemon adds the portal's line while axiom runs and takes it
// out when it stops (a link as the file: the user adds the line by hand). The body of the ScreenSharing card
// (ScreenSharingStatus, whose card shows `statusLabel` in its header) and
// of the onboarder's System page.
ColumnLayout {
  id: root

  spacing: Widget.spacing * 1.5

  readonly property var portal: ScreenShareManager.portal
  readonly property bool niri: CompositorManager.kind === "niri"
  readonly property bool hookedUp: root.niri ? ScreenShareManager.portalLine.state === "on" : IntegrationHookupManager.isDone("screenSharing")

  // "unsupported" | "off" | "missing" | "checking" (niri's line, not read yet) | "todo" | "ready"
  readonly property string status: {
    if (!root.portal)
      return "unsupported";
    if (!ScreenSharingConfig.enabled)
      return "off";
    if (!ScreenShareManager.portalInstalled || !ScreenShareManager.axiomPortalInstalled)
      return "missing";
    if (root.niri && ScreenShareManager.portalLine.state === "")
      return "checking";
    return root.hookedUp ? "ready" : "todo";
  }

  readonly property string _automaticText: I18n.tr("Automatic while axiom runs: axiom adds its portal line as it starts and takes it out when it stops (a share running then ends).")

  readonly property color statusColor: {
    switch (root.status) {
    case "ready":
      return Theme.success;
    case "todo":
      return Theme.warning;
    case "missing":
      return Theme.error;
    }
    return Theme.foregroundAlt;
  }

  readonly property string statusLabel: {
    switch (root.status) {
    case "ready":
      return I18n.tr("Set up");
    case "todo":
      return I18n.tr("Not set up");
    case "missing":
      return I18n.tr("Not installed");
    case "unsupported":
      return I18n.tr("Unavailable");
    case "checking":
      return I18n.tr("Checking…");
    }
    return I18n.tr("Off");
  }

  readonly property string detail: {
    switch (root.status) {
    case "unsupported":
      return I18n.tr("axiom doesn't know this compositor's screen-share portal.");
    case "off":
      return I18n.tr("Apps share through {0}'s own picker.", root.portal.package);
    case "missing":
      return !ScreenShareManager.portalInstalled ? I18n.tr("Install {0}: apps share the screen through it.", root.portal.package) : I18n.tr("axiom's own portal file (axiom.portal) isn't installed: run axiom's install.sh again, or reinstall its package.");
    case "todo":
      if (root.niri)
        return ScreenShareManager.portalLine.state === "link" ? I18n.tr("{0} is a link (dotfiles?), so axiom won't change it every session: add this line under [preferred] yourself:", Paths.shortenHome(ScreenShareManager.portalLine.path)) : ScreenShareManager.portalLine.error !== "" ? ScreenShareManager.portalLine.error : root._automaticText;
      return I18n.tr("Point the portal at axiom's picker once: Apply below, then restart the portal.");
    }
    if (root.niri)
      return root._automaticText;
    return I18n.tr("Apps ask axiom's picker what to share. Restart the portal if you just applied the change.");
  }

  Component.onCompleted: ScreenShareManager.checkPortal()

  // The daemon edits the portal's file as the switch changes: looked at once
  // when it has had a moment
  Connections {
    target: ScreenSharingConfig
    function onEnabledChanged() {
      _recheck.restart();
    }
  }

  Timer {
    id: _recheck
    interval: 1000
    onTriggered: ScreenShareManager.checkPortal()
  }

  StyledText {
    text: root.detail
    textColor: root.status === "missing" ? Theme.error : Theme.foreground
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  SetupLines {
    visible: root.niri && ScreenSharingConfig.enabled && ScreenShareManager.portalLine.state === "link"
    hint: Paths.shortenHome(ScreenShareManager.portalLine.path)
    lines: ScreenShareManager.portalLine.line
    onCopyClicked: ClipboardManager.copyText(ScreenShareManager.portalLine.line)
  }

  IntegrationHookup {
    visible: !root.niri
    Layout.fillWidth: true
    integration: "screenSharing"
    active: ScreenSharingConfig.enabled && root.status !== "missing" && root.status !== "unsupported"
    doneText: I18n.tr("The portal asks axiom's picker.")
    todoText: I18n.tr("The portal needs a line to ask axiom's picker: copy it, or Apply to add it for you.")
  }

  RowLayout {
    visible: !root.niri && ScreenSharingConfig.enabled && root.hookedUp
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("The portal reads its config as it starts: restart it once after applying. A share running now stops.")
      textColor: Theme.foregroundInactive
      textSize: Appearance.fontSizeBy(-1)
      wrapMode: Text.WordWrap
    }

    StyledTextButton {
      iconText: "restart_alt"
      text: I18n.tr("Restart the portal")
      onClicked: ScreenShareManager.restartPortal()
    }
  }

  StyledTextButton {
    visible: ScreenSharingConfig.enabled
    iconText: "screen_share"
    text: I18n.tr("Try the picker")
    tooltipText: I18n.tr("Opens the picker without sharing anything")
    onClicked: ScreenShareManager.openTest()
  }
}
