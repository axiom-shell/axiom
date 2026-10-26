pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods

// Where a surface growing out of a screen edge goes along it, and
// everything that follows from what it meets there, for every host alike:
// bar popouts, edge popouts (OSDs, floating edge menus, the attached
// launcher) and docks. It gathers what's on the screen and hands it to
// SurfaceContext (frame: its ends and room; layout: its box), which hold
// every rule, so one intersection behaves the same whoever draws it; and
// it owns the side effects that follow: the pill stretched to carry it
// (PillStretch), pill bars it joins at an end (PillBarJoin) and the
// strokes it covers (StrokeOpening).
//
// Along the edge, inputs and outputs are in the host's coordinates, whose
// 0 lies `alongStart` px along the screen edge (an edge popout's past
// what's reserved at its start, a bar popout's at its bar window's start).
// Across it, in px from the screen edge.
QtObject {
  id: root

  required property ShellScreen screen
  // A ScreenEdge
  property int edge: ScreenEdge.Top
  // Held off the edge (a `detached` OSD, edge menu or dock, or a surface
  // over a fullscreen window): it follows no bar, joins nothing, and keeps
  // `gaps` from the frame lines (ScreenEdgeManager.detachedGaps, `gap` -1 Auto)
  property bool held: false
  property int gap: -1
  readonly property var gaps: root.held ? ScreenEdgeManager.detachedGaps(root.screen, root.edge, root.gap) : null
  readonly property int connectorGap: Appearance.connectorGap

  // The bar it follows: a bar popout's own (`followPanel`, solid
  // included); else the bar on its edge other than a solid one, while it
  // shows (a bar inside the border hides under fullscreen windows)
  property var followPanel: undefined
  readonly property var barPanel: {
    if (root.held)
      return null;
    if (root.followPanel !== undefined)
      return root.followPanel;
    const panel = ScreenEdgeManager.barOn(root.screen?.name ?? "", root.edge);
    return panel?.visible && !panel.barConfig.solid ? panel : null;
  }
  readonly property var barConfig: root.barPanel?.barConfig ?? null
  readonly property bool followsBar: root.barConfig !== null
  // The bar's BarContainer
  readonly property var container: root.barPanel?.container ?? null
  readonly property bool island: root.barConfig?.island ?? false
  readonly property bool pillBar: root.followsBar && ((root.barConfig?.pills ?? false) || root.island)

  // Where the host's coordinates start along the screen edge
  property real alongStart: ScreenEdgeManager.reservedWithMenusOn(root.screen, root.startSide)

  // The box, in the host's coordinates: its centre (picks the pill), where
  // its content would start and its length, and where it would like to be
  // at rest, which decides its joins (`probeStart`, `probeLength`: a box
  // that changes size, magnified or capped, never joins or parts an end)
  property real centre: 0
  property real aligned: 0
  property real contentLength: 0
  property real probeStart: 0
  property real probeLength: 0
  // The part of the surface (from its start) over the stroke it stands on,
  // left open there (AttachedSurface.coverStart/coverLength); a negative
  // length is the whole surface
  property real coverStart: 0
  property real coverLength: -1
  // Where the surface is drawn, which a box gliding along its edge (a bar
  // popout switching in place) lags its place by: its openings follow it
  property real drawnSurfaceStart: root.place.surfaceStart
  // The host's SubmenuHost, if it has one: where a joined submenu's outer
  // wall rests (how it meets the stroke there is submenuJoin), and where
  // it covers the stroke it stands on beside the box ({ start, end }, left
  // open there too while the surface's openings show); else null
  property var submenu: null
  readonly property var submenuWall: root.submenu?.wall ?? null
  readonly property var submenuSpan: root.opens ? (root.submenu?.joinSpan ?? null) : null

  // Its pill stretch: a key unique per surface on a bar, and whether it
  // shows (not while the content loads or unloads, the box a placeholder)
  required property string owner
  property bool showing: false
  // Whether the surface is to show (open, not closing), and whether the
  // pills have grown out to carry it, its own and any pill bar's it joins
  // at an end: the surface slides out once they have (PillStretch.ready)
  property bool open: false
  readonly property bool stretchReady: root._stretch.ready && root._startPill.ready && root._endPill.ready

  readonly property bool vertical: root.edge === ScreenEdge.Left || root.edge === ScreenEdge.Right
  readonly property string edgeName: ScreenEdge.name(root.edge)
  readonly property int startSide: root.vertical ? ScreenEdge.Top : ScreenEdge.Left
  readonly property int endSide: root.vertical ? ScreenEdge.Bottom : ScreenEdge.Right
  readonly property real _span: (root.vertical ? root.screen?.height : root.screen?.width) ?? 0
  readonly property real _spanAcross: (root.vertical ? root.screen?.width : root.screen?.height) ?? 0
  readonly property bool bareEdge: ScreenEdgeManager.screenEdgeOpen(root.screen, root.edge)
  // The bar on the edge, whatever it is (an enriched bar entry), or null
  readonly property var ownBar: ScreenEdgeManager.edgesFor(root.screen)[root.edgeName] ?? null

  // Where the followed bar's window lies along the screen edge
  readonly property real barStart: root.barPanel ? (root.vertical ? root.barPanel.screenPlaced.y : root.barPanel.screenPlaced.x) : 0
  readonly property real _barLength: root.container?.length ?? root._span
  // Host coordinates to the bar window's and the screen's, and back
  readonly property real _toBar: root.alongStart - root.barStart
  function _toScreen(x) {
    return x + root.alongStart;
  }
  function _fromScreen(x) {
    return x - root.alongStart;
  }

  // --- Its frame (SurfaceContext.frame): ends and room ---
  function _side(location, held) {
    const name = ScreenEdge.name(location);
    const frame = ScreenEdgeManager.frameLineOn(root.screen, location);
    const reserved = ScreenEdgeManager.reservedWithMenusOn(root.screen, location);
    return {
      "kind": ScreenEdgeManager.surfaceEnd(root.screen, location),
      "frame": frame,
      "reserved": reserved,
      "corner": ScreenEdgeManager.cornerLineOn(root.screen, location),
      "gapsOut": CompositorManager.gapsOut[name] ?? 0,
      "barHeld": held
    };
  }
  readonly property var _params: ({
      "edge": root.edge,
      "span": root._span,
      "border": Appearance.screenBorder,
      "bareEdge": root.bareEdge,
      "gap": root.connectorGap,
      "stroke": Appearance.borderWidth,
      "radius": Appearance.borderRadius,
      "held": root.held,
      "gaps": root.gaps,
      "bar": root.barConfig,
      "barStart": root.barStart,
      "barLength": root._barLength,
      "islandFrom": root.barStart + (root.container?.islandFrom ?? 0),
      "islandTo": root.barStart + (root.container?.islandEnd ?? root._barLength),
      "start": root._side(root.startSide, root.barConfig?.ends?.start?.held ?? false),
      "end": root._side(root.endSide, root.barConfig?.ends?.end?.held ?? false)
    })
  readonly property var frame: SurfaceContext.frame(root._params)
  // What each end meets, and what that makes it (SurfaceContext.end)
  readonly property var startEnd: root.frame.startEnd
  readonly property var endEnd: root.frame.endEnd
  // How far the window reaches onto the perpendicular strokes past each
  // end, where a joined end sits (as a bar's inside the border does)
  readonly property real strokeInsetStart: root.startEnd.strokeInset
  readonly property real strokeInsetEnd: root.endEnd.strokeInset
  // In the host's coordinates: where windows start past the perpendicular
  // edges (what an edge popout's window spans), where an unjoined box may
  // reach, where joined ends sit, and where a floating bar's islands may
  // reach
  readonly property real innerStart: root._fromScreen(root._params.start.reserved)
  readonly property real innerEnd: root._fromScreen(root._span - root._params.end.reserved)
  readonly property real lo: root._fromScreen(root.frame.lo)
  readonly property real hi: root._fromScreen(root.frame.hi)
  readonly property real joinFrom: root._fromScreen(root.frame.joinFrom)
  readonly property real joinTo: root._fromScreen(root.frame.joinTo)
  // The perpendicular strokes' outer edges (a floating bar's island
  // reach): what a stroke the box grows from reaches to without it
  readonly property real strokeFrom: root._fromScreen(root.frame.strokeFrom)
  readonly property real strokeTo: root._fromScreen(root.frame.strokeTo)
  readonly property real islandFrom: root._fromScreen(root.frame.islandFrom)
  readonly property real islandTo: root._fromScreen(root.frame.islandTo)
  // ...and as distances in from the inner sides
  readonly property real insetStart: root.lo - root.innerStart
  readonly property real insetEnd: root.innerEnd - root.hi
  // Standing on an island, decided without the box's length, which may be
  // capped by what it decides
  readonly property bool atIsland: root.island && (root.container?.pillRects?.length ?? 0) > 0
  // Which ends it joins, from where it would rest
  readonly property var _joins: SurfaceContext.joinsOf(root.frame, root._toScreen(root.probeStart), root.probeLength, root.connectorGap)
  readonly property bool joinStart: root._joins.joinStart
  readonly property bool joinEnd: root._joins.joinEnd
  // Where windows past a perpendicular edge start, or a frame line plus
  // `gap`, in from where windows start there (a held box's room)
  function heldInset(side, gap) {
    return ScreenEdgeManager.heldInset(root.screen, side, gap);
  }

  // --- Its box (SurfaceContext.layout) ---
  readonly property var _layout: SurfaceContext.layout(root.frame, Object.assign({}, root._params, {
    "pills": root.pillBar ? (root.container?.pillRects ?? []).map(p => Object.assign({}, p, {
        "start": p.start + root.barStart
      })) : [],
    "centre": root._toScreen(root.centre),
    "aligned": root._toScreen(root.aligned),
    "length": root.contentLength,
    "joinStart": root.joinStart,
    "joinEnd": root.joinEnd,
    "frameLine": ScreenEdgeManager.frameLineOn(root.screen, root.edge),
    "reserved": ScreenEdgeManager.reservedWithMenusOn(root.screen, root.edge),
    "detachedPush": root.barConfig ? Bar.detachedPush(root.barConfig, CompositorManager.gapsOut[root.edgeName] ?? 0, root.connectorGap) : 0,
    "ownBar": root.ownBar,
    "across": root.gaps?.across ?? 0,
    "layerOrder": CompositorManager.supports.layerOrder === true,
    "overOverlay": root.overOverlay
  }))
  // EdgeAttach.place's answer in the host's coordinates
  readonly property var place: {
    const l = root._layout;
    const shift = r => r ? Object.assign({}, r, {
        "start": root._fromScreen(r.start)
      }) : r;
    return Object.assign({}, l, {
      "start": root._fromScreen(l.start),
      "end": root._fromScreen(l.end),
      "contentStart": root._fromScreen(l.contentStart),
      "surfaceStart": root._fromScreen(l.surfaceStart),
      "pill": shift(l.pill),
      "stretch": l.stretch ? Object.assign({}, l.stretch, {
        "start": root._fromScreen(l.stretch.start),
        "end": root._fromScreen(l.stretch.end)
      }) : null
    });
  }
  readonly property bool merged: root._layout.merged
  // Standing on a pill's or island's far stroke
  readonly property bool onPill: root._layout.onPill
  // A box of its own (SurfaceContext.detached): held, or on a bar with
  // nothing to grow out of (a transparent one, a floating one showing no
  // islands)
  readonly property bool detached: root._layout.detached
  // Runs straight off its attach edge: a bare screen edge, or without the
  // border, the outer edge a merged box grows from
  readonly property bool straight: root._layout.straight
  // Extra box depth at the attach edge that a merged box's content keeps
  // clear of where the pills would be by
  readonly property real attachClearance: root._layout.attachClearance
  // Where its attach edge goes, across from the screen edge (held, a
  // connector gap short of its box), and from the followed bar's outer
  // edge
  readonly property real attachAt: root._layout.attachAt
  readonly property real attachFromBar: root._layout.attachFromBar
  readonly property real barOuter: root._layout.barOuter
  // Whether the overlay is open on its screen (the host latches it while
  // open), and whether a detached box slides out from under a transparent
  // bar, its window on that bar's layer ordered under it
  property bool overOverlay: false
  readonly property bool slidesUnder: root._layout.slidesUnder
  // On a pill's far stroke the surface covers that stroke's inner fringe
  readonly property int backfill: root._layout.backfill
  // How a joined submenu meets the stroke the box grows from, from where
  // its outer wall rests (SurfaceContext.submenuJoin): its fillet curving
  // in, or its wall running straight up into it, and the box's pill or
  // island stretched for it (kept between the strokes at the edge's ends,
  // or within where islands may reach)
  readonly property var _ownPill: {
    if (!root.onPill)
      return null;
    const p = root.place.stretch ?? root.place.pill;
    return p ? Object.assign({}, p, {
      "end": p.end ?? p.start + p.length
    }) : null;
  }
  readonly property var submenuJoin: root.submenuWall === null ? null : SurfaceContext.submenuJoin({
    "wall": root.submenuWall,
    "before": root.submenu?.openToLeft ?? false,
    "radius": Appearance.borderRadius,
    "stroke": Appearance.borderWidth,
    "merge": root.barConfig?.pillMerge ?? 0,
    "own": root._ownPill,
    "pills": root.onPill ? (root.container?.pillRects ?? []).map(p => Object.assign({}, p, {
        "start": p.start - root._toBar
      })) : [],
    "stretchFrom": root._fromScreen(root._layout.stretchFrom),
    "stretchTo": root._fromScreen(root._layout.stretchTo),
    "strokeFrom": root.strokeFrom,
    "strokeTo": root.strokeTo
  })
  // Its pill stretch
  readonly property var stretch: root.place.stretch
  // A joined submenu's, as its outer wall is drawn: it slides out along
  // the stroke, and the pill runs out with it (`_slideLead` ahead), never
  // past where it rests
  // nor back inside what the box's own stretch covers. Its `box` is the
  // two boxes together, from the submenu's wall at rest
  // (BarLayout.flushEnds)
  readonly property var _submenuReach: {
    const j = root.submenuJoin;
    const own = root._ownPill;
    if (!j?.stretch || j.at === null || !own)
      return null;
    const before = root.submenu?.openToLeft ?? false;
    const tip = j.at + (before ? 1 : -1) * Math.max(0, (root.submenu?.hidden ?? 0) - root._slideLead);
    return Object.assign({}, j.stretch, before ? {
      "start": Math.min(own.start, tip)
    } : {
      "end": Math.max(own.end, tip)
    }, {
      "box": {
        "start": Math.min(root.place.start, j.at),
        "end": Math.max(root.place.end, j.at)
      }
    });
  }

  // --- Its shadow (SurfaceContext.shadow) ---
  // What it grows out of: its bar (pills, islands, a merged box's outer
  // edge, a solid bar's own stroke with the border off), the border, or a
  // bare edge. AttachedSurface's shadowLook.
  readonly property var shadow: root._layout.shadow
  // (BarStyle's while the bar is gone: bars changing, the decision may
  // lag a moment)
  readonly property var shadowLook: root.shadow.look === "bar" && root.ownBar ? root.ownBar : BarStyle.look

  // --- Its fill (BlurManager) ---
  // Whether its window is on the Overlay layer, and where it is on screen
  // (null until known): the blur window draws its fill and casts its
  // shadow where it backs that layer on its screen; else it fills itself,
  // solid while blur is paused for a fullscreen window there
  property bool onOverlayLayer: true
  property var origin: null
  readonly property bool backed: BlurManager.backsOn(root.screen, root.onOverlayLayer) && root.origin !== null
  readonly property bool opaque: BlurManager.opaqueOn(root.screen)

  // --- The strokes it covers ---
  // The surface (its AttachedSurface, positioned in the window at
  // `origin`) and whether its openings show: out, and granted
  property var attachedSurface: null
  property bool opens: false
  // From the screen edge, how far in the surface's attach side is at
  // rest, and how far a joined end's far wall reaches
  // (AttachedSurface.joinWall). From the layout, not where the surface is
  // drawn: that slides in, and the join this decides (PillBarJoin.filleted)
  // resizes it and its window a frame apart, which moved the wall it was
  // decided from and flipped it back.
  readonly property real _surfaceFromEdge: root.attachAt - root.backfill
  readonly property real joinReach: root._surfaceFromEdge + (root.attachedSurface?.joinWall ?? 0)
  // How far context along a slide (a pill bar's end pill under a joined
  // end, a joined submenu's pill reach) leads its surface's wall: a stroke
  // where another window's change may show a frame or so after the
  // surface's (no supports.layerFrameSync), else none, the two moving as one
  readonly property real _slideLead: CompositorManager.supports.layerFrameSync === true ? 0 : Appearance.borderWidth
  // How much of the surface is still behind its edge as it slides, less
  // that lead: what a pill bar joined at an end follows it along by
  // (PillBarJoin.hidden, AttachedSurface.hiddenNow)
  readonly property real _surfaceHidden: Math.max(0, (root.attachedSurface?.hiddenNow ?? 0) - root._slideLead)
  function _edgeSpan(start, end) {
    return {
      "screen": root.screen?.name ?? "",
      "edge": root.edgeName,
      "start": root._toScreen(start),
      "end": root._toScreen(end)
    };
  }
  readonly property real _coverStart: root.drawnSurfaceStart + root.coverStart
  readonly property real _coverEnd: root._coverStart + (root.coverLength < 0 ? root.place.surfaceLength : root.coverLength)
  // ...with the fillets curving into it at each end
  readonly property var _coverSpan: root.opens && root.attachedSurface && root._coverEnd > root._coverStart ? Object.assign(root._edgeSpan(root._coverStart, root._coverEnd), {
    "startFillet": root.attachedSurface.coverStartFillet,
    "endFillet": root.attachedSurface.coverEndFillet
  }) : null
  // At a joined end, the perpendicular edge's stroke its end covers, from
  // where its window is on screen, its fillet included
  function _joinSpan(atStart) {
    const s = root.attachedSurface;
    if (!root.opens || !s || !root.origin || root.detached)
      return null;
    const from = root.vertical ? root.origin.x + s.x : root.origin.y + s.y;
    return Object.assign({
      "screen": root.screen?.name ?? ""
    }, EdgeAttach.joinOpening(root.edgeName, atStart, from, root.vertical ? s.width : s.height, atStart ? s.joinShown : s.joinShownEnd, root._spanAcross, atStart ? s.joinFillet : s.joinFilletEnd));
  }
  property StrokeOpening _ownOpening: StrokeOpening {
    screen: root.screen
    owner: root.owner + ":stroke"
    sink: root._layout.ownSink
    span: root._coverSpan
  }
  property StrokeOpening _submenuOpening: StrokeOpening {
    screen: root.screen
    owner: root.owner + ":submenuStroke"
    sink: root._layout.ownSink
    span: root.submenuSpan ? root._edgeSpan(root.submenuSpan.start, root.submenuSpan.end) : null
  }
  property StrokeOpening _startOpening: StrokeOpening {
    screen: root.screen
    owner: root.owner + ":joinStartStroke"
    sink: root.startEnd.sink
    span: root.attachedSurface?.joinStart ? root._joinSpan(true) : null
  }
  property StrokeOpening _endOpening: StrokeOpening {
    screen: root.screen
    owner: root.owner + ":joinEndStroke"
    sink: root.endEnd.sink
    span: root.attachedSurface?.joinEnd ? root._joinSpan(false) : null
  }

  // Joined ends run straight off a bare screen edge, or into a pill bar's
  // stub where its pill doesn't already run on past the wall
  // (PillBarJoin.filleted)
  readonly property bool straightJoinStart: root.startEnd.straight || (root._startPill.joined && !root._startPill.filleted)
  readonly property bool straightJoinEnd: root.endEnd.straight || (root._endPill.joined && !root._endPill.filleted)
  property PillBarJoin _startPill: PillBarJoin {
    screen: root.screen
    edge: root.edge
    side: root.startSide
    owner: root.owner + ":joinStart"
    open: root.open
    joined: root.place.joinStart && root.startEnd.sink === "pillBar"
    showing: root.showing
    joinReach: root.joinReach
    hidden: root._surfaceHidden
  }
  property PillBarJoin _endPill: PillBarJoin {
    screen: root.screen
    edge: root.edge
    side: root.endSide
    owner: root.owner + ":joinEnd"
    open: root.open
    joined: root.place.joinEnd && root.endEnd.sink === "pillBar"
    showing: root.showing
    joinReach: root.joinReach
    hidden: root._surfaceHidden
  }

  // The pill (or island) stretched to carry the box's fillets while it
  // shows, and its far stroke left open under a translucent box (or, on a
  // solid bar's own stroke, StrokeOpening above), in the bar's coordinates
  function _toBarSpan(start, end) {
    return {
      "start": start + root._toBar,
      "end": end + root._toBar
    };
  }
  // A stretch (with its surface's `box`) in the bar's coordinates, with
  // the pill it stands on at rest (`pill`: BarLayout.pillIndex finds it
  // again should the bar's pills change before it's sent anew)
  function _toBarStretch(stretch) {
    const pill = root.place.pill;
    return Object.assign({}, stretch, root._toBarSpan(stretch.start, stretch.end), {
      "box": root._toBarSpan(stretch.box.start, stretch.box.end),
      "pill": pill ? {
        "start": pill.start + root._toBar,
        "length": pill.length
      } : null
    });
  }
  property PillStretch _stretch: PillStretch {
    container: root.container
    owner: root.owner
    open: root.open
    stretch: root.showing && root.stretch ? root._toBarStretch(Object.assign({}, root.stretch, {
      "box": {
        "start": root.place.start,
        "end": root.place.end
      }
    })) : null
    covered: root._covers
    opening: root.showing && root.onPill && Appearance.translucent ? root._toBarSpan(root._coverStart, root._coverEnd) : null
  }
  // Whether the surface is out over the stroke it stands on (none of it
  // while it's all behind its edge): the bar runs a wall of it on from a
  // pill's squared end only then (BarContainer._flushEnds)
  readonly property bool _covers: root._coverEnd > root._coverStart
  property PillStretch _submenuStretch: PillStretch {
    container: root.container
    owner: root.owner + ":submenu"
    tracks: true
    stretch: root.showing && root._submenuReach ? root._toBarStretch(root._submenuReach) : null
    opening: root.showing && root.onPill && Appearance.translucent && root.submenuSpan ? root._toBarSpan(root.submenuSpan.start, root.submenuSpan.end) : null
  }
}
