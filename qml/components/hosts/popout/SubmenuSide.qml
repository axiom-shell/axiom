pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// What a submenu (SubPopout) meets on the side of its parent's box, the
// same for a bar popout's and an edge popout's: which side it opens to,
// whether its ends may run flush to a free end of the side or join the
// stroke the parent grows from, how far that stroke reaches, and which of
// the parent's corners it squares. Everything is in the parent's window,
// y along the side (submenus open to the left or right).
QtObject {
  id: root

  // The parent's edge (a ScreenEdge), whether its box is detached (a
  // box of its own: its bar side has nothing to join) or runs straight
  // off its attach edge (a bare screen edge, or without the border a
  // merged box's outer edge)
  property int edge: ScreenEdge.Top
  property bool detached: false
  property bool straight: false
  // The parent's attach edge (y of the stroke's outer edge), where a
  // joined submenu's end sits, and the backfill row it takes past it (on a
  // pill or island), which a joined submenu covers beside it
  property real attachLine: 0
  property real backfill: 0
  // The parent's joined ends (along its edge)
  property bool joinStart: false
  property bool joinEnd: false
  // The parent's box centre and its window's size: which half it's in
  property real boxCentreX: 0
  property real boxCentreY: 0
  property real windowWidth: 0
  property real windowHeight: 0
  // What an open submenu asks of the box (SubPopout.parentStretch), or null
  property var stretch: null

  readonly property bool vertical: root.edge === ScreenEdge.Left || root.edge === ScreenEdge.Right
  // Away from a side edge; on a top or bottom one towards the nearer half
  // (a box about the middle opening right: judged by its exact centre, it
  // flipped with a few px of where its window was found to be)
  readonly property bool openToLeft: root.vertical ? root.edge === ScreenEdge.Right : root.boxCentreX > root.windowWidth * 0.55
  // At the bar side of a box on a top or bottom edge, a submenu with no
  // room for its fillet joins the stroke the box grows from, as a popout
  // joins the perpendicular border: the border's, a solid bar's, a pill's
  // or island's far stroke (stretched to carry it). A detached box's ends
  // there are flush instead.
  readonly property bool _joins: !root.vertical && !root.detached
  readonly property bool joinTop: root._joins && root.edge === ScreenEdge.Top
  readonly property bool joinBottom: root._joins && root.edge === ScreenEdge.Bottom
  // The ends of the side it may run flush to: the far edge's, not a
  // joined end, and on a top or bottom edge its bar side's where nothing's
  // joined there
  readonly property bool freeTop: root.vertical ? !root.joinStart : root.edge === ScreenEdge.Bottom || !root._joins
  readonly property bool freeBottom: root.vertical ? !root.joinEnd : root.edge === ScreenEdge.Top || !root._joins
  // Longer than the side, it hangs past its far end: up on a bottom edge,
  // and on a side edge towards the screen's middle
  readonly property bool growsUp: root.vertical ? root.boxCentreY > root.windowHeight / 2 : root.edge === ScreenEdge.Bottom
  // Joined at the bar side, the stroke the box's wall there ran flush into
  // carries on past it, under the submenu
  readonly property bool joined: !root.vertical && (root.stretch?.joined ?? false)
  // The box's corners it squares: on a side edge its far edge's top and
  // bottom (AttachedSurface's start/end), on a top or bottom one those of
  // the side it opens on, the far one, or a detached box's near one
  readonly property bool _squareTop: root.stretch?.squareTop ?? false
  readonly property bool _squareBottom: root.stretch?.squareBottom ?? false
  readonly property bool _squareFar: root.edge === ScreenEdge.Top ? root._squareBottom : root._squareTop
  readonly property bool _squareNear: !root.vertical && (root.edge === ScreenEdge.Top ? root._squareTop : root._squareBottom)
  readonly property bool squareStartCorner: root.vertical ? root._squareTop : root.openToLeft && root._squareFar
  readonly property bool squareEndCorner: root.vertical ? root._squareBottom : !root.openToLeft && root._squareFar
  readonly property bool squareStartNear: root.openToLeft && root._squareNear
  readonly property bool squareEndNear: !root.openToLeft && root._squareNear
}
