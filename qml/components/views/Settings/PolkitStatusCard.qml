pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.components.reusable

// The Polkit section's first card (its `x-card`): whether axiom is the
// session's polkit agent, and which other agents it stopped
FieldGroup {
  id: root

  readonly property string status: PolkitManager.status

  readonly property color statusColor: {
    switch (root.status) {
    case "running":
      return Theme.success;
    case "starting":
      return Theme.warning;
    case "blocked":
      return Theme.error;
    }
    return Theme.foregroundAlt;
  }

  readonly property string statusLabel: {
    switch (root.status) {
    case "running":
      return I18n.tr("Running");
    case "starting":
      return I18n.tr("Starting");
    case "blocked":
      return I18n.tr("Not running");
    }
    return I18n.tr("Off");
  }

  readonly property string detail: {
    switch (root.status) {
    case "off":
      return I18n.tr("Another polkit agent answers apps' password requests, if you run one (hyprpolkitagent, KDE's, GNOME's).");
    case "starting":
      return I18n.tr("axiom is registering as the session's polkit agent.");
    case "blocked":
      return I18n.tr("axiom couldn't become the polkit agent: another agent it doesn't know holds the session, or axiom isn't running in a login session. Stop the other agent and turn this off and on again.");
    }
    return I18n.tr("axiom answers apps' password requests.");
  }

  headerExtras: [
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  StyledText {
    text: root.detail
    textColor: root.status === "blocked" ? Theme.error : Theme.foreground
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledText {
    visible: PolkitConfig.enabled && PolkitManager.replaced.length > 0
    text: I18n.tr("axiom stopped {0}, likely started by your own compositor config or a systemd unit. Remove its autostart line or disable the unit so the two don't race at login.", PolkitManager.replaced.join(", "))
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }
}
