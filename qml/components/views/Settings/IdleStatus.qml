pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.components.reusable

// The top of the Idle card (the section's `x-intro`): whether axiom is
// watching for idle, what holds it off now, and a warning when another
// program answers apps' requests to keep the screen on. `status` and
// `statusColor` are the card's header chip
ColumnLayout {
  id: root

  readonly property string stage: IdleManager.status

  readonly property color statusColor: {
    switch (root.stage) {
    case "running":
      return Theme.success;
    case "inhibited":
      return Theme.accent;
    case "noLock":
    case "unsupported":
    case "unavailable":
      return Theme.warning;
    }
    return Theme.foregroundAlt;
  }

  readonly property string status: {
    switch (root.stage) {
    case "running":
      return I18n.tr("Watching");
    case "inhibited":
      return I18n.tr("Held off");
    case "noLock":
      return I18n.tr("Doesn't lock");
    case "unsupported":
      return I18n.tr("Unsupported");
    case "unavailable":
      return I18n.tr("Not running");
    }
    return I18n.tr("Off");
  }

  readonly property string detail: {
    switch (root.stage) {
    case "off":
      return I18n.tr("axiom leaves idle to you: a daemon such as hypridle, if you run one. Caffeine holds off a daemon that honours logind's idle inhibitors, as hypridle does; swayidle and others that don't still act while it's on.");
    case "unsupported":
      return I18n.tr("The compositor doesn't tell axiom when you're idle (ext-idle-notify), so nothing happens when you step away.");
    case "unavailable":
      return I18n.tr("axiom's daemon isn't running this shell, so nothing watches for idle.");
    case "inhibited":
      if (IdleManager.inhibitors.length > 0 && IdleManager.inhibitors.every(held => held.source === "caffeine"))
        return I18n.tr("Caffeine is keeping the screen on: the steps below wait until it's turned off.");
      if (IdleManager.inhibitors.length > 0 && IdleManager.inhibitors.every(held => held.source === "caffeine" || held.source === "windowRule"))
        return I18n.tr("A window rule is keeping the screen on: the steps below wait until its window goes.");
      return I18n.tr("An app is keeping the screen on: the steps below wait until it lets go.");
    case "noLock":
      return I18n.tr("The lock screen is your own locker, but its Lock command is empty or loginctl lock-session, which comes back to axiom: nothing locks. Set the Lock command to your locker.");
    }
    return I18n.tr("axiom dims, locks and turns the screens off on these settings, and locks before the computer sleeps.");
  }

  spacing: Widget.spacing * 1.5

  StyledText {
    text: root.detail
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // What holds idle off (i18n: the sources, chosen at runtime:
  // I18n.tr("Keeping awake") for caffeine, I18n.tr("Window rule: {0}", name))
  Repeater {
    model: Idle.enabled ? IdleManager.inhibitors.length : 0

    delegate: RowLayout {
      id: inhibitor
      required property int index
      readonly property var held: IdleManager.inhibitors[index] ?? ({})
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledIcon {
        text: inhibitor.held.source === "caffeine" ? "coffee" : inhibitor.held.source === "windowRule" ? "select_window" : "visibility"
        textColor: Theme.accent
      }

      StyledLabel {
        Layout.fillWidth: true
        text: inhibitor.held.source === "caffeine" ? I18n.tr("Keeping awake") : inhibitor.held.source === "windowRule" ? I18n.tr("Window rule: {0}", inhibitor.held.app) : inhibitor.held.reason ? `${inhibitor.held.app}: ${inhibitor.held.reason}` : inhibitor.held.app
        elide: Text.ElideRight
      }
    }
  }

  StyledText {
    visible: Idle.enabled && IdleManager.screensaverHolder !== ""
    text: I18n.tr("{0} answers apps asking to keep the screen on, so axiom doesn't see them. If it's hypridle, remove its autostart line so the two don't both act when you're away.", IdleManager.screensaverHolder)
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }
}
