pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// Layouts editor, left: the edge menus (drag to reorder, click to edit),
// and New menu
ColumnLayout {
  id: root

  required property var dragLayer

  spacing: Widget.spacing / 2

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Edge menus")
    font.bold: true
    textColor: Theme.accent
  }

  EntryListTarget {
    id: menuList
    dragLayer: root.dragLayer
    moveKind: "menu-move"
    count: EdgeMenuManager.localMenus?.length ?? 0
    onDropRequested: (drag, index) => EdgeMenuManager.moveMenu(drag.index, index)

    Repeater {
      model: menuList.count

      EntryListRow {
        id: entry
        readonly property var entryMenu: EdgeMenuManager.localMenus[entry.index] ?? ({})

        list: menuList
        icon: Utils.edgeArrow(entry.entryMenu.edge)
        label: EdgeMenuManager.menuLabel(entry.entryMenu, entry.index)
        selected: OverlayManager.editTarget === "menu" && EdgeMenuManager.selectedMenuIndex === entry.index
        dimmed: entry.entryMenu.enabled === false
        changed: EdgeMenuManager.menuChanged(entry.index)
        onClicked: OverlayManager.editMenu(entry.index)

        // Held open on screen by the editor
        badges: StyledIcon {
          visible: EdgeMenuManager.previewing !== "" && EdgeMenuManager.previewing === entry.entryMenu.id
          text: "visibility"
          textColor: entry.ink
        }

        RowAction {
          row: entry
          iconText: "content_copy"
          tooltipText: I18n.tr("Duplicate this menu")
          onClicked: EdgeMenuManager.duplicateMenu(entry.index)
        }

        RowAction {
          row: entry
          danger: true
          iconText: "close"
          tooltipText: I18n.tr("Remove this menu")
          onClicked: EdgeMenuManager.removeMenu(entry.index)
        }
      }
    }
  }

  AddEntryButton {
    Layout.topMargin: Widget.spacing / 2
    text: I18n.tr("New menu")
    onClicked: {
      EdgeMenuManager.addMenu();
      OverlayManager.editMenu(EdgeMenuManager.selectedMenuIndex);
    }
  }
}
