pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// Window rules page, right: the selected rule. Its name, icon and switch;
// its kinds of window and their conditions; what happens when one opens
// (greyed where the compositor can't); and the rule's problems. Built anew
// for each selection (a KeyedLoader), so typed text never lands on another
// rule; conditions are read by index.
ColumnLayout {
  id: root

  readonly property var editor: WindowRulesManager.editor
  readonly property var rule: root.editor.selected ?? ({})
  readonly property var schema: ConfigManager.configSchema.definitions.WindowRule.properties
  readonly property var issues: WindowRuleIssues.of(root.editor.report, root.rule.id)
  readonly property var row: WindowRuleIssues.rowOf(root.editor.report, root.rule.id)
  readonly property var general: WindowRuleIssues.general(root.issues)
  // The effects only the daemon places, after the window opens
  readonly property var placedNotes: (root.row?.placed ?? []).map(key => ({
        "level": "info",
        "text": I18n.tr("{0}: applied just after the window opens.", I18n.tr(root.schema.window.properties[key]?.title ?? key))
      }))
  readonly property var generalNotes: root.general.map(issue => ({
        "level": "error",
        "text": root.editor.issueText(issue)
      }))

  spacing: Widget.spacing * 2

  SchemaPropertiesForm {
    Layout.fillWidth: true
    propertiesSchema: Utils.pick(root.schema, order)
    order: ["name", "icon", "enabled"]
    values: root.rule
    onEdited: (path, value) => root.editor.set(path, value)
  }

  FieldGroup {
    title: I18n.tr(root.schema.windows.title)
    description: I18n.tr(root.schema.windows.description)

    Repeater {
      model: root.rule.windows?.length ?? 0

      delegate: ColumnLayout {
        id: kindItem
        required property int index
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledText {
          visible: kindItem.index > 0
          text: I18n.tr("or")
          opacity: 0.6
        }

        KindBlock {
          Layout.fillWidth: true
          k: kindItem.index
        }
      }
    }

    StyledTextButton {
      implicitHeight: Widget.height
      iconText: "add"
      text: I18n.tr("Add another kind")
      onClicked: root.editor.addKind()
    }
  }

  FieldGroup {
    title: I18n.tr(root.schema.window.title)
    description: I18n.tr(root.schema.window.description)

    SchemaPropertiesForm {
      Layout.fillWidth: true
      propertiesSchema: root.schema.window.properties
      order: ["float", "size", "center", "workspace", "follow", "special", "monitor", "fullscreen", "maximize", "pin", "opacity", "noBlur", "noFocus", "noScreenShare", "tearing"]
      values: root.rule.window ?? ({})
      onEdited: (path, value) => root.editor.set(["window"].concat(path), value)
    }

    IssueList {
      issues: root.placedNotes
    }
  }

  FieldGroup {
    visible: root.generalNotes.length > 0
    title: I18n.tr("Problems")
    description: I18n.tr("A rule with problems is saved but not applied.")

    IssueList {
      issues: root.generalNotes
    }
  }
}
