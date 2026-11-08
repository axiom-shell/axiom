pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.session
import qs.services.ui
import qs.components.reusable
import qs.components.content.parts
import qs.components.forms

// How axiom fits into the system: self-updates, the launcher's clipboard
// history, whether axiom handles idle (Idle.enabled), whether axiom's
// lock screen locks (Lockscreen.mode), and whether it's the
// polkit agent (Polkit.enabled): idle and polkit off by default,
// recommended on. Last, the login screen (GreeterManager): off by default,
// and set up only from its Install button (a password prompt), never by
// picking its card. Other apps in axiom's colors are the next page's
// (AppColorsPage)
OnboardingPage {
  id: root

  // axiom is the login screen (or behind axiom: still set up)
  readonly property bool greeterSet: GreeterManager.status === "installed" || GreeterManager.status === "outdated"
  // Its card picked, before Install
  property bool greeterChosen: false

  title: I18n.tr("System")
  intro: I18n.tr("How axiom fits into the rest of your system: updates, idle, locking, password prompts and the login screen.")

  Component.onCompleted: GreeterManager.check()

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
      description: I18n.tr("Dims, locks and turns the screens off when you're away, set up from axiom's settings, and locks before the computer sleeps. Stop any idle daemon you start yourself.")
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
      description: I18n.tr("Leaves idle to a daemon you run yourself.")
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
      text: I18n.tr("To lock after some idle time with your own idle daemon, have it lock with this command, also before the computer sleeps:")
      wrapMode: Text.WordWrap
    }

    CodeLine {
      text: "axiom lock"
    }
  }

  StyledText {
    Layout.fillWidth: true
    visible: !Idle.enabled
    text: I18n.tr("Caffeine keeps your own idle daemon off only if it honours logind's idle inhibitors.")
    wrapMode: Text.WordWrap
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
      description: I18n.tr("The screen dims and the prompt opens in the middle, in axiom's theme. Stops any other agent you run.")
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
      description: I18n.tr("Leaves the prompt to the agent you start yourself.")
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
}
