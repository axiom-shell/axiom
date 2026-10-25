pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.core
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
// only where the surface has come. Whether it fillets is decided from
// where the wall rests.
PillStretch {
  id: root

  required property ShellScreen screen
  // The surface's own edge, and the perpendicular one it joins (Bar.Location)
  property int edge: Bar.Top
  property int side: Bar.Left
  // Whether the surface's end joins it, and is out (not loading or gone)
  property bool joined: false
  property bool showing: false
  // How far in from the surface's screen edge its joined end reaches the
  // pill bar's far stroke at its far wall (AttachedSurface.joinWall from
  // that edge), at rest; and how much of the surface is still behind its
  // edge, sliding, less the lead it keeps (EdgePlacement._slideLead)
  property real joinReach: 0
  property real hidden: 0

  readonly property var _panel: ShellManager.barOn(root.screen?.name ?? "", root.side)
  // A pill bar showing there, with no integrated menu's strip on that edge
  // between (SurfaceContext.endKind "pillBar", as its hosts decide joins)
  readonly property bool available: BarManager.surfaceEnd(root.screen, root.side).kind === "pillBar"

  // Along that bar, this edge is its start (left, top) or its end
  readonly property bool _atStart: root.edge === Bar.Left || root.edge === Bar.Top
  readonly property bool _vertical: root.edge === Bar.Left || root.edge === Bar.Right
  readonly property real _radius: Appearance.borderRadius
  // Where the surface's far wall meets that bar (its coordinates) at
  // `reach` from the surface's edge; null while the surface doesn't show
  function _wallAt(reach) {
    const origin = root._panel?.container?.blurOrigin;
    if (!origin || !root.showing || !root.joined || !root.available)
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
  readonly property bool filleted: root._wall !== null && EdgeAttach.pillJoinFilleted(root._panel.container.sectionPills, root._wall, root._atStart, root._radius, root._panel.barConfig.pillMerge ?? 0, Appearance.borderWidth)
  // Where the joined end covers that bar's far stroke to, as drawn: the
  // fillet's tip, or the wall
  readonly property var _reach: root._drawnWall === null ? null : !root.filleted ? root._drawnWall : root._atStart ? root._drawnWall + root._radius : root._drawnWall - root._radius

  container: root.joined && root.available ? (root._panel?.container ?? null) : null
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
  // Its far stroke left open under the surface (and its fillet, which the
  // bar's shadow then follows round, BarContainer._shadowHoles; or inside
  // the wall, whose stroke carries on into the pill's there): opaque or
  // not, as the two are separate windows whose stacking isn't the bar's to
  // choose. Whole pixels where filleted (SurfaceContext.opening).
  opening: {
    if (root._reach === null)
      return null;
    if (!root.filleted)
      return {
        "start": root._atStart ? 0 : root._reach + Appearance.borderWidth / 2,
        "end": root._atStart ? root._reach - Appearance.borderWidth / 2 : root._panel.container.length,
        "keepFill": true
      };
    return Object.assign(SurfaceContext.opening(root._atStart ? 0 : root._reach, root._atStart ? root._reach : root._panel.container.length, root._atStart ? 0 : root._radius, root._atStart ? root._radius : 0), {
      "keepFill": true
    });
  }
}
