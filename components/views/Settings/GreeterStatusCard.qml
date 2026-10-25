pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.components.forms
import qs.components.reusable

// The Greeter section's first card (its `x-card`): whether axiom is the
// login screen, and setting it up, updating or removing it (GreeterSetup)
FieldGroup {
  id: root

  readonly property string status: GreeterManager.status

  readonly property color statusColor: {
    switch (root.status) {
    case "installed":
      return Theme.success;
    case "outdated":
    case "notInstalled":
      return Theme.warning;
    case "noGreetd":
    case "noCompositor":
    case "checkFailed":
      return Theme.error;
    }
    return Theme.foregroundAlt;
  }

  readonly property string statusLabel: {
    switch (root.status) {
    case "installed":
      return I18n.tr("Set up");
    case "outdated":
      return I18n.tr("Update available");
    case "notInstalled":
      return I18n.tr("Not installed");
    case "noGreetd":
      return I18n.tr("No greetd");
    case "noCompositor":
      return I18n.tr("No compositor");
    case "checking":
      return I18n.tr("Checking");
    case "checkFailed":
      return I18n.tr("Check failed");
    }
    return I18n.tr("Off");
  }

  headerExtras: [
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  Component.onCompleted: GreeterManager.check()

  StyledText {
    visible: root.status === "off"
    text: I18n.tr("Your display manager shows its own login screen. Axiom's runs under greetd, laid out on the Layouts page like the lock screen.")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.status === "installed" || root.status === "outdated"
    text: I18n.tr("Axiom is greetd's login screen. Lay it out on the Layouts page; it shows your theme, wallpapers and monitor layout as they are when you save.")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  GreeterSetup {
    Layout.fillWidth: true
  }
}
