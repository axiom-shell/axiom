pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// A backing-window copy with its stroke left open in `holes` (rects in its
// coordinates, drawn in by a 64th of a px on their outer edges
// (`Utils.tieInset`)): its fill whole (`fillOnly`, once, unclipped), its
// stroke (`strokeOnly`) in the pieces of its area outside the holes. The
// pieces are disjoint, so every stroke pixel is drawn once, with the whole
// stroke's coverage; each is an `Item` that clips, no layer. With no holes,
// `strokeOnly` once, unclipped. Pieces are kept across changes of the hole
// count (see `_outsideSlots`). The area is its rect grown on every side, so
// nothing its drawing reaches past its rect is lost. (HoledItem is the same
// job for a host, cutting all of its children.)
Item {
  id: root

  property var holes: []
  property Component fillOnly
  property Component strokeOnly

  readonly property real _grow: Math.max(root.width, root.height)
  readonly property rect _area: Qt.rect(-root._grow, -root._grow, root.width + root._grow * 2, root.height + root._grow * 2)
  // A hole's outer edges drawn in by a 64th of a px (a power of two, exact
  // in float): Qt's scissor rounds a clip edge to the nearest device px,
  // .5 up, through float matrices, so an edge on a .5 device px (a whole px
  // at 1.25) gave its pixel to the hole at an end, where the joined
  // surface's flat stroke cap leaves it too (a pixel's gap in the stroke),
  // and two pieces meeting there could both draw a row or neither. Off the
  // tie, every edge rounds one way: a pixel centred on a hole's edge is the
  // drawing's, as with no hole (`Utils.tieInset`)
  // (no holes: the whole area, one piece)
  readonly property var _outside: root.holes.length > 0 ? Utils.subtractRects(root._area, Utils.insetUnion(root._area, root.holes, Utils.tieInset)) : [root._area]

  // The most pieces it has needed: the Repeater's model. A piece is built
  // once and kept, hidden when there are fewer pieces than slots, so a hole
  // that comes or goes while a surface slides builds and destroys no
  // drawing (each is a whole Shape).
  property int _outsideSlots: root._outside.length
  on_OutsideChanged: root._outsideSlots = Math.max(root._outsideSlots, root._outside.length)

  Loader {
    width: root.width
    height: root.height
    sourceComponent: root.fillOnly
  }

  Repeater {
    model: root._outsideSlots

    Item {
      id: outsidePiece
      required property int index
      readonly property bool used: outsidePiece.index < root._outside.length
      // (a spare slot keeps its last rect)
      property rect piece: Qt.rect(0, 0, 0, 0)
      Binding on piece {
        when: outsidePiece.used
        value: root._outside[outsidePiece.index] ?? Qt.rect(0, 0, 0, 0)
      }
      visible: outsidePiece.used
      x: outsidePiece.piece.x
      y: outsidePiece.piece.y
      width: outsidePiece.piece.width
      height: outsidePiece.piece.height
      clip: root.holes.length > 0

      Loader {
        x: -outsidePiece.piece.x
        y: -outsidePiece.piece.y
        width: root.width
        height: root.height
        sourceComponent: root.strokeOnly
      }
    }
  }
}
