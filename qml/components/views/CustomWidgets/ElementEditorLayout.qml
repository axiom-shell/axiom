pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom
import qs.components.views.Layouts

// Custom widgets page, Module tab: the element library and the selected
// element down the left (the tab's full height), and on the right what the
// host puts above (`canvasTop`) over the layouts editor's canvas filling the
// rest, in one GridDragLayer (as LayoutsEditorLayout holds the layouts editor's),
// so elements are carried from the library onto the module.
GridDragLayer {
  id: root

  // The selected definition's elements, and whether there's one
  property var elements: []
  property bool editable: false
  // The inspector column's width: the host's BaseView.inspectorWidth
  property real inspectorWidth: 0
  // The base elements, drawn dimmed under the canvas while a screen is edited
  // ([{ place, label, element }])
  property var underlay: []
  // One grid unit in pixels at the module's design size: an element is drawn
  // at the size it has there and scaled into its tile
  property real card: Widget.px(400)
  // What the host puts above the canvas (the previews, the layers, a screen's form)
  property alias canvasTop: topColumn.data

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

  // An element drawn in its tile (GridCanvas.tileContent): the real element
  // on the previewed sample, at the size it has in the module and scaled to
  // the tile, with its name (else its kind) in a chip while it is hovered or
  // selected; one the sample's `showWhen` hides is dimmed and says so. Never runs anything
  Component {
    id: elementTile

    Item {
      id: content

      // The element (the tile's module, or an underlay item's element)
      property var module: null
      readonly property var fields: CustomWidgetsManager.editor.previewFields ?? ({})
      readonly property bool hidden: !tileElement.shown
      readonly property real designWidth: Math.max(1, (content.module?.place?.w ?? 1) / CustomWidgetData.subCells * root.card)
      readonly property real designHeight: Math.max(1, (content.module?.place?.h ?? 1) / CustomWidgetData.subCells * root.card)
      readonly property real zoom: Math.min(content.width / content.designWidth, content.height / content.designHeight)
      readonly property string title: content.module ? (content.module.name || I18n.tr(CustomWidgetsConfig.elementKind(content.module.type)?.label ?? content.module.type)) : ""
      // Room above the tile inside the canvas, for the name chip (it re-reads
      // when the element moves or resizes: the place is read for that)
      readonly property real roomAbove: {
        const place = content.module?.place;
        return place && content.height >= 0 ? content.mapToItem(canvasHolder, 0, 0).y : 0;
      }
      opacity: content.hidden ? Style.opacityDisabled : 1

      // Centred in the tile, cut to it
      Item {
        id: clipped
        anchors.fill: parent
        clip: true

        Item {
          x: (content.width - content.designWidth * content.zoom) / 2
          y: (content.height - content.designHeight * content.zoom) / 2
          width: content.designWidth
          height: content.designHeight
          scale: content.zoom
          transformOrigin: Item.TopLeft
          readonly property real contentZoom: scale

          CustomElement {
            id: tileElement
            anchors.fill: parent
            anchors.margins: Widget.px(3)
            element: content.module ?? ({})
            fields: content.fields
            history: CustomWidgetsManager.history[CustomWidgetsManager.editor.selectedId] ?? ({})
            widgetId: CustomWidgetsManager.editor.selectedId
            actionsEnabled: false
            fallbackIcon: CustomWidgetsManager.editor.selected?.icon || "widgets"
            moduleFont: CustomWidgetsManager.editor.selected?.module?.font ?? ""
          }
        }
      }

      HoverHandler {
        id: tileHover
      }

      // Its name, while the pointer is on it or it is the selected element:
      // on the tile's top edge, outside it, so it never covers the element
      // (inside, at the top, only where the canvas has no room above)
      Row {
        id: chips
        readonly property bool above: content.roomAbove >= chips.height + Widget.px(2)
        visible: (tileHover.hovered || (content.module?.id ?? "") === (CustomWidgetsManager.editor.element?.id ?? null)) && content.width > Widget.px(56) && content.height > Widget.px(28)
        x: Widget.px(2)
        y: chips.above ? -chips.height - Widget.px(1) : Widget.px(2)
        z: 3
        spacing: Widget.px(2)

        StatusChip {
          text: content.title
          tone: "neutral"
        }
        StatusChip {
          visible: content.hidden
          text: I18n.tr("hidden")
          tone: "warning"
        }
      }
    }
  }

  // An element's menu (a right click selects it, or keeps its group):
  // `source` the element it was opened on, `others` the rest of its group
  StyledContextMenu {
    id: elementMenu
    parent: root
    property int source: -1
    property var others: []
    items: (elementMenu.others.length > 0 ? [
        {
          "id": "look",
          "icon": "format_paint",
          "text": I18n.tr("Copy look to the selected")
        }
      ] : []).concat([
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
    ])
    onTriggered: id => {
      const editor = CustomWidgetsManager.editor;
      const grid = editor.elements;
      if (id === "look") {
        editor.copyLook(elementMenu.source, elementMenu.others);
        return;
      }
      // The others of a group are left: the element acts alone
      grid.select(elementMenu.source);
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

    // The inspector, the tab's full height; it owns its header
    Surface {
      Layout.preferredWidth: root.inspectorWidth
      Layout.fillHeight: true
      tone: "surface"

      StyledScrollView {
        id: sideScroll
        anchors.fill: parent

        FormInset {
          width: sideScroll.availableWidth

          ElementInspector {
            Layout.fillWidth: true
            dragLayer: root
          }
        }
      }
    }

    // What is being looked at and edited (previews, the layers, the screen's
    // form: the host's `canvasTop`), then the canvas filling the rest
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Widget.spacing

      ColumnLayout {
        id: topColumn
        Layout.fillWidth: true
        // Never grows past its content: with a screen's form empty (the base)
        // the spare height went to it and left the canvas nothing
        Layout.maximumHeight: topColumn.implicitHeight
        spacing: Widget.spacing
      }

      // GridCanvas anchors itself to what holds it
      Item {
        id: canvasHolder
        Layout.fillWidth: true
        Layout.fillHeight: true

        GridCanvas {
          dragLayer: root
          modules: root.editable ? root.elements : null
          underlay: root.underlay
          tileContent: elementTile
          showActions: false
          contextKeepsGroup: true
          showUndo: false
          showMargins: false
          onTileContext: (index, tile, x, y) => {
            elementMenu.source = index;
            elementMenu.others = CustomWidgetsManager.editor.elements.group.filter(i => i !== index);
            elementMenu.openAt(tile, x, y);
          }
          title: I18n.tr("Module")
          icon: "widgets"
          emptyText: I18n.tr("Drag elements here from the left: the module's box fits them.")
          emptyHint: I18n.tr("An empty module: drag elements here from the left, or click one to add it where there's room.")
        }
      }
    }
  }
}
