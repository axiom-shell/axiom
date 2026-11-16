pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.session
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
    onClicked: SettingsManager.commitValues(RecommendedSetupManager.appKeys.reduce((values, key) => {
      values["ThemeIntegrations." + key] = true;
      return values;
    }, {}))
  }

  // Two columns of rows, the first half of the list in the left one
  readonly property int half: Math.ceil(ThemeManager.integrations.length / 2)

  Component {
    id: integrationRow

    SwitchRow {
      id: integration
      required property string modelData
      readonly property bool present: root.installed(modelData)

      label: I18n.tr(ThemeManager.integrationTitle(modelData))
      checked: ThemeIntegrations[modelData] === true
      onToggled: on => {
        const values = {};
        values["ThemeIntegrations." + integration.modelData] = on;
        SettingsManager.commitValues(values);
      }

      leading: StyledIcon {
        text: integration.present ? "check_circle" : "radio_button_unchecked"
        textColor: integration.present ? Style.success : Style.textFaint
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing * 3
    uniformCellSizes: true

    FormColumn {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop

      Repeater {
        model: ThemeManager.integrations.slice(0, root.half)
        delegate: integrationRow
      }
    }

    FormColumn {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop

      Repeater {
        model: ThemeManager.integrations.slice(root.half)
        delegate: integrationRow
      }
    }
  }

  // The switched-on integrations' hookups: the line to add, and Apply
  // (i18n: keys from the schema: integration titles)
  SectionHeading {
    Layout.topMargin: Widget.spacing
    visible: root.hookups.length > 0
    title: root.hookups.every(key => IntegrationHookupManager.isDone(key)) ? I18n.tr("Every app you turned on is set up") : I18n.tr("Finish setting up")
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
        role: "label"
        tone: "accent"
      }

      IntegrationHookup {
        Layout.fillWidth: true
        integration: hookup.modelData
      }
    }
  }
}
