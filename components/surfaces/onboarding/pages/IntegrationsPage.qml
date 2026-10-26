pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.session
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// How axiom fits into the system: self-updates, the launcher's clipboard
// history, whether axiom handles idle (Idle.enabled), whether axiom's
// lock screen locks (Lockscreen.mode), and whether it's the
// polkit agent (Polkit.enabled): idle and polkit off by default,
// recommended on. Then the login screen (GreeterManager): off by default,
// and set up only from its Install button (a password prompt), never by
// picking its card. Last, theme integrations (other apps in axiom's
// colors), marked by whether the app is installed, and the switched-on
// ones' hookups (IntegrationHookup)
OnboardingPage {
  id: root

  // axiom is the login screen (or behind axiom: still set up)
  readonly property bool greeterSet: GreeterManager.status === "installed" || GreeterManager.status === "outdated"
  // Its card picked, before Install
  property bool greeterChosen: false

  title: I18n.tr("Integrations")
  intro: I18n.tr("How axiom fits into the rest of your system: updates, idle, locking, password prompts and the login screen, then other apps in axiom's colors.")

  // The switched-on integrations with something to hook up
  readonly property var hookups: ThemeManager.integrations.filter(key => ThemeIntegrations[key] === true && IntegrationHookupManager.targets(key).length > 0)

  function installed(key) {
    const commands = ThemeManager.integrationCommands(key);
    return commands.length === 0 || commands.some(command => DependencyManager.found[command] === true);
  }

  Component.onCompleted: {
    DependencyManager.check([].concat(...ThemeManager.integrations.map(key => ThemeManager.integrationCommands(key))));
    GreeterManager.check();
  }

  // A package updates with the system
  StyledText {
    visible: !Paths.packaged
    text: I18n.tr("Keeping axiom up to date")
    font.bold: true
  }

  SettingRows {
    visible: !Paths.packaged
    Layout.fillWidth: true
    paths: ["SelfUpdate.mode", "SelfUpdate.channel"]
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Clipboard history")
    font.bold: true
  }

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("Type : in the launcher to search what you've copied. axiom keeps it in memory only and skips what password managers mark as sensitive; turn it off if you copy passwords from apps that don't.")
    wrapMode: Text.WordWrap
  }

  SettingRows {
    Layout.fillWidth: true
    paths: ["Launcher.providers.clipboard.enabled"]
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Idle")
    font.bold: true
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "bedtime"
      title: I18n.tr("Let axiom handle idle")
      description: I18n.tr("Dims, locks and turns the screens off when you're away, set up from axiom's settings, and locks before the computer sleeps. Remove any hypridle you start yourself.")
      selected: Idle.enabled
      recommended: true
      onClicked: SettingsManager.commitValues({
        "Idle.enabled": true
      })
    }

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "tune"
      title: I18n.tr("Use my own")
      description: I18n.tr("Leaves idle to a daemon you run yourself, such as hypridle.")
      selected: !Idle.enabled
      onClicked: SettingsManager.commitValues({
        "Idle.enabled": false
      })
    }
  }

  SettingRows {
    Layout.fillWidth: true
    visible: Idle.enabled
    paths: ["Idle.dim.timeout", "Idle.lock.timeout", "Idle.screenOff.timeout", "Idle.suspend.timeout"]
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: !Idle.enabled && LockscreenConfig.mode !== "none"
    spacing: Widget.spacing

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("To lock after some idle time with your own hypridle, point its general section in ~/.config/hypr/hypridle.conf at axiom:")
      wrapMode: Text.WordWrap
    }

    CodeLine {
      text: "lock_cmd = axiom lock\nbefore_sleep_cmd = loginctl lock-session"
    }
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Lock screen")
    font.bold: true
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "lock"
      title: I18n.tr("Use axiom's lock screen")
      description: I18n.tr("Locks through the session-lock protocol and unlocks with your password (PAM), in your theme and laid out on the Layouts page.")
      selected: LockscreenConfig.mode === "quickshell"
      recommended: true
      onClicked: SettingsManager.commitValues({
        "Lockscreen.mode": "quickshell"
      })
    }

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "tune"
      title: I18n.tr("Use my own")
      description: I18n.tr("Leaves locking to a locker you set up yourself.")
      selected: LockscreenConfig.mode === "none"
      onClicked: SettingsManager.commitValues({
        "Lockscreen.mode": "none"
      })
    }
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Authentication prompts")
    font.bold: true
  }

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("When an app needs administrator rights (installing updates, mounting a drive, changing system settings), a polkit agent asks for your password. A session has only one.")
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "admin_panel_settings"
      title: I18n.tr("Use axiom's prompt")
      description: I18n.tr("The screen dims and the prompt opens in the middle, in axiom's theme. Stops any other agent, such as hyprpolkitagent.")
      selected: PolkitConfig.enabled
      recommended: true
      onClicked: SettingsManager.commitValues({
        "Polkit.enabled": true
      })
    }

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "tune"
      title: I18n.tr("Use my own")
      description: I18n.tr("Leaves the prompt to the agent you start yourself, such as hyprpolkitagent.")
      selected: !PolkitConfig.enabled
      onClicked: SettingsManager.commitValues({
        "Polkit.enabled": false
      })
    }
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Login screen")
    font.bold: true
  }

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("Axiom can be the screen you log in on (through greetd), laid out on the Layouts page like the lock screen.")
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "login"
      title: I18n.tr("Use axiom's login screen")
      description: I18n.tr("Your theme, wallpapers and monitor layout from the first screen on. Installing it asks for your password once.")
      selected: root.greeterSet || root.greeterChosen
      onClicked: root.greeterChosen = true
    }

    OptionCard {
      // Equal halves, as tall as the taller one
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      icon: "tune"
      title: I18n.tr("Keep my own")
      description: I18n.tr("Leaves the login screen to your display manager (SDDM, GDM, greetd's own greeters).")
      selected: !root.greeterSet && !root.greeterChosen
      onClicked: root.greeterChosen = false
    }
  }

  GreeterSetup {
    visible: root.greeterSet || root.greeterChosen
    Layout.fillWidth: true
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Other apps in axiom's colors")
    font.bold: true
  }

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("axiom can color other apps to match its theme. Each one writes only its own axiom file; once it's on, below shows the line that loads it from the app's config, to copy or to apply for you. A tick marks the apps you have installed.")
    wrapMode: Text.WordWrap
  }

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

        StyledText {
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
