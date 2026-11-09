pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// Theme integrations (other apps in axiom's colors), the onboarding's last
// page before Checks: each marked by whether the app is installed, then
// the switched-on ones' hookups (IntegrationHookup). Optional: nothing on
// it needs a decision
OnboardingPage {
  id: root

  title: I18n.tr("App colors")
  intro: I18n.tr("axiom can color other apps to match its theme. Each one writes only its own axiom file; once it's on, below shows the line that loads it from the app's config, to copy or to apply for you. A tick marks the apps you have installed.")

  // The switched-on integrations with something to hook up
  readonly property var hookups: ThemeManager.integrations.filter(key => ThemeIntegrations[key] === true && IntegrationHookupManager.targets(key).length > 0)

  function installed(key) {
    const commands = ThemeManager.integrationCommands(key);
    return commands.length === 0 || commands.some(command => DependencyManager.found[command] === true);
  }

  Component.onCompleted: DependencyManager.check([].concat(...ThemeManager.integrations.map(key => ThemeManager.integrationCommands(key))))

  StyledTextButton {
    text: I18n.tr("Turn on for installed apps")
    iconText: "done_all"
    onClicked: SettingsManager.commitValues(ThemeManager.integrations.filter(key => root.installed(key) && key !== "gtk" && key !== "qt").reduce((values, key) => {
      values["ThemeIntegrations." + key] = true;
      return values;
    }, {}))
  }

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 3
    rowSpacing: Widget.spacing

    Repeater {
      model: ThemeManager.integrations

      delegate: RowLayout {
        id: integration
        required property string modelData
        readonly property bool present: root.installed(modelData)
        readonly property bool isOn: ThemeIntegrations[modelData] === true
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledIcon {
          text: integration.present ? "check_circle" : "radio_button_unchecked"
          textColor: integration.present ? Theme.success : Theme.foregroundInactive
        }

        StyledLabel {
          Layout.fillWidth: true
          text: I18n.tr(ThemeManager.integrationTitle(integration.modelData))
          elide: Text.ElideRight
          textColor: integration.present ? Theme.foreground : Theme.foregroundInactive
        }

        StyledSwitch {
          checked: integration.isOn
          onToggled: {
            const values = {};
            values["ThemeIntegrations." + integration.modelData] = checked;
            SettingsManager.commitValues(values);
          }
        }
      }
    }
  }

  // The switched-on integrations' hookups: the line to add, and Apply
  // (i18n: keys from the schema: integration titles)
  StyledText {
    Layout.topMargin: Widget.spacing
    visible: root.hookups.length > 0
    text: root.hookups.every(key => IntegrationHookupManager.isDone(key)) ? I18n.tr("Every app you turned on is set up") : I18n.tr("Finish setting up")
    font.bold: true
  }

  Repeater {
    model: root.hookups

    // Set up ones drop out once checked (Settings still shows them)
    delegate: ColumnLayout {
      id: hookup
      required property string modelData
      Layout.fillWidth: true
      visible: !IntegrationHookupManager.isDone(hookup.modelData)
      spacing: Widget.spacing / 2

      StyledText {
        text: I18n.tr(ThemeManager.integrationTitle(hookup.modelData))
        textColor: Theme.accent
        font.bold: true
      }

      IntegrationHookup {
        Layout.fillWidth: true
        integration: hookup.modelData
      }
    }
  }
}
