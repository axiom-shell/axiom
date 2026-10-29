pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.content.base

// i18n: keys from the schema (titles, descriptions)
// Custom widgets page, left: the definitions (add, duplicate, remove), then
// the selected one's script: what runs and how, picked from a file or
// typed, with the head of the script when it's a file.
Item {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var schema: ConfigManager.configSchema.definitions.CustomWidget.properties
  readonly property string scriptPath: root.editor.scriptPath(root.definition?.command)
  // The first lines of the script, read when its path changes
  readonly property string scriptHead: {
    if (root.scriptPath === "")
      return "";
    const text = FileManager.read(root.scriptPath);
    return text === null ? "" : text.split("\n").slice(0, 40).join("\n");
  }

  TitledCard {
    anchors.fill: parent
    title: I18n.tr("Custom widgets")
    scrollKey: "CustomWidgets/list"
    showActions: false

    headerExtras: ColumnLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      Repeater {
        model: root.editor.items.length

        delegate: ListEntryRow {
          id: entry
          required property int index
          readonly property var item: root.editor.items[index] ?? ({})

          icon: entry.item.icon || "widgets"
          label: entry.item.name || entry.item.id || ""
          selected: root.editor.selectedIndex === entry.index
          dimmed: !entry.item.command
          changed: root.editor.changed(entry.index)
          onClicked: root.editor.selectDefinition(entry.index)

          RowAction {
            row: entry
            iconText: "content_copy"
            tooltipText: I18n.tr("Copy this custom widget")
            onClicked: root.editor.duplicate(entry.index)
          }
          RowAction {
            row: entry
            danger: true
            iconText: "close"
            tooltipText: I18n.tr("Remove this custom widget")
            onClicked: root.editor.remove(entry.index)
          }
        }
      }

      AddEntryButton {
        Layout.topMargin: Widget.spacing
        Layout.bottomMargin: Widget.spacing
        text: I18n.tr("New custom widget")
        onClicked: root.editor.add()
      }
    }

    // A ColumnLayout's Repeater re-runs on every draft edit: built once a
    // definition is selected, keyed by it
    KeyedLoader {
      id: script
      Layout.fillWidth: true
      Layout.preferredHeight: script.childrenRect.height
      key: root.definition ? root.definition.id : ""

      sourceComponent: ColumnLayout {
        width: script.width
        spacing: Widget.spacing

        FieldGroup {
          Layout.fillWidth: true
          title: I18n.tr("Script")

          SchemaPropertiesForm {
            Layout.fillWidth: true
            propertiesSchema: Utils.pick(root.schema, order)
            order: ["name", "icon", "command", "mode", "interval", "output", "execIf", "refreshName"]
            values: root.definition ?? ({})
            onEdited: (path, value) => root.editor.set(path, value)
          }

          StyledTextButton {
            implicitHeight: Widget.height
            iconText: "folder_open"
            text: I18n.tr("Pick a script…")
            onClicked: FilePickerManager.pick(root, I18n.tr("Pick a script"), {
              "start": root.scriptPath !== "" ? root.scriptPath.replace(/\/[^/]*$/, "") : "~",
              "shortenHome": true
            }, path => root.editor.set("command", path))
          }

          StyledText {
            Layout.fillWidth: true
            text: I18n.tr("Run it again from anywhere: {0}", `axiom ipc customWidgets refresh ${root.definition?.refreshName || root.definition?.id || ""}`)
            wrapMode: Text.WrapAnywhere
            textSize: Appearance.fontSizeBy(-2)
            opacity: 0.6
          }
        }

        FieldGroup {
          visible: root.scriptHead !== ""
          Layout.fillWidth: true
          title: I18n.tr("The script")
          description: root.scriptPath

          StyledText {
            Layout.fillWidth: true
            text: root.scriptHead
            textFamily: "monospace"
            textSize: Appearance.fontSizeBy(-3)
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            opacity: 0.8
          }
        }
      }
    }
  }
}
