pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.views.base

// Custom widgets page, left: the definitions (select, duplicate, remove) and
// New, which opens its chooser (a bar text, an interactive card, a known
// script, an import). The selected one's script is on the Data tab.
Item {
  id: root

  readonly property var editor: CustomWidgetsManager.editor

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
        Layout.bottomMargin: Widget.spacing
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
    }
  }
}
