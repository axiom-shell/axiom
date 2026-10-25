pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.core
import qs.components.methods
import qs.components.hosts.popout
import qs.components.reusable

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
    namespace: "axiom-border"
    edge: root.edge === "left" ? Bar.Left : root.edge === "right" ? Bar.Right : root.edge === "bottom" ? Bar.Bottom : Bar.Top
  }
  // Surfaces joined to the stroke leave it open under them, in strip
  // coordinates: the stroke and the fill beside it (the stroke's row),
  // which would show through their translucent fill
  readonly property var openings: ShellManager.borderOpenings.filter(o => o.screen === (root.screen?.name ?? "") && o.edge === root.edge).map(o => ({
        "start": o.start - root.screenOffset,
        "end": o.end - root.screenOffset
      }))
  // The stroke runs between the corner pieces: a horizontal strip spans
  // the screen, a vertical one the room between them
  readonly property real strokeStart: horizontal ? frameWidth + innerBorderRadius : innerBorderRadius
  readonly property var strokePieces: Utils.subtractSpans(root.strokeStart, root.length - root.strokeStart, root.openings)
  readonly property var rowPieces: Utils.subtractSpans(0, root.length, root.openings)
  // An opening follows a surface in another window (sliding, a pill
  // growing): drawn here, but shown only once this window commits again
  // (FrameNudge)
  onOpeningsChanged: nudge.burst()

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
  WlrLayershell.namespace: "axiom-border"
  // Once the windows before it in the stack have mapped
  visible: slot.shown
  LayerSlot {
    id: slot
    window: root
    namespace: "axiom-border"
  }
  color: "transparent"
  mask: Region {}

  FrameNudge {
    id: nudge
  }

  // The frame, but for the stroke's row
  Rectangle {
    readonly property int depth: root.frameWidth - root.strokeWidth
    x: root.edge === "right" ? root.strokeWidth : 0
    y: root.edge === "bottom" ? root.strokeWidth : 0
    width: root.horizontal ? parent.width : depth
    height: root.horizontal ? depth : parent.height
    color: Appearance.fill(root.frameColor)
  }

  // The stroke's row: the fill under the stroke and past its ends
  Repeater {
    model: root.rowPieces.length

    delegate: Rectangle {
      required property int index
      readonly property var piece: root.rowPieces[index] ?? {
        "start": 0,
        "end": 0
      }
      x: root.horizontal ? piece.start : root.edge === "left" ? root.frameWidth - root.strokeWidth : 0
      y: root.horizontal ? (root.edge === "top" ? root.frameWidth - root.strokeWidth : 0) : piece.start
      width: root.horizontal ? piece.end - piece.start : root.strokeWidth
      height: root.horizontal ? root.strokeWidth : piece.end - piece.start
      color: Appearance.fill(root.frameColor)
    }
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
      color: Appearance.fill(root.endFillColor)
      width: root.horizontal ? along : root.strokeWidth
      height: root.horizontal ? root.strokeWidth : along
      x: root.horizontal ? (atStart ? 0 : parent.width - width) : (root.edge === "left" ? along : 0)
      y: root.horizontal ? (root.edge === "top" ? along : 0) : (atStart ? 0 : parent.height - height)
    }
  }

  // The inner stroke, on the strip's screen-facing side, between the
  // corner pieces and around the openings
  Repeater {
    model: root.strokePieces.length

    delegate: Rectangle {
      required property int index
      readonly property var piece: root.strokePieces[index] ?? {
        "start": 0,
        "end": 0
      }
      color: root.innerStrokeColor
      x: root.horizontal ? piece.start : root.edge === "left" ? root.frameWidth - root.strokeWidth : 0
      y: root.horizontal ? (root.edge === "top" ? root.frameWidth - root.strokeWidth : 0) : piece.start
      width: root.horizontal ? piece.end - piece.start : root.strokeWidth
      height: root.horizontal ? root.strokeWidth : piece.end - piece.start
    }
  }
}
