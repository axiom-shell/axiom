pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.session
import qs.components.reusable

// Setting axiom up as the login screen (GreeterManager), shared by
// Settings → Login screen (GreeterStatusCard) and the onboarder: what
// Install changes, Install / Update / Remove (one password prompt each),
// what's left for the user to run, and what went wrong.
ColumnLayout {
  id: root

  readonly property string status: GreeterManager.status
  readonly property var report: GreeterManager.report
  readonly property bool busy: GreeterManager.elevating
  // Remove waits for a second click
  property bool confirmingRemove: false
  // What installs greetd and agreety here ("" on a distribution axiom has
  // no package names for)
  readonly property string installGreetd: DependencyManager.installCommand(["greetd", "agreety"])
  // What installs sway, the compositor it runs in ("" as above)
  readonly property string installSway: DependencyManager.installCommand(["sway"])

  spacing: Widget.spacing

  function bullet(text) {
    return "•  " + text;
  }

  // greetd missing: how to get it
  ColumnLayout {
    visible: root.status === "noGreetd"
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: root.installGreetd !== "" ? I18n.tr("The login screen runs under greetd, with its text login (agreety) as the fallback. Install them:") : I18n.tr("The login screen runs under greetd, with its text login (agreety) as the fallback. Install them with your package manager.")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    CodeLine {
      visible: text !== ""
      text: root.installGreetd
    }
  }

  // No compositor to run in: sway (plain sway is enough), or Hyprland.
  // Set up already, it falls back to agreety until one is installed
  ColumnLayout {
    visible: root.status === "noCompositor" || (root.report?.installed === true && root.report?.compositor === "")
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: root.installSway !== "" ? I18n.tr("The login screen runs in a compositor of its own: sway, or Hyprland when sway isn't installed. Neither is, so it would always fall back to greetd's text login. Install sway (plain sway is enough):") : I18n.tr("The login screen runs in a compositor of its own: sway, or Hyprland when sway isn't installed. Neither is, so it would always fall back to greetd's text login. Install sway with your package manager.")
      textColor: root.status === "noCompositor" ? Theme.foreground : Theme.warning
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    CodeLine {
      visible: text !== ""
      text: root.installSway
    }
  }

  // What Install does
  ColumnLayout {
    visible: root.status === "off" || root.status === "notInstalled"
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      text: I18n.tr("Install asks for your password once, then:")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    Repeater {
      model: [I18n.tr("Copies axiom's code (from where Code from below says) to /usr/share/axiom-greeter, for greetd's user to run (your home folder is private to you)."), I18n.tr("Makes /var/lib/axiom-greeter, with a folder of yours that axiom keeps the login screen's look and layout in: changing them later needs no password."), I18n.tr("Backs up /etc/greetd/config.toml, then changes only its default_session command, to start axiom's login screen in a compositor of its own (sway, else Hyprland).")]

      delegate: StyledText {
        required property string modelData
        text: root.bullet(modelData)
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.leftMargin: Widget.padding
      }
    }

    StyledText {
      text: I18n.tr("If the login screen ever fails to start, greetd's text login (agreety) takes its place. Remove puts greetd's config back.")
      opacity: 0.7
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }
  }

  // Behind axiom: why
  StyledText {
    visible: root.status === "outdated"
    text: root.report?.configured === false ? I18n.tr("greetd's config no longer starts axiom's login screen. Update points it back (after a backup).") : root.report?.installedSource !== GreeterManager.wantedSource ? I18n.tr("The login screen's code came from elsewhere than Code from now says. Update takes it from there, asking for your password.") : Paths.packaged ? I18n.tr("axiom's package was updated since its login screen was set up. It runs the new code already; Update refreshes its start-up files and fallback look, asking for your password.") : I18n.tr("Axiom changed since its login screen was set up. Its layout and look follow your settings already; Update brings its code up to date, asking for your password.")
    textColor: Theme.warning
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // Where the code comes from (Greeter.source, or the package), and what
  // that trusts
  StyledText {
    readonly property bool local: GreeterConfig.source === "local" && !Paths.packaged
    visible: root.report !== null && root.status !== "noGreetd" && root.status !== "noCompositor"
    // i18n: I18n.tr("the newest release") I18n.tr("the main branch")
    text: Paths.packaged ? I18n.tr("The login screen runs the copy of axiom your package manager installed, so it updates with the system. Only root can change it.") : local ? I18n.tr("Code from Local: Update copies your clone as it is, uncommitted changes included. Any program running as you can change that code before you next update, and the password prompt is then the only check. Choose Git unless you're working on axiom.") : I18n.tr("Code from Git: root fetches {0} from {1}, as axiom's own updates follow it. Nothing that can write to your clone can change what the login screen runs.", I18n.tr(SelfUpdate.channel === "main" ? "the main branch" : "the newest release"), root.report?.url || I18n.tr("your clone's remote"))
    textColor: local ? Theme.warning : Theme.foreground
    opacity: local ? 1 : 0.7
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // Set up: what's left to run, or that it's done
  ColumnLayout {
    visible: root.status === "installed" || root.status === "outdated"
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: GreeterManager.finishCommands.length > 0 ? I18n.tr("To finish, switch your display manager to greetd (it takes over at the next boot):") : I18n.tr("greetd shows it at the next login. To see it now, restart greetd, which ends this session:")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    Repeater {
      model: GreeterManager.finishCommands.length > 0 ? GreeterManager.finishCommands : ["sudo systemctl restart greetd.service"]

      delegate: CodeLine {
        required property string modelData
        text: modelData
      }
    }

    StyledText {
      text: I18n.tr("Fonts and cursor themes installed only in your home folder don't reach the login screen: install them system-wide to use them there.")
      opacity: 0.7
      textSize: Appearance.fontSizeBy(-1)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }
  }

  StyledText {
    visible: GreeterManager.lastError !== ""
    text: GreeterManager.lastError
    textColor: Theme.error
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      visible: root.busy
      text: I18n.tr("Waiting for your password...")
      opacity: 0.7
    }

    Item {
      Layout.fillWidth: true
    }

    StyledTextButton {
      visible: root.status === "noGreetd" || root.status === "noCompositor" || root.status === "checking" || root.status === "checkFailed"
      enabled: root.status !== "checking"
      implicitHeight: Widget.height - Widget.px(4)
      iconText: "refresh"
      text: I18n.tr("Check again")
      onClicked: GreeterManager.check()
    }

    StyledTextButton {
      visible: root.status === "installed" || root.status === "outdated"
      enabled: !root.busy
      implicitHeight: Widget.height - Widget.px(4)
      iconText: root.confirmingRemove ? "warning" : "delete"
      text: root.confirmingRemove ? I18n.tr("Remove it?") : I18n.tr("Remove")
      onClicked: {
        if (!root.confirmingRemove) {
          root.confirmingRemove = true;
          confirmTimeout.restart();
          return;
        }
        root.confirmingRemove = false;
        GreeterManager.uninstall();
      }

      Timer {
        id: confirmTimeout
        interval: 3000
        onTriggered: root.confirmingRemove = false
      }
    }

    StyledTextButton {
      visible: root.status === "outdated"
      enabled: !root.busy
      implicitHeight: Widget.height - Widget.px(4)
      iconText: "system_update_alt"
      text: I18n.tr("Update")
      onClicked: GreeterManager.update()
    }

    StyledTextButton {
      visible: root.status === "off" || root.status === "notInstalled"
      enabled: !root.busy
      implicitHeight: Widget.height - Widget.px(4)
      iconText: "login"
      text: I18n.tr("Install")
      onClicked: GreeterManager.install()
    }
  }
}
