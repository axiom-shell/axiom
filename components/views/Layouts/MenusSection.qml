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
    count: OverlayManager.menus.localMenus?.length ?? 0
    onDropRequested: (drag, index) => OverlayManager.menus.moveMenu(drag.index, index)

    Repeater {
      model: menuList.count

      EntryListRow {
        id: entry
        readonly property var entryMenu: OverlayManager.menus.localMenus[entry.index] ?? ({})

        list: menuList
        icon: Utils.edgeArrow(entry.entryMenu.edge)
        label: OverlayManager.menus.menuLabel(entry.entryMenu, entry.index)
        selected: OverlayManager.editTarget === "menu" && OverlayManager.menus.selectedMenuIndex === entry.index
        dimmed: entry.entryMenu.enabled === false
        changed: OverlayManager.menus.menuChanged(entry.index)
        onClicked: OverlayManager.editMenu(entry.index)

        // Held open on screen by the editor
        badges: StyledIcon {
          visible: OverlayManager.menus.previewing !== "" && OverlayManager.menus.previewing === entry.entryMenu.id
          text: "visibility"
          textColor: entry.ink
        }

        RowAction {
          row: entry
          iconText: "content_copy"
          tooltipText: I18n.tr("Duplicate this menu")
          onClicked: OverlayManager.menus.duplicateMenu(entry.index)
        }

        RowAction {
          row: entry
          danger: true
          iconText: "close"
          tooltipText: I18n.tr("Remove this menu")
          onClicked: OverlayManager.menus.removeMenu(entry.index)
        }
      }
    }
  }

  AddEntryButton {
    Layout.topMargin: Widget.spacing / 2
    text: I18n.tr("New menu")
    onClicked: {
      OverlayManager.menus.addMenu();
      OverlayManager.editMenu(OverlayManager.menus.selectedMenuIndex);
    }
  }
}
