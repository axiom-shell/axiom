pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// One module on the layouts canvas: its icon and name (plus a hint for
// modules whose look depends on their properties). Click to edit it, drag
// it to move it (onto a module of its size: they swap; onto others: they
// make way), drag any edge or corner to resize it from that side. One
// that grows (`properties.grow`) shows how far, dashed, round it.
// Positioned and sized by GridCanvas.
Rectangle {
  id: root

  required property var dragLayer
  required property int index
  // { type, properties, place }
  property var module: null
  // One grid unit plus its gap, and the gap, at the canvas's scale
  required property real step
  required property real gap

  readonly property GridEditor editor: root.dragLayer.editor
  readonly property string type: root.module?.type ?? ""
  readonly property var place: root.module?.place ?? {
    "x": 0,
    "y": 0,
    "w": 1,
    "h": 1
  }
  readonly property bool selected: root.editor.isSelected(root.index)
  // Part of a group selected together: dragging it moves them all
  readonly property bool grouped: root.editor.group.includes(root.index)
  readonly property bool carried: root.dragLayer.draggingKind === "module-move" && (root.dragLayer.dragging.index === root.index || (root.dragLayer.dragging.group ?? []).includes(root.index))
  // Whether the press was with Shift or Ctrl (a tap then toggles it in
  // the selection)
  property bool _toggling: false

  // From the schema: a color property that fills the tile, and one shown
  // on it (OverlayConfig.moduleInfo)
  readonly property var info: OverlayConfig.moduleInfo(root.type)
  readonly property var props: root.module?.properties ?? {}
  readonly property bool filled: (root.info?.canvasFill ?? "") !== ""
  readonly property color fill: root.filled ? Theme.resolveColor(root.props[root.info.canvasFill]) : Theme.backgroundAlt
  readonly property color ink: root.filled ? Utils.getContrastColor(root.fill) : Theme.foreground
  readonly property string detail: {
    const value = root.info?.canvasDetail ? root.props[root.info.canvasDetail] : undefined;
    return Array.isArray(value) ? value.join(", ") : String(value ?? "");
  }

  // The side being dragged to resize it ("n", "ne", … "nw"), else ""
  property string resizing: ""
  readonly property bool small: root.width < Appearance.fontSize * 7 || root.height < Appearance.fontSize * 4

  z: root.selected || root.resizing !== "" ? 2 : 1
  // Set by GridCanvas, matching its lattice
  radius: Widget.radius
  color: root.fill
  border.color: root.selected ? Theme.accent : Theme.border
  border.width: root.selected ? Math.max(Appearance.borderWidth, 2) : Appearance.borderWidth
  opacity: root.carried ? 0.3 : 1

  Glide on opacity {}

  // How far it may grow (`properties.grow`, see ModuleGrid): { up, down }
  // rows (GridCanvas.growthOf), drawn as a dashed outline round its tallest,
  // under it
  property var growth: ({
      "up": 0,
      "down": 0
    })
  Canvas {
    id: growOutline
    visible: root.growth.up + root.growth.down > 0 && !root.carried
    z: -1
    y: -root.growth.up * root.step
    width: root.width
    height: root.height + (root.growth.up + root.growth.down) * root.step
    readonly property color ink: Theme.accent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onInkChanged: requestPaint()
    onPaint: {
      const ctx = getContext("2d");
      ctx.reset();
      ctx.globalAlpha = 0.7;
      ctx.strokeStyle = growOutline.ink;
      ctx.lineWidth = 1.5;
      ctx.setLineDash([5, 4]);
      ctx.beginPath();
      ctx.roundedRect(1, 1, width - 2, height - 2, root.radius, root.radius);
      ctx.stroke();
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - Widget.px(8)
    spacing: 2

    StyledIcon {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.dragLayer.moduleIcon(root.type)
      textColor: root.filled ? root.ink : Theme.accent
      textSize: root.small ? Appearance.fontSizeBy(2) : Appearance.fontSizeBy(8)
    }

    StyledText {
      width: parent.width
      visible: !root.small
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.dragLayer.moduleLabel(root.type)
      textColor: root.ink
      textSize: Appearance.fontSizeBy(-1)
      font.bold: true
    }

    StyledText {
      width: parent.width
      visible: text !== "" && !root.small
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.detail
      textColor: root.ink
      textSize: Appearance.fontSizeBy(-3)
      opacity: 0.75
    }
  }

  DragArea {
    id: area
    anchors.fill: parent
    cursorShape: root.dragLayer.dragging !== null ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    dragLayer: root.dragLayer
    payload: ({
        "kind": "module-move",
        "index": root.index,
        "group": root.grouped ? root.editor.group : [],
        "type": root.type,
        "icon": root.grouped ? "select_all" : root.dragLayer.moduleIcon(root.type),
        "label": root.grouped ? root.dragLayer.countLabel(root.editor.group.length) : root.dragLayer.moduleLabel(root.type)
      })
    onPressed: mouse => root._toggling = (mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier)) !== 0
    onTapped: {
      if (root._toggling)
        root.editor.toggleSelected(root.index);
      else
        root.editor.select(root.index);
    }
  }

  // Its size while it's resized: inside it at the bottom, or under a
  // small one
  Rectangle {
    visible: root.resizing !== ""
    z: 4
    x: (root.width - width) / 2
    y: root.small ? root.height + 4 : root.height - height - 6
    width: sizeText.implicitWidth + Widget.padding
    height: sizeText.implicitHeight + Widget.px(4)
    radius: height / 2
    color: Theme.accent

    StyledText {
      id: sizeText
      anchors.centerIn: parent
      readonly property var place: root.dragLayer.landingPlace ?? root.place
      text: root.dragLayer.sizeLabel(sizeText.place.w, sizeText.place.h)
      textColor: Theme.background
      textSize: Appearance.fontSizeBy(-2)
      font.bold: true
    }
  }

  // Resize zones along each edge and in each corner, thinner on a small
  // tile so its middle is still there to move it by. Dragging one moves
  // that side (or both, at a corner) by whole units; the others stay
  Repeater {
    model: root.dragLayer.dragging === null ? ["n", "ne", "e", "se", "s", "sw", "w", "nw"] : []

    MouseArea {
      id: zone
      required property string modelData
      readonly property bool north: zone.modelData.includes("n")
      readonly property bool south: zone.modelData.includes("s")
      readonly property bool east: zone.modelData.includes("e")
      readonly property bool west: zone.modelData.includes("w")
      readonly property bool corner: zone.modelData.length === 2
      readonly property real edge: Math.max(3, Math.min(8, root.width / 5, root.height / 5))
      readonly property real cornerSize: Math.max(Widget.px(5), Math.min(Widget.px(16), root.width / 4, root.height / 4))
      // Where the drag started, in the canvas, and the place then
      property point start: Qt.point(0, 0)
      property var startPlace: null

      x: zone.west ? 0 : zone.east ? root.width - zone.width : zone.cornerSize
      y: zone.north ? 0 : zone.south ? root.height - zone.height : zone.cornerSize
      width: zone.corner ? zone.cornerSize : zone.north || zone.south ? root.width - 2 * zone.cornerSize : zone.edge
      height: zone.corner ? zone.cornerSize : zone.east || zone.west ? root.height - 2 * zone.cornerSize : zone.edge
      z: 3
      hoverEnabled: true
      preventStealing: true
      cursorShape: zone.corner ? (zone.modelData === "nw" || zone.modelData === "se" ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor) : zone.north || zone.south ? Qt.SizeVerCursor : Qt.SizeHorCursor

      onPressed: mouse => {
        root.editor.select(root.index);
        zone.start = zone.mapToItem(root.parent, mouse.x, mouse.y);
        zone.startPlace = Object.assign({}, root.place);
        root.resizing = zone.modelData;
      }
      onPositionChanged: mouse => {
        if (!zone.pressed || !zone.startPlace)
          return;
        const p = zone.mapToItem(root.parent, mouse.x, mouse.y);
        const place = GridPlacement.resizeFrom(zone.startPlace, zone.modelData, Math.round((p.x - zone.start.x) / root.step), Math.round((p.y - zone.start.y) / root.step));
        const current = root.dragLayer.resizePlan?.place ?? zone.startPlace;
        if (!GridPlacement.samePlace(place, current) || !root.dragLayer.resizePlan)
          root.dragLayer.resizePlan = root.editor.planResize(root.index, place);
      }
      onReleased: {
        const plan = root.dragLayer.resizePlan;
        zone.finish();
        root.editor.applyPlan(plan);
      }
      onCanceled: zone.finish()

      function finish() {
        root.dragLayer.resizePlan = null;
        root.resizing = "";
        zone.startPlace = null;
      }

      // The side it moves, shown under the pointer
      Rectangle {
        visible: zone.containsMouse || root.resizing === zone.modelData
        anchors.centerIn: parent
        width: zone.corner ? Math.min(parent.width, Widget.px(8)) : zone.north || zone.south ? Math.min(parent.width, Appearance.fontSize * 2) : Widget.px(3)
        height: zone.corner ? Math.min(parent.height, Widget.px(8)) : zone.east || zone.west ? Math.min(parent.height, Appearance.fontSize * 2) : Widget.px(3)
        radius: Math.min(width, height) / 2
        color: Theme.accent
      }
    }
  }
}
