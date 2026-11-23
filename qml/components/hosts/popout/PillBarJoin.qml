pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.ui
import qs.components.methods

// A surface's end joining a pill bar on a perpendicular screen edge: its
// end sits on that bar's far stroke, and the bar's pill at this edge's end
// runs out along the surface (BarContainer.setRequest's endReach: the end pill
// stretched, or a stub grown where the bar has none there). Where the
// bar's own pill already runs on past the surface's wall (`filleted`),
// the end curves into its far stroke with a fillet, as into a solid bar's
// stroke, the pill carried on past the fillet; otherwise the pill (or
// stub) runs only to the surface's far wall and squares there, the wall
// running straight up into it (the host joins it straight). Inside the
// border, or on the bare edge without it, alike.
//
// It follows the surface along its slide (`hidden`): the pill runs out
// with the surface's far wall as it slides out along it, and back with
// it as it slides away, so the two never part; its far stroke opens
// only where the surface (a boxed one's) has come. Whether it fillets is decided from
// where the wall rests.
PillStretch {
  id: root

  required property ShellScreen screen
  // The surface's own edge, and the perpendicular one it joins (ScreenEdges)
  property int edge: ScreenEdge.Top
  property int side: ScreenEdge.Left
  // Whether the surface's end joins it, and is out (not loading or gone)
  property bool joined: false
  property bool showing: false
  // Its surface draws no box (AttachedSurface.hollow): the pill still runs
  // out with it, its far stroke left whole
  property bool hollow: false
  // How far in from the surface's screen edge its joined end reaches the
  // pill bar's far stroke at its far wall (AttachedSurface.joinSide from
  // that edge), at rest; and how much of the surface is still behind its
  // edge, sliding, less the lead it keeps (EdgePlacement._slideLead)
  property real joinReach: 0
  property real hidden: 0

  readonly property var _panel: ScreenEdgeManager.barOn(root.screen?.name ?? "", root.side)

  // Along that bar, this edge is its start (left, top) or its end
  readonly property bool _atStart: root.edge === ScreenEdge.Left || root.edge === ScreenEdge.Top
  readonly property bool _vertical: root.edge === ScreenEdge.Left || root.edge === ScreenEdge.Right
  readonly property real _radius: Appearance.borderRadius
  // Where the surface's far wall meets that bar (its coordinates) at
  // `reach` from the surface's edge; null while the surface doesn't show
  function _wallAt(reach) {
    const origin = root._panel?.container?.blurOrigin;
    if (!origin || !root.showing || !root.joined)
      return null;
    const span = (root._vertical ? root.screen?.width : root.screen?.height) ?? 0;
    return (root._atStart ? reach : span - reach) - (root._vertical ? origin.x : origin.y);
  }
  // ...at rest, which decides whether it fillets
  readonly property var _wall: root._wallAt(root.joinReach)
  // ...and as drawn, sliding: what the pill and its opening follow
  readonly property var _drawnWall: root._wallAt(root.joinReach - root.hidden)
  // Whether one of the bar's own pills shows past the wall near enough to
  // be carried on past a fillet: the end then curves into it rather than
  // squaring a stub at the wall (EdgeAttach.pillJoinFilleted)
  readonly property bool filleted: root._wall !== null && EdgeAttach.pillJoinFilleted(root._panel.container.groupPills, root._wall, root._atStart, root._radius, root._panel.barConfig.joinGap ?? 0, Appearance.borderWidth)
  // Where the joined end covers that bar's far stroke to, as drawn: the
  // fillet's tip, or the wall
  readonly property var _reach: root._drawnWall === null ? null : !root.filleted ? root._drawnWall : root._atStart ? root._drawnWall + root._radius : root._drawnWall - root._radius

  container: root.joined ? (root._panel?.container ?? null) : null
  // Filleted, past the fillet by the pill's own corner; else out to the
  // wall's outer edge, squared there
  endReach: root._reach === null ? null : root.filleted ? {
    "atStart": root._atStart,
    "to": root._atStart ? root._reach + root._radius : root._reach - root._radius
  } : {
    "atStart": root._atStart,
    "to": root._atStart ? root._reach + Appearance.borderWidth / 2 : root._reach - Appearance.borderWidth / 2,
    "square": true
  }
  // Where its surface's joined end is drawn from across this bar, in screen
  // px (EdgePlacement), or null
  property var drawnStart: null
  // Its far stroke left open under the surface (and its fillet, which the
  // bar's shadow then follows round, BarContainer._shadowHoles; or inside
  // the wall, whose stroke carries on into the pill's there): opaque or
  // not, as the two are separate windows whose stacking isn't the bar's to
  // choose. Whole pixels (SurfaceContext.opening), as every opening.
  opening: {
    if (root._reach === null || root.hollow)
      return null;
    if (!root.filleted)
      return Object.assign(SurfaceContext.opening(root._atStart ? 0 : root._reach + Appearance.borderWidth / 2, root._atStart ? root._reach - Appearance.borderWidth / 2 : root._panel.container.length), root.drawnStart === null ? {
        "keepFill": true
      } : {
        "keepFill": true,
        "coverStart": root.drawnStart - (root._vertical ? root._panel.container.blurOrigin.y : root._panel.container.blurOrigin.x)
      });
    return Object.assign(SurfaceContext.opening(root._atStart ? 0 : root._reach, root._atStart ? root._reach : root._panel.container.length, root._atStart ? 0 : root._radius, root._atStart ? root._radius : 0), {
      "keepFill": true
    });
  }
}
