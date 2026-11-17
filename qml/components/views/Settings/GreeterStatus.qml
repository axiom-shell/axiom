pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.components.forms

// The top of the Login screen card (the section's `x-intro`): whether axiom
// is the login screen, and setting it up, updating or removing it
// (GreeterSetup). `status` and `statusTone` are the card's header chip
IntroColumn {
  id: root

  readonly property string stage: GreeterManager.status

  readonly property string statusTone: {
    switch (root.stage) {
    case "installed":
      return "success";
    case "outdated":
    case "notInstalled":
      return "warning";
    case "noGreetd":
    case "noCompositor":
    case "noClone":
    case "checkFailed":
      return "error";
    }
    return "neutral";
  }

  readonly property string status: {
    switch (root.stage) {
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
    case "noClone":
      return I18n.tr("Unavailable");
    case "checking":
      return I18n.tr("Checking");
    case "checkFailed":
      return I18n.tr("Check failed");
    }
    return I18n.tr("Off");
  }

  Component.onCompleted: GreeterManager.check()

  StatusLine {
    visible: root.stage === "off"
    text: I18n.tr("Your display manager shows its own login screen. Axiom's runs under greetd, laid out on the Layouts page like the lock screen.")
    Layout.fillWidth: true
  }

  StatusLine {
    visible: root.stage === "installed" || root.stage === "outdated"
    text: I18n.tr("Axiom is greetd's login screen. Lay it out on the Layouts page; it shows your theme, wallpapers and monitor layout as they are when you save.")
    Layout.fillWidth: true
  }

  GreeterSetup {
    Layout.fillWidth: true
  }
}
