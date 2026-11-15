pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.views.Layouts

// Custom widgets page, Module tab: the element library and the selected
// element down the left, and the layouts editor's canvas filling the rest,
// in one GridDragLayer (as LayoutsEditorLayout holds the layouts editor's),
// so elements are carried from the library onto the module.
GridDragLayer {
  id: root

  // The selected definition's elements, and whether there's one
  property var elements: []
  property bool editable: false
  // The base elements, drawn dimmed under the canvas while a screen is edited
  property var underlay: []

  // "Copy to screen ▸": the base, then each screen but the one edited
  readonly property var copyTargets: {
    const editor = CustomWidgetsManager.editor;
    const views = editor.selected?.module?.views ?? [];
    const targets = [];
    if (editor.viewIndex >= 0)
      targets.push({
        "id": "to:-1",
        "text": I18n.tr("Base")
      });
    views.forEach((view, i) => {
      if (i !== editor.viewIndex)
        targets.push({
          "id": "to:" + i,
          "text": view.name || view.id
        });
    });
    return targets;
  }

  editor: CustomWidgetsManager.editor.elements
  // Element kinds, not module types (schema labels)
  describe: type => {
    const kind = CustomWidgetsConfig.elementKind(type);
    return kind ? {
      "icon": kind.icon,
      "label": I18n.tr(kind.label)
    } : null;
  }
  // In grid units (4 sub-cells each)
  sizeLabel: (w, h) => I18n.tr("{0} × {1}", w / CustomWidgetData.subCells, h / CustomWidgetData.subCells)
  countLabel: n => I18n.tr("{0} elements", n)

  // An element's menu (a right click selects it)
  StyledContextMenu {
    id: elementMenu
    parent: root
    items: [
      {
        "id": "duplicate",
        "icon": "content_copy",
        "text": I18n.tr("Duplicate")
      },
      {
        "id": "copy",
        "icon": "move_item",
        "text": I18n.tr("Copy to screen"),
        "enabled": root.copyTargets.length > 0,
        "submenu": root.copyTargets
      },
      {
        "id": "remove",
        "icon": "delete",
        "text": I18n.tr("Remove"),
        "danger": true
      }
    ]
    onTriggered: id => {
      const grid = CustomWidgetsManager.editor.elements;
      if (id === "duplicate")
        grid.duplicateModule(grid.selected);
      else if (id === "remove")
        grid.removeModule(grid.selected);
      else if (id.startsWith("to:"))
        CustomWidgetsManager.editor.copyElementToView(Number(id.slice(3)));
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: Widget.spacing * 3

    // A box and a header like the canvas's, so the two read as a pair
    Surface {
      Layout.preferredWidth: Math.min(Widget.textPx(340), Math.round(root.width * 0.34))
      Layout.fillHeight: true
      tone: "surface"

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Widget.padding
        spacing: Widget.spacing

        CardHeader {
          icon: "category"
          title: I18n.tr("Elements")
          showActions: false
        }

        // While no element is selected: what the library is for
        StyledText {
          visible: root.editor.selected < 0
          Layout.fillWidth: true
          role: "caption"
          tone: "muted"
          overflow: "wrap"
          text: I18n.tr("Drag one onto the module, or click it to add it where there's room.")
        }

        StyledScrollView {
          id: sideScroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentPadding: 0

          ElementInspector {
            width: sideScroll.availableWidth
            dragLayer: root
          }
        }
      }
    }

    // GridCanvas anchors itself to what holds it
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      GridCanvas {
        dragLayer: root
        modules: root.editable ? root.elements : null
        underlay: root.underlay
        onTileContext: (index, tile, x, y) => elementMenu.openAt(tile, x, y)
        title: I18n.tr("Module")
        icon: "widgets"
        emptyText: I18n.tr("Drag elements here from the left: the module's box fits them.")
        emptyHint: I18n.tr("An empty module: drag elements here from the left, or click one to add it where there's room.")
      }
    }
  }
}
