pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.components.methods
import qs.components.hosts.window
import qs.services.ui

// One edge of the screen border (RoundedBorders): a strip that reserves
// `frameWidth` and draws the frame with its inner stroke, which stops short
// of the corners by `innerBorderRadius` where the corner pieces take over.
// Input passes through it.
PanelWindow {
  id: root

  // "top" | "bottom" | "left" | "right"
  required property string edge
  required property int frameWidth
  required property int innerBorderRadius
  required property color frameColor
  // The frame's own colour, for the ends of a strip whose frameColor is
  // transparent (see endFills)
  required property color endFillColor
  required property color innerStrokeColor
  required property int strokeWidth

  readonly property bool horizontal: edge === "top" || edge === "bottom"
  readonly property real length: horizontal ? width : height
  // Where the strip starts along its edge on screen (LayerOrigin); until
  // it's mapped, as if what reserves the edges across it (the strips
  // there, when they mapped first) reserved as much at either end
  readonly property real screenOffset: placeOnScreen.origin ? (horizontal ? placeOnScreen.origin.x : placeOnScreen.origin.y) : ((horizontal ? screen?.width : screen?.height) ?? length) / 2 - length / 2
  LayerOrigin {
    id: placeOnScreen
    window: root
    layer: slot.layer
    edge: root.edge === "left" ? ScreenEdge.Left : root.edge === "right" ? ScreenEdge.Right : root.edge === "bottom" ? ScreenEdge.Bottom : ScreenEdge.Top
  }
  // The stroke runs between the corner pieces: a horizontal strip spans
  // the screen, a vertical one the room between them
  readonly property rect stripStroke: FrameOutline.stripStroke(root.edge, root.length, root.frameWidth, root.innerBorderRadius, root.strokeWidth)
  // Surfaces joined to the stroke, in strip coordinates: the backing window's
  // copy leaves the stroke open under them (this strip draws it whole)
  readonly property var openings: SurfaceManager.borderOpenings.filter(o => o.screen === (root.screen?.name ?? "") && o.edge === root.edge).map(o => ({
        "start": o.start - root.screenOffset,
        "end": o.end - root.screenOffset
      }))
  // Where its stroke pieces are on screen, on the device px its Rectangle
  // fills, for the backing window's copy: the stroke less its openings,
  // except that a pixel centred on an opening's edge is the stroke's
  readonly property var screenStrokePieces: FrameOutline.screenStrokePieces(root.edge, root.length, root.frameWidth, root.innerBorderRadius, root.strokeWidth, root.openings, placeOnScreen.placed, root.devicePixelRatio)

  anchors {
    left: root.edge !== "right"
    right: root.edge !== "left"
    top: root.edge !== "bottom"
    bottom: root.edge !== "top"
  }

  implicitWidth: root.horizontal ? 0 : root.frameWidth
  implicitHeight: root.horizontal ? root.frameWidth : 0

  exclusiveZone: root.frameWidth
  aboveWindows: true
  readonly property string layerNamespace: "axiom-border"
  WlrLayershell.namespace: root.layerNamespace
  WlrLayershell.layer: slot.layer
  // Once the windows before it in the stack have mapped
  visible: slot.shown
  LayerSlot {
    id: slot
    window: root
  }
  color: "transparent"
  mask: Region {}

  // The frame, but for the stroke's row
  Rectangle {
    readonly property int depth: root.frameWidth - root.strokeWidth
    x: root.edge === "right" ? root.strokeWidth : 0
    y: root.edge === "bottom" ? root.strokeWidth : 0
    width: root.horizontal ? parent.width : depth
    height: root.horizontal ? depth : parent.height
    color: Style.edgeFill(root.frameColor, false)
  }

  // The stroke's row: the fill under the stroke and past its ends
  Rectangle {
    x: root.horizontal ? 0 : root.stripStroke.x
    y: root.horizontal ? root.stripStroke.y : 0
    width: root.horizontal ? root.length : root.stripStroke.width
    height: root.horizontal ? root.stripStroke.height : root.length
    color: Style.edgeFill(root.frameColor, false)
  }

  // On a solid bar's edge the strip is transparent, but a strip that runs
  // into the corners (the first mapped of two that meet) also owns the
  // stroke's row past the bar there, outside the corner piece: fill it
  Repeater {
    model: root.frameColor.a < 1 ? [true, false] : []

    delegate: Rectangle {
      required property bool modelData
      readonly property bool atStart: modelData
      readonly property int along: root.frameWidth - root.strokeWidth
      color: Style.edgeFill(root.endFillColor, false)
      width: root.horizontal ? along : root.strokeWidth
      height: root.horizontal ? root.strokeWidth : along
      x: root.horizontal ? (atStart ? 0 : parent.width - width) : (root.edge === "left" ? along : 0)
      y: root.horizontal ? (root.edge === "top" ? along : 0) : (atStart ? 0 : parent.height - height)
    }
  }

  // The inner stroke, on the strip's screen-facing side, between the
  // corner pieces
  Rectangle {
    color: root.innerStrokeColor
    x: root.stripStroke.x
    y: root.stripStroke.y
    width: root.stripStroke.width
    height: root.stripStroke.height
  }
}
