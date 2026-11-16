pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// Custom widgets page, Module tab: the element library and the selected
// element down the left, the full height of the tab, and in the column beside
// it the previews (the module as it's drawn: the bar widget's popout, and the
// sizes a page may give it), the layer strip (the base elements and a button
// per screen), the selected screen's form, and the layouts editor's canvas
// filling the rest, editing the layer's elements as it edits a submenu's
// modules (drag in, move, resize from any side, push, box-select, guides,
// undo). The module's box fits the elements of every layer; the base is drawn
// dimmed under a screen being edited. The previews draw the edited screen's
// sample (kept in the definition, else the last one seen live:
// CustomWidgetsEditor.previewFields), so every screen can be designed before
// the script reaches it.
Item {
  id: root

  required property var grid
  // The height the tab has (the page's, less its header)
  required property real availableHeight
  // The inspector column's width (BaseView.inspectorWidth)
  required property real inspectorWidth
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var views: root.definition?.module?.views ?? []
  readonly property var view: root.views[root.editor.viewIndex] ?? null
  readonly property var designSize: CustomWidgetData.designSize(CustomWidgetData.allElements(root.definition?.module), root.definition?.module?.size)
  // The screen whose button a menu is open for
  property int menuView: 0

  width: parent?.width ?? 0
  height: root.availableHeight

  ElementEditorLayout {
    id: layout
    anchors.fill: parent
    inspectorWidth: root.inspectorWidth
    elements: root.editor.layerElements
    editable: root.definition !== null
    card: root.grid?.unit ?? Widget.px(400)
    underlay: root.view && root.view.base ? (root.definition?.module?.elements ?? []).map(e => ({
          "place": e.place,
          "label": e.name || e.options?.label || e.type,
          "element": e
        })) : []

    canvasTop: [
      ModulePreviews {
        definition: root.definition
        card: layout.card
        designSize: root.designSize
        tabHeight: root.availableHeight
      },
      ScreenStrip {
        views: root.views
        onMenuRequested: (index, item, x, y) => {
          root.menuView = index;
          chipMenu.openAt(item, x, y);
        }
      },
      ScreenForm {}
    ]

    // A screen button's menu (menuView: the screen)
    StyledContextMenu {
      id: chipMenu
      parent: layout
      items: [
        {
          "id": "rename",
          "icon": "edit",
          "text": I18n.tr("Rename")
        },
        {
          "id": "duplicate",
          "icon": "content_copy",
          "text": I18n.tr("Duplicate")
        },
        {
          "id": "left",
          "icon": "arrow_back",
          "text": I18n.tr("Move left"),
          "enabled": root.menuView > 0
        },
        {
          "id": "right",
          "icon": "arrow_forward",
          "text": I18n.tr("Move right"),
          "enabled": root.menuView < root.views.length - 1
        },
        {
          "id": "remove",
          "icon": "delete",
          "text": I18n.tr("Remove"),
          "danger": true
        }
      ]
      onTriggered: id => {
        const index = root.menuView;
        if (id === "rename") {
          root.editor.selectView(index);
          root.editor.focusScreenName = true;
        } else if (id === "duplicate") {
          root.editor.duplicateView(index);
        } else if (id === "left") {
          root.editor.moveView(index, index - 1);
        } else if (id === "right") {
          root.editor.moveView(index, index + 1);
        } else if (id === "remove") {
          root.editor.removeView(index);
        }
      }
    }
  }
}
