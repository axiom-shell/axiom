pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.ui
import qs.components.forms
import qs.components.reusable

// The ScreenSharing section's first card (its `x-card`): which portal
// shares the screen under this compositor and whether it's installed, the
// line that points it at axiom's picker (applied once, on a click), and a
// restart of the portal so it takes effect
FieldGroup {
  id: root

  readonly property var portal: ScreenShareManager.portal
  readonly property bool hookedUp: IntegrationHookupManager.isDone("screenSharing")

  // "unsupported" | "off" | "missing" | "todo" | "ready"
  readonly property string status: {
    if (!root.portal)
      return "unsupported";
    if (!ScreenSharingConfig.enabled)
      return "off";
    if (!ScreenShareManager.portalInstalled || !ScreenShareManager.axiomPortalInstalled)
      return "missing";
    return root.hookedUp ? "ready" : "todo";
  }

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
      return I18n.tr("Point the portal at axiom's picker once: Apply below, then restart the portal.");
    }
    return I18n.tr("Apps ask axiom's picker what to share. Restart the portal if you just applied the change.");
  }

  Component.onCompleted: ScreenShareManager.checkPortal()

  headerExtras: [
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  StyledText {
    text: root.detail
    textColor: root.status === "missing" ? Theme.error : Theme.foreground
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  IntegrationHookup {
    Layout.fillWidth: true
    integration: "screenSharing"
    active: ScreenSharingConfig.enabled && root.status !== "missing" && root.status !== "unsupported"
    doneText: I18n.tr("The portal asks axiom's picker.")
    todoText: I18n.tr("The portal needs a line to ask axiom's picker: copy it, or Apply to add it for you.")
  }

  RowLayout {
    visible: ScreenSharingConfig.enabled && root.hookedUp
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
