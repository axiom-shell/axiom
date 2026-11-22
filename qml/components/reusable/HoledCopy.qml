pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// A backing-window copy with its stroke left open in `holes` (rects in its
// coordinates, whole px) and its fill kept there: `drawing` (fill and
// stroke) in the pieces of its area outside the holes, `fillOnly` in the
// pieces inside them. The pieces are disjoint, so every pixel is drawn once,
// by one piece, with the whole drawing's coverage; each is an `Item` that
// clips, no layer. With no holes, `drawing` once, unclipped. The area is its
// rect grown on every side, so nothing its drawing reaches past its rect is
// lost. (HoledItem is the same job for a host, cutting all of its children.)
Item {
  id: root

  property var holes: []
  property Component drawing
  property Component fillOnly

  readonly property real _grow: Math.max(root.width, root.height)
  readonly property rect _area: Qt.rect(-root._grow, -root._grow, root.width + root._grow * 2, root.height + root._grow * 2)
  readonly property var _outside: root.holes.length > 0 ? Utils.subtractRects(root._area, root.holes) : []
  readonly property var _inside: root.holes.length > 0 ? Utils.subtractRects(root._area, root._outside) : []

  Loader {
    anchors.fill: parent
    sourceComponent: root.drawing
    active: root.holes.length === 0
  }

  // (keyed by count, as HoledItem's holes are: a hole that moves or grows
  // moves its pieces' items and rebuilds nothing)
  Repeater {
    model: root._outside.length

    Item {
      id: outsidePiece
      required property int index
      readonly property rect piece: root._outside[outsidePiece.index] ?? Qt.rect(0, 0, 0, 0)
      x: outsidePiece.piece.x
      y: outsidePiece.piece.y
      width: outsidePiece.piece.width
      height: outsidePiece.piece.height
      clip: true

      Loader {
        x: -outsidePiece.piece.x
        y: -outsidePiece.piece.y
        width: root.width
        height: root.height
        sourceComponent: root.drawing
      }
    }
  }

  Repeater {
    model: root._inside.length

    Item {
      id: insidePiece
      required property int index
      readonly property rect piece: root._inside[insidePiece.index] ?? Qt.rect(0, 0, 0, 0)
      x: insidePiece.piece.x
      y: insidePiece.piece.y
      width: insidePiece.piece.width
      height: insidePiece.piece.height
      clip: true

      Loader {
        x: -insidePiece.piece.x
        y: -insidePiece.piece.y
        width: root.width
        height: root.height
        sourceComponent: root.fillOnly
      }
    }
  }
}
