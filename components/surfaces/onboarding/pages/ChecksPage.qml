pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.components.reusable

// What's missing: the icon font, and the programs features use
// (DependencyManager.tools; one is there when any of its alternatives is,
// as the login screen's compositor), with the commands that install them on this
// distribution (DependencyManager.installLines), or just their names on one
// axiom has no package names for
OnboardingPage {
  id: root

  title: I18n.tr("Checks")
  intro: I18n.tr("axiom uses a few programs for some of its features. Everything else works without them.")

  readonly property var missing: DependencyManager.tools.filter(tool => DependencyManager.toolFound(tool) === false)
  readonly property bool checked: DependencyManager.tools.every(tool => DependencyManager.toolFound(tool) !== undefined)
  // Every command to look up, alternatives too
  readonly property var commands: [].concat(...DependencyManager.tools.map(tool => DependencyManager.commandsOf(tool)))
  // What to install: commands, and "iconFont" for the icon font
  readonly property var wanted: (DependencyManager.iconFontInstalled ? [] : ["iconFont"]).concat(root.missing.map(tool => tool.command))
  readonly property var installLines: DependencyManager.installLines(root.wanted)

  Component.onCompleted: DependencyManager.check(root.commands)

  Notice {
    visible: !DependencyManager.iconFontInstalled
    tone: "error"
    text: I18n.tr("The icon font ({0}) isn't installed, so icons show as words. Install it with the command below, then restart the shell.", Appearance.iconFamily)
  }

  Notice {
    visible: root.checked && root.wanted.length === 0
    tone: "success"
    text: I18n.tr("Everything axiom uses is installed.")
  }

  Repeater {
    model: DependencyManager.tools

    delegate: RowLayout {
      id: tool
      required property var modelData
      readonly property var present: DependencyManager.toolFound(modelData)
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledIcon {
        text: tool.present === undefined ? "hourglass_empty" : tool.present ? "check_circle" : "cancel"
        textColor: tool.present === undefined ? Theme.foregroundInactive : tool.present ? Theme.success : Theme.warning
      }

      StyledText {
        text: DependencyManager.label(DependencyManager.toolCommand(tool.modelData))
        textFamily: "monospace"
      }

      StyledText {
        Layout.fillWidth: true
        // I18n.tr: purposes are declared in DependencyManager
        text: I18n.tr(tool.modelData.purpose)
        textColor: Theme.foregroundAlt
        elide: Text.ElideRight
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: root.wanted.length > 0
    spacing: Widget.spacing

    StyledText {
      Layout.topMargin: Widget.spacing
      Layout.fillWidth: true
      text: root.installLines.length > 0 ? I18n.tr("To install what's missing:") : I18n.tr("Install these with your package manager: {0}", root.wanted.map(key => DependencyManager.label(key)).join(", "))
      wrapMode: Text.WordWrap
    }

    CodeLine {
      visible: root.installLines.length > 0
      text: root.installLines.join("\n")
    }
  }

  StyledTextButton {
    text: I18n.tr("Check again")
    iconText: "refresh"
    onClicked: DependencyManager.check(root.commands)
  }
}
