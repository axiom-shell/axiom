pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.components.reusable

// The Idle section's first card (its `x-card`): whether axiom is watching
// for idle, what holds it off now, and a warning when another program
// answers apps' requests to keep the screen on
FieldGroup {
  id: root

  readonly property string status: IdleManager.status

  readonly property color statusColor: {
    switch (root.status) {
    case "running":
      return Theme.success;
    case "inhibited":
      return Theme.accent;
    case "unsupported":
    case "unavailable":
      return Theme.warning;
    }
    return Theme.foregroundAlt;
  }

  readonly property string statusLabel: {
    switch (root.status) {
    case "running":
      return I18n.tr("Watching");
    case "inhibited":
      return I18n.tr("Held off");
    case "unsupported":
      return I18n.tr("Unsupported");
    case "unavailable":
      return I18n.tr("Not running");
    }
    return I18n.tr("Off");
  }

  readonly property string detail: {
    switch (root.status) {
    case "off":
      return I18n.tr("axiom leaves idle to you: a daemon such as hypridle, if you run one.");
    case "unsupported":
      return I18n.tr("The compositor doesn't tell axiom when you're idle (ext-idle-notify), so nothing happens when you step away.");
    case "unavailable":
      return I18n.tr("axiom's daemon isn't running this shell, so nothing watches for idle.");
    case "inhibited":
      return I18n.tr("An app is keeping the screen on: the steps below wait until it lets go.");
    }
    return I18n.tr("axiom dims, locks and turns the screens off on these settings, and locks before the computer sleeps.");
  }

  headerExtras: [
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  StyledText {
    text: root.detail
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // What holds idle off (i18n: the sources, chosen at runtime:
  // I18n.tr("Keeping awake") for caffeine)
  Repeater {
    model: Idle.enabled ? IdleManager.inhibitors : []

    delegate: RowLayout {
      id: inhibitor
      required property var modelData
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledIcon {
        text: inhibitor.modelData.source === "caffeine" ? "coffee" : "visibility"
        textColor: Theme.accent
      }

      StyledText {
        Layout.fillWidth: true
        text: inhibitor.modelData.source === "caffeine" ? I18n.tr("Keeping awake") : inhibitor.modelData.reason ? `${inhibitor.modelData.app}: ${inhibitor.modelData.reason}` : inhibitor.modelData.app
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
