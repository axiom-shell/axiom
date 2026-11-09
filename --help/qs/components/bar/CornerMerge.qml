pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.components.hosts.popout

// One end of a pill bar that makes way for a pill bar at its corner
// (BarEnds "pillBar"), with its end pill joined there: that bar's end pill
// (grown if the bar has none there, BarContainer.setRequest) runs on past
// this pill's join fillet, straight off its own end, its far stroke left
// open where this pill joins it, so the two read as one with a single
// concave corner, as against a solid bar.
PillStretch {
  id: root
  // A BarContainer (typed var: its own members are read)
  required property var bar
  required property bool atStart

  readonly property var _rects: root.bar.pillRects
  readonly property var _pill: root.atStart ? root._rects[0] : root._rects[root._rects.length - 1]
  // The pill bar there is BarContainer.barAt's: one this bar makes way for
  readonly property bool _joins: !!root._pill && (root.atStart ? root._pill.joinStart : root._pill.joinEnd)
  readonly property var _origin: root.bar.blurOrigin
  readonly property var _otherOrigin: root.container?.blurOrigin ?? null
  // (the bar there may be unset rather than null, or go before this
  // re-evaluates: read it again where it's used)
  readonly property bool _placed: !!root.container && root._origin !== null && root._otherOrigin !== null
  // On a right or bottom bar the other bar's end is its far one
  readonly property bool _right: root.bar.barConfig.right || root.bar.barConfig.bottom
  // Along the other bar: across this one
  readonly property bool _vertical: root.bar.isVertical
  readonly property real _thickness: root._vertical ? root.bar.width : root.bar.height
  readonly property real _otherAt: !root._otherOrigin ? 0 : root._vertical ? root._otherOrigin.x : root._otherOrigin.y
  // Its pills' far edge, across the screen
  readonly property real _at: !root._origin ? 0 : root._vertical ? root._origin.x : root._origin.y
  readonly property real _far: !root._origin ? 0 : root._right ? root._at + root._thickness - root.bar.barConfig.pillDepth : root._at + root.bar.barConfig.pillDepth
  readonly property real _radius: Appearance.borderRadius
  // Where the join's fillet meets the other bar's far stroke: its stroke
  // runs on the centre line, half a stroke in from the pills' far edge
  readonly property real _filletTip: (root._right ? root._far - root._radius + Appearance.borderWidth / 2 : root._far + root._radius - Appearance.borderWidth / 2) - root._otherAt

  owner: "corner:" + root.bar.barConfig.id + (root.atStart ? ":start" : ":end")
  open: true
  container: root._joins ? (root.atStart ? root.bar.pillBarStart : root.bar.pillBarEnd) : null
  // Past the join's fillet, with room for the other pill's own corner
  endReach: root._placed ? {
    "atStart": !root._right,
    "to": (root._right ? root._far - 2 * root._radius : root._far + 2 * root._radius) - root._otherAt,
    "straight": true
  } : null
  // Its far stroke, from where the join's fillet meets it on to its end,
  // the other bar's shadow following round that fillet
  // (BarContainer._shadowHoles). Not past the fillet's flat cap: the
  // stroke left open there showed through as a gap in the corner.
  opening: root._placed && root.container ? Object.assign(SurfaceContext.opening(root._right ? root._filletTip : 0, root._right ? root.container.length : root._filletTip, root._right ? root._radius - 1 : 0, root._right ? 0 : root._radius - 1), {
    "keepFill": true
  }) : null
}
