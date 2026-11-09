pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable

// The optional programs features use (DependencyManager.tools; one is
// there when any of its alternatives is), each installed or not, and the
// commands that install the missing ones on this distribution
// (DependencyManager.installLines), or just their names on one axiom has
// no package names for. The onboarder's Checks and Settings › System's
// Optional packages. Checks them when built (`check()` again)
ColumnLayout {
  id: root

  // Tools to a line (Settings' wide card: 2)
  property int columns: 1

  readonly property var missing: DependencyManager.tools.filter(tool => DependencyManager.toolFound(tool) === false)
  readonly property bool checked: DependencyManager.tools.every(tool => DependencyManager.toolFound(tool) !== undefined)
  // Every command to look up, alternatives too
  readonly property var commands: [].concat(...DependencyManager.tools.map(tool => DependencyManager.commandsOf(tool)))
  // The commands to install
  readonly property var wanted: root.missing.map(tool => tool.command)
  readonly property var installLines: DependencyManager.installLines(root.wanted)

  function check() {
    DependencyManager.check(root.commands);
  }

  Component.onCompleted: root.check()

  Layout.fillWidth: true
  spacing: Widget.spacing

  GridLayout {
    Layout.fillWidth: true
    columns: root.columns
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing

    Repeater {
      model: DependencyManager.tools

      delegate: RowLayout {
        id: tool
        required property var modelData
        readonly property var present: DependencyManager.toolFound(modelData)
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: Widget.spacing

        StyledIcon {
          text: tool.present === undefined ? "hourglass_empty" : tool.present ? "check_circle" : "cancel"
          textColor: tool.present === undefined ? Theme.foregroundInactive : tool.present ? Theme.success : Theme.warning
        }

        StyledLabel {
          text: DependencyManager.toolCommand(tool.modelData)
          textFamily: "monospace"
        }

        StyledLabel {
          Layout.fillWidth: true
          // I18n.tr: purposes are declared in DependencyManager
          text: I18n.tr(tool.modelData.purpose)
          textColor: Theme.foregroundAlt
          elide: Text.ElideRight
        }
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
      text: root.installLines.length > 0 ? I18n.tr("To install what's missing:") : I18n.tr("Install these with your package manager: {0}", root.wanted.join(", "))
      wrapMode: Text.WordWrap
    }

    CodeLine {
      visible: root.installLines.length > 0
      text: root.installLines.join("\n")
    }
  }
}
