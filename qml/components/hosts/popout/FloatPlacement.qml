pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.services.ui
import qs.components.methods

// Where a detached surface placed as the launcher is (an `edge`, a
// `position` along it, a `distance` across the free screen from it) goes
// on a FloatingPopout: its fractions, aligns and margins, to bind the
// popout's to. Used by the launcher and the window switcher.
//
// Distance 0 is where a detached dock or OSD on its edge sits with an
// automatic gap (ScreenEdgeManager.detachedGaps): the free area's margin
// on each side, in from the window, which starts past what's reserved
// there. The fraction with the same align spreads the room left over: 0
// against the edge, 0.5 centred.
QtObject {
  id: root

  required property ShellScreen screen
  // A ScreenEdge
  property int edge: ScreenEdge.Top
  // 0-1 along the edge, of its centre
  property real position: 0.5
  // 0-0.5 across the free screen from the edge
  property real distance: 0.5

  readonly property bool vertical: root.edge === ScreenEdge.Left || root.edge === ScreenEdge.Right
  readonly property real across: root.edge === ScreenEdge.Bottom || root.edge === ScreenEdge.Right ? 1 - root.distance : root.distance

  readonly property real xFraction: root.vertical ? root.across : root.position
  readonly property real xAlign: root.vertical ? root.across : 0.5
  readonly property real yFraction: root.vertical ? root.position : root.across
  readonly property real yAlign: root.vertical ? 0.5 : root.across
  readonly property real leftMargin: root._marginOn(ScreenEdge.Left)
  readonly property real topMargin: root._marginOn(ScreenEdge.Top)
  readonly property real rightMargin: root._marginOn(ScreenEdge.Right)
  readonly property real bottomMargin: root._marginOn(ScreenEdge.Bottom)

  readonly property var _edgeGaps: ScreenEdgeManager.detachedGaps(root.screen, root.edge, -1)
  readonly property var _oppositeGaps: ScreenEdgeManager.detachedGaps(root.screen, ScreenEdge.opposite(root.edge), -1)

  function _marginOn(side) {
    let gap = root._edgeGaps.end;
    if (side === root.edge)
      gap = root._edgeGaps.across;
    else if (side === ScreenEdge.opposite(root.edge))
      gap = root._oppositeGaps.across;
    else if (side === (root.vertical ? ScreenEdge.Top : ScreenEdge.Left))
      gap = root._edgeGaps.start;
    return ScreenEdgeManager.heldInset(root.screen, side, gap);
  }
}
