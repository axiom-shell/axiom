pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.views.base

// Custom widgets page, left: the definitions (add, duplicate, remove) pinned
// above, then the selected one's script: what runs and how, picked from a file or
// typed, with the head of the script when it's a file.
Item {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var schema: ConfigManager.configSchema.definitions.CustomWidget.properties
  readonly property string scriptPath: root.editor.scriptPath(root.definition?.command)
  // The script, read (its first 256 KiB, off the UI thread) when its path
  // changes: only a script, text starting with #!, not a program the
  // command names (an ELF)
  property string scriptText: ""
  onScriptPathChanged: root._readScript()
  Component.onCompleted: root._readScript()

  function _readScript() {
    const path = root.scriptPath;
    root.scriptText = "";
    if (path !== "")
      CommandManager.run(["head", "-c", "262144", "--", path], (code, out) => {
        if (path === root.scriptPath)
          root.scriptText = code === 0 && out.startsWith("#!") ? out : "";
      });
  }
  // Its first lines
  readonly property string scriptHead: root.scriptText.split("\n").slice(0, 40).join("\n")
  // The script refreshes Waybar by signal (pkill -RTMIN+N waybar), which
  // reaches nothing here
  readonly property bool signalsWaybar: /RTMIN/.test(root.scriptText)

  ToolPane {
    anchors.fill: parent
    title: I18n.tr("Custom widgets")
    headerIcon: "widgets"
    scrollKey: "CustomWidgets/list"
    showActions: false

    pinned: ColumnLayout {
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
          onRemoveRequested: root.editor.remove(entry.index)

          RowAction {
            row: entry
            iconText: "content_copy"
            tooltipText: I18n.tr("Duplicate")
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

      // The New flow: what kind of widget (a chooser, not a blank one at
      // once)
      AddEntryButton {
        id: newButton
        Layout.topMargin: Widget.spacing
        text: I18n.tr("New custom widget")
        onClicked: newMenu.openAt(newButton, 0, newButton.height)
      }

      StyledContextMenu {
        id: newMenu
        parent: root
        // Known scripts: names declared in CustomWidgetData.scriptPresets
        items: [
          {
            "id": "bar",
            "icon": "text_fields",
            "text": I18n.tr("Bar text from a script")
          },
          {
            "id": "card",
            "icon": "dashboard_customize",
            "text": I18n.tr("Interactive card")
          },
          {
            "id": "script",
            "icon": "auto_awesome",
            "text": I18n.tr("From a known script"),
            "submenu": CustomWidgetData.scriptPresets.map((preset, index) => ({
                  "id": "preset:" + index,
                  "icon": preset.icon,
                  "text": I18n.tr(preset.name)
                }))
          },
          {
            "id": "import",
            "icon": "input",
            "text": I18n.tr("Import a widget…")
          }
        ]
        onTriggered: id => {
          if (id === "bar")
            root.editor.addBlank();
          else if (id === "card")
            root.editor.openGallery();
          else if (id === "import")
            root.editor.openImport();
          else if (id.startsWith("preset:"))
            root.editor.addScript(CustomWidgetData.scriptPresets[Number(id.slice(7))]);
        }
      }

      // Paste what someone copied (or a Waybar custom/* module): the
      // Import form, in the inspector pane
      StyledTextButton {
        Layout.fillWidth: true
        Layout.bottomMargin: Widget.spacing
        implicitHeight: Widget.height
        iconText: "input"
        text: I18n.tr("Import a widget…")
        onClicked: root.editor.openImport()
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
            role: "caption"
            tone: "faint"
            overflow: "wrap"
          }
        }

        StyledText {
          visible: root.signalsWaybar
          Layout.fillWidth: true
          text: I18n.tr("This script refreshes Waybar with a signal (pkill -RTMIN…), which does nothing here: change it to run {0}.", `axiom ipc customWidgets refresh ${root.definition?.refreshName || root.definition?.id || ""}`)
          tone: "warning"
          overflow: "wrap"
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
            role: "micro"
            tone: "muted"
            // A long line wraps inside the card
            overflow: "wrap"
          }
        }
      }
    }
  }
}
