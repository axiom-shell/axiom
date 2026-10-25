pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.session
import qs.components.reusable

// The Idle section's first card (its `x-card`): whether axiom's hypridle
// is running, where its config is, and Restart
FieldGroup {
  id: root

  readonly property string status: HypridleManager.status

  readonly property color statusColor: {
    switch (root.status) {
    case "running":
      return Theme.success;
    case "stopped":
      return Theme.warning;
    case "missing":
      return Theme.error;
    }
    return Theme.foregroundAlt;
  }

  readonly property string statusLabel: {
    switch (root.status) {
    case "running":
      return I18n.tr("Running");
    case "stopped":
      return I18n.tr("Not running");
    case "missing":
      return I18n.tr("Not installed");
    }
    return I18n.tr("Off");
  }

  readonly property string detail: {
    if (HypridleManager.installed === false)
      return I18n.tr("hypridle isn't installed. Install it to dim, lock and turn the screens off when you're away.");
    switch (root.status) {
    case "off":
      return I18n.tr("axiom leaves hypridle to you: your own ~/.config/hypr/hypridle.conf is used, if you run it.");
    case "stopped":
      return I18n.tr("axiom's hypridle isn't running. Restart it, or check that hypridle starts from a terminal.");
    }
    return I18n.tr("hypridle runs with the config axiom writes from these settings.");
  }

  headerExtras: [
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  StyledText {
    text: root.detail
    textColor: HypridleManager.installed === false ? Theme.error : Theme.foreground
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // How to install it here (nothing on a distribution axiom has no
  // package names for)
  CodeLine {
    visible: HypridleManager.installed === false && text !== ""
    text: DependencyManager.installCommand("hypridle")
  }

  GridLayout {
    visible: Idle.enabled
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing / 2

    StyledText {
      text: I18n.tr("Config")
      opacity: 0.7
    }
    StyledText {
      text: HypridleManager.configPath
      textFamily: "monospace"
      elide: Text.ElideMiddle
      Layout.fillWidth: true
    }
  }

  StyledText {
    visible: Idle.enabled && HypridleManager.replacedOther
    text: I18n.tr("axiom stopped another hypridle, likely started by your own compositor config. Remove its autostart line so the two don't fight at login.")
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  RowLayout {
    visible: Idle.enabled && HypridleManager.installed === true
    Layout.fillWidth: true
    spacing: Widget.spacing

    Item {
      Layout.fillWidth: true
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Restart")
      onClicked: HypridleManager.restart()
    }
  }
}
