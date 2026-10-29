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
  property bool importing: false
  property string importNote: ""
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
  // The script refreshes Waybar by signal (pkill -RTMIN+N waybar), which
  // reaches nothing here
  readonly property bool signalsWaybar: {
    if (root.scriptPath === "")
      return false;
    return /RTMIN/.test(FileManager.read(root.scriptPath) ?? "");
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
        text: I18n.tr("New custom widget")
        onClicked: root.editor.add()
      }

      // Presets: names declared in CustomWidgetData.presets
      StyledComboEntry {
        Layout.fillWidth: true
        value: ""
        icon: "auto_awesome"
        placeholderText: I18n.tr("From a preset…")
        options: CustomWidgetData.presets.map((preset, index) => ({
              "value": String(index),
              "label": I18n.tr(preset.name),
              "icon": preset.icon
            }))
        onPicked: value => {
          const preset = CustomWidgetData.presets[Number(value)];
          if (preset)
            root.editor.add(Object.assign({}, preset, {
              "name": I18n.tr(preset.name)
            }));
        }
      }

      StyledTextButton {
        Layout.bottomMargin: Widget.spacing
        implicitHeight: Widget.height
        iconText: root.importing ? "expand_less" : "input"
        text: I18n.tr("Import from Waybar…")
        onClicked: {
          root.importing = !root.importing;
          root.importNote = "";
        }
      }

      // Paste a custom/* block, or a whole config
      ColumnLayout {
        visible: root.importing
        Layout.fillWidth: true
        Layout.bottomMargin: Widget.spacing
        spacing: Widget.spacing / 2

        StyledTextArea {
          id: waybarText
          Layout.fillWidth: true
          Layout.preferredHeight: Widget.height * 4
          input.font.family: "monospace"
          placeholderText: I18n.tr("Paste a \"custom/…\" module from your Waybar config, or the whole config")
        }
        RowLayout {
          Layout.fillWidth: true
          StyledText {
            Layout.fillWidth: true
            text: root.importNote
            wrapMode: Text.WordWrap
            textSize: Appearance.fontSizeBy(-2)
            opacity: 0.8
          }
          StyledTextButton {
            implicitHeight: Widget.height
            iconText: "download"
            text: I18n.tr("Import")
            onClicked: {
              const result = root.editor.importWaybar(waybarText.text);
              root.importNote = result.error ? I18n.tr("Couldn't read it: {0}", result.error) : I18n.tr("Added {0}.", result.count);
              if (!result.error)
                waybarText.text = "";
            }
          }
        }
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

        StyledText {
          visible: root.signalsWaybar
          Layout.fillWidth: true
          text: I18n.tr("This script refreshes Waybar with a signal (pkill -RTMIN…), which does nothing here: change it to run {0}.", `axiom ipc customWidgets refresh ${root.definition?.refreshName || root.definition?.id || ""}`)
          textColor: Theme.warning
          wrapMode: Text.WordWrap
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
