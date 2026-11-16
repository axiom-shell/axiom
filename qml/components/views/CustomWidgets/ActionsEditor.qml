pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// Custom widgets page, Data tab: the selected definition's actions
// (actions.items), one ActionRow each, an Add button, the setting that reruns
// the script after one, and, folded, how a script runs them from outside.
// Rows are by count over the saved items.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var schema: ConfigManager.configSchema.definitions.CustomWidget.properties
  readonly property var items: root.definition?.actions?.items ?? []
  property bool scriptsOpen: false

  Layout.fillWidth: true
  spacing: Widget.spacing

  Repeater {
    model: root.items.length

    ActionRow {}
  }

  AddEntryButton {
    text: I18n.tr("Add an action")
    onClicked: root.editor.addAction({})
  }

  SchemaPropertiesForm {
    Layout.fillWidth: true
    propertiesSchema: Utils.pick(root.schema.actions.properties, order)
    order: ["refreshAfter"]
    values: root.definition?.actions ?? ({})
    onEdited: (path, value) => root.editor.set(["actions"].concat(path), value)
    changedAt: path => root.editor.changedAt(["actions"].concat(path))
    onDiscardAt: path => root.editor.discardAt(["actions"].concat(path))
  }

  FoldingSection {
    visible: root.items.length > 0
    title: I18n.tr("For scripts")
    collapsed: !root.scriptsOpen
    onToggled: root.scriptsOpen = !root.scriptsOpen

    Repeater {
      model: root.items.length

      StyledText {
        id: line
        required property int modelData
        readonly property var action: root.items[line.modelData] ?? null
        Layout.fillWidth: true
        text: I18n.tr("{0} — {1}", line.action?.id ?? "", `axiom ipc customWidgets act ${root.definition?.id ?? ""} ${line.action?.id ?? ""}`)
        textFamily: "monospace"
        role: "caption"
        tone: "muted"
        overflow: "wrap"
      }
    }
  }
}
