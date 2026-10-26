pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs.config
import qs.components.reusable
import qs.components.methods

/**
 * The shared "grows out of an edge" shape used by bar popouts, screen-edge
 * popouts and bar pills: a content box joined to the attach edge by two
 * concave fillets, with the bar/border stroke cut open where it joins.
 * The whole thing slides in/out from the attach edge.
 *
 * The outline is a single path (fill + stroke), with the stroke centred
 * half a border width inside the edge. That way every segment (the line
 * along the attach edge, the fillets, the sides and the far corners) is
 * the same full width, pixel-aligned with the bar/border stroke it
 * continues. Composing rectangles + clipped corner pieces left some
 * segments half-clipped and anti-aliased.
 *
 * `edge` is the side the surface attaches to, as a ScreenEdge value.
 * `boxWidth`/`boxHeight` are the size of the content box; the implicit
 * size adds the connector and fillet margins around it. Attached, the box
 * starts on the attach edge (boxStart), the fillets beside it.
 *
 * Variations, all off by default:
 * - joinStart/joinEnd: that end sits flush on the perpendicular edge's
 *   stroke (u = 0 is its outer edge): no side wall, and the far edge meets
 *   that stroke with a concave fillet instead
 * - flushStart/flushEnd: that side wall runs straight into the attach
 *   edge with no fillet, continuing the end of what it attaches to (a
 *   floating bar's island, whose corner squares to meet it)
 * - detached: a plain rounded box, not joined to anything; detachedOffset
 *   sets it further in from the edge it slides out of
 * - straight/straightJoins: the attach edge, or the edges a join meets, are
 *   bare screen edges, so the walls run straight off them
 *
 * Place this at the attach edge of its window: for a Top edge, y = 0 of
 * this item should sit on the top of the bar/border stroke line.
 */
Item {
  id: root

  required property int edge
  property bool active: false
  property real boxWidth: 100 // fixed px: a placeholder, always set
  property real boxHeight: 100 // fixed px: a placeholder, always set
  property int connectorGap: Appearance.connectorGap
  property int animationDuration: Appearance.animNormal

  property bool joinStart: false
  property bool joinEnd: false
  property bool flushStart: false
  property bool flushEnd: false
  // A flush wall runs on through the backfill, over the end of the stroke
  // it continues (see SurfaceOutline._outline). Off where that stroke now carries on past
  // it (a submenu joined beside it, the pill or island stretched
  // under it): the wall stops at the attach edge, the backfill running on.
  property bool flushStartThrough: true
  property bool flushEndThrough: true
  property bool detached: false
  // A detached box's distance from the attach edge past the connector gap.
  // The surface starts at the attach edge, so the box slides in from
  // there: placed under a bar, from beneath it.
  property real detachedOffset: 0
  // Fill drawn this far behind the attach edge (the surface grows by it,
  // and v = 0 stays on the attach edge). A popout on a pill's far stroke
  // takes a pixel, to cover the pill stroke's anti-aliased fringe on the
  // pill's side, which is left standing alone as a faint line once the
  // popout covers the stroke itself.
  property real backfill: 0
  readonly property real _back: detached ? 0 : backfill
  // Fill drawn this far past a joined end, over what it joins, with no
  // stroke or shadow of its own: a submenu joined beside a popout on
  // a pill covers the popout's backfill row there, where the popout's shadow
  // would show as a dash
  property real joinBackfill: 0
  // The attach edge / the perpendicular edges a join meets are bare screen
  // edges (screen border off): the surface runs straight off them, with no
  // fillet onto them
  property bool straight: false
  property bool straightJoins: false
  // ...for each joined end on its own, where the two differ (a pill on a
  // bare edge joining a solid bar's stroke at one end)
  property bool straightJoinStart: straightJoins
  property bool straightJoinEnd: straightJoins

  // Breathing room between the box edge and its content: clears the
  // stroke, plus the popout padding every popout shares (Popouts.padding,
  // as EdgePopout and edge menus use). Callers that size the box from
  // their content add this on each side (see bar Popouts, submenus).
  readonly property int contentInset: Appearance.borderWidth + PopoutsConfig.padding

  property color fillColor: Theme.background
  property color strokeColor: Theme.foreground
  // Casts the shell's shadow (SurfaceShadow), for a surface whose
  // border shows: off for a bar's own pills, which their bar's casts
  property bool castShadow: false
  // The look it casts it in: BarStyle's, or the bar it grows out of.
  // Hosts take it from what the surface grows out of
  // (SurfaceContext.shadow), so joined shapes cast one shadow
  property var shadowLook: BarStyle.look
  // Rects (in this item's coordinates) its own shadow isn't cast on
  // either: a submenu's box beside it, whose translucent fill it would
  // show through (the blur window's shadow, cut by every shape, needs none)
  property var shadowHoles: []
  // How far past it the shadow reaches, which its window keeps room for
  readonly property int shadowReach: root.castShadow && root.shadowLook.shadow ? Math.ceil(root.shadowLook.shadowSize * 1.25) : 0
  // The blur window (BlurManager) draws this surface's fill and casts its
  // shadow (BlurShape.shadow): it draws its stroke and content only
  property bool backed: false
  // Filled solid while unbacked (BlurManager.opaqueOn: blur paused for a
  // fullscreen window on its screen)
  property bool opaque: false
  // Casting its own shadow, in its own window
  readonly property bool _ownShadow: root.castShadow && !root.backed
  // Where its shape runs on past its outline, for a shadow `reach` long
  // cast from it (rects in this item's coordinates, at rest): the shadow
  // beside a wall that carries on past it then runs on at full strength
  // to where it gives way to what carries it on (cut there by its holes),
  // as that one's runs on to it from the other side, with no step where
  // the two meet. Each is wide: a thin strip's blur is much weaker.
  // - behind a flush end, the wall it continues (an island's or pill's
  //   squared end, BarContainer._flushEnds), to the band hole;
  // - past a straight joined end, its far wall running on into the pill
  //   or island squared to meet it, or off a bare screen edge;
  // - behind an attach edge it runs straight off (a bare screen edge): its
  //   walls run on off screen, the shadow beside them not fading at it.
  // A bar's pills, cast by their bar, add theirs to its shadow's source.
  function shadowRunOn(reach) {
    if (root.detached || reach <= 0)
      return [];
    const along = Math.min(root.alongLength, reach * 2), across = Math.min(root.boxDepth, reach * 2);
    const behind = -root._back - reach, far = root.farV + root.half;
    const m = root._m;
    return (m.throughStart ? [root._rectFrom(0, behind, along, reach)] : []).concat(m.throughEnd ? [root._rectFrom(root.alongLength - along, behind, along, reach)] : [], root.joinStart && m.straightJoinStart ? [root._rectFrom(-reach, far - across, reach, across)] : [], root.joinEnd && m.straightJoinEnd ? [root._rectFrom(root.alongLength, far - across, reach, across)] : [], root.straight ? [root._rectFrom(0, behind, root.alongLength, reach)] : []);
  }
  readonly property var _shadowRunOn: root._ownShadow ? root.shadowRunOn(root.shadowReach) : []
  // Boxes (in this item's coordinates) of surfaces running on from its
  // box, a wall of theirs continuing one of its own (a submenu flush to a
  // free end of its side). Its shadow casts as if that wall ran on past
  // where the two meet (`source`), and gives way to theirs past it
  // (`hole`), cast the same way from their side (a flush end's run-on):
  // both at full strength where they meet, with no step
  property var wallsRunOn: []
  readonly property var _runsOn: {
    const reach = root.shadowReach;
    if (reach <= 0 || root.wallsRunOn.length === 0)
      return [];
    const b = root.boxRect, tol = root.strokeWidth + 2;
    const right = b.x + b.width, bottom = b.y + b.height;
    // Its attach side has no wall, unless it's a box of its own
    const wall = side => root.detached || side !== root.edge;
    const runs = [];
    root.wallsRunOn.forEach(s => {
      if (!s)
        return;
      // Beside it (submenus open to the left or right): its top or bottom
      // wall runs on there
      const toLeft = s.x + s.width <= b.x + tol, toRight = s.x >= right - tol;
      if (toLeft || toRight) {
        const x0 = toLeft ? b.x : right, w = Math.min(b.height, reach * 2);
        const sx = toLeft ? x0 - reach : x0, hx = toLeft ? x0 - reach * 2 : x0;
        if (wall(ScreenEdge.Top) && Math.abs(s.y - b.y) <= 1)
          runs.push({
            "source": Qt.rect(sx, b.y, reach, w),
            "hole": Qt.rect(hx, b.y - reach, reach * 2, reach)
          });
        if (wall(ScreenEdge.Bottom) && Math.abs(s.y + s.height - bottom) <= 1)
          runs.push({
            "source": Qt.rect(sx, bottom - w, reach, w),
            "hole": Qt.rect(hx, bottom, reach * 2, reach)
          });
      }
    });
    return runs;
  }
  // A copy of a surface (AttachedSurfaceCopy): its fill alone, its stroke
  // in `mirrorStroke`
  property bool mirror: false
  property color mirrorStroke: "transparent"
  // (a copy is drawn opaque: the blur window applies the opacity to all
  // of them at once, so where they overlap they don't stack)
  readonly property color _fill: root.mirror ? root.fillColor : root.backed ? "transparent" : root.opaque ? root.fillColor : Appearance.fill(root.fillColor)
  readonly property color _stroke: root.mirror ? root.mirrorStroke : root.strokeColor
  // Rects (in this item's coordinates) where its outline is left open:
  // what's joined to it over them (a submenu on its side, a popout on
  // a pill's far stroke) carries on there, its fill no longer hiding it
  property var strokeHoles: []
  // Ready to cut them from the first frame they come (HoledItem.keepLayer):
  // while surfaces are translucent, when they can
  readonly property bool _holesReady: Appearance.translucent && !root.mirror

  default property alias content: contentContainer.data
  // The content box, sliding with the surface: where things in the
  // content are within the box whether or not it's out yet
  readonly property Item contentBox: contentContainer

  // Along the attach edge, the part of what it attaches to that it covers,
  // from its start: what of it shows at that edge as it slides, the box
  // and as much of each fillet as has come out past the edge (the fillet
  // runs along the edge, then curves up into the wall). A stroke left open
  // under it (the border's, a pill's) opens only there, or a gap shows
  // past the fillets, or the stroke cuts across them.
  // How far it's behind that edge: slid, or moved by its host (a hiding
  // dock, `hiddenBehind`)
  property real hiddenBehind: 0
  // How far it has slid behind that edge (none once out)
  readonly property real slid: Math.abs(slideContainer.slideX) + Math.abs(slideContainer.slideY)
  // ...and in all: what context along its slide follows (PillBarJoin)
  readonly property real hiddenNow: root.slid + root.hiddenBehind
  // How far in from the surface's end the fillet shows at the edge, with
  // `hidden` of the surface still behind it (see SurfaceOutline._outline: a line along
  // the edge at v = half to sideU - R, an arc of radius R up to the wall)
  function _filletIn(margin, hidden) {
    if (margin <= 0)
      return 0;
    const R = filletRadius, h = half;
    // The stroke along the edge is a full stroke wide
    if (hidden <= strokeWidth)
      return 0;
    if (hidden >= h + R)
      return margin;
    const dv = h + R - hidden;
    return Math.min(margin, Math.max(0, margin + h - R + Math.sqrt(R * R - dv * dv)));
  }
  // The fillets are taken a stroke's width ahead of the slide: the opening
  // is drawn in another window (the bar's, the border's), which commits a
  // frame or so after this one, so a stub of stroke showed under each
  // fillet as it landed. Within a stroke of the edge the fillet's own
  // stroke lies over the one it opens, so opening it early shows nothing.
  readonly property real _filletHidden: Math.max(0, root.hiddenNow - root.strokeWidth)
  readonly property real coverStart: root._filletIn(root.startMargin, root._filletHidden)
  // (nothing once it's all behind the edge)
  readonly property real coverLength: root.hiddenNow >= root.depth ? 0 : root.alongLength - root.coverStart - root._filletIn(root.endMargin, root._filletHidden)
  // How much of that is the fillet curving up into each wall from the
  // attach edge (0 at a joined, flush or straight end): what it covers
  // shows round its curve, not across its square (a solid bar's shadow)
  readonly property real coverStartFillet: root._natural.filletStart ? Math.max(0, root.startMargin - root.coverStart) : 0
  readonly property real coverEndFillet: root._natural.filletEnd && root.coverLength > 0 ? Math.max(0, root.endMargin - (root.alongLength - root.coverStart - root.coverLength)) : 0

  readonly property bool vertical: edge === ScreenEdge.Left || edge === ScreenEdge.Right
  readonly property bool attachLeft: edge === ScreenEdge.Left
  readonly property bool attachRight: edge === ScreenEdge.Right
  readonly property bool attachTop: edge === ScreenEdge.Top
  readonly property bool attachBottom: edge === ScreenEdge.Bottom

  // ---- Geometry, in edge-local coordinates ----
  // u runs along the attach edge, v away from it (v = 0 is the attach
  // edge). Everything below is laid out as if attached to the Top edge,
  // then mapped onto the real edge (SurfaceOutline.toItem).
  readonly property real strokeWidth: Appearance.borderWidth
  // Stroke centre line offset, so the full stroke lies inside the shape
  readonly property real half: strokeWidth / 2
  // Concave fillet radius (where the box meets an edge) and convex corner
  // radius at the far side, matching a Rectangle's radius
  readonly property real filletRadius: Appearance.borderRadius
  readonly property real cornerRadius: Math.max(0, Appearance.borderRadius - half)
  // The far corners at each end of the attach edge: 0 squares one, where a
  // box runs flush into this surface (a pill stretched to carry it)
  property real startCornerRadius: cornerRadius
  property real endCornerRadius: cornerRadius
  // A detached box's near corners (at the attach edge), at each end: 0
  // squares one, where a submenu runs flush to it
  property real startNearRadius: Appearance.borderRadius
  property real endNearRadius: Appearance.borderRadius

  readonly property real boxAlong: vertical ? boxHeight : boxWidth
  readonly property real boxDepth: vertical ? boxWidth : boxHeight
  // The shape's metrics and paths (SurfaceOutline), so its footprint and
  // its copies agree with what's drawn. Its margins and natural start come
  // from what shapes its walls alone (`_baseSpec`): hosts place things by
  // them (a submenu, by the box's start) that decide how its joins look
  // (straightJoins) or whether a flush wall runs through, which mustn't
  // loop back into them.
  readonly property var _baseSpec: ({
      "edge": root.edge,
      "boxAlong": root.boxAlong,
      "boxDepth": root.boxDepth,
      "strokeWidth": root.strokeWidth,
      "filletRadius": root.filletRadius,
      "startCornerRadius": root.startCornerRadius,
      "endCornerRadius": root.endCornerRadius,
      "connectorGap": root.connectorGap,
      "joinStart": root.joinStart,
      "joinEnd": root.joinEnd,
      "flushStart": root.flushStart,
      "flushEnd": root.flushEnd,
      "detached": root.detached,
      "detachedOffset": root.detachedOffset,
      "backfill": root.backfill,
      "straight": root.straight
    })
  readonly property var _spec: Object.assign({}, root._baseSpec, {
    "flushStartThrough": root.flushStartThrough,
    "flushEndThrough": root.flushEndThrough,
    "straightJoins": root.straightJoins,
    "straightJoinStart": root.straightJoinStart,
    "straightJoinEnd": root.straightJoinEnd,
    "joinBackfill": root.joinBackfill
  })
  readonly property var _natural: SurfaceOutline.metrics(root._baseSpec)
  readonly property var _m: SurfaceOutline.withBoxStart(root._spec, SurfaceOutline.metrics(root._spec), root.boxStart)
  readonly property bool _straightJoinStart: _m.straightJoinStart
  readonly property bool _straightJoinEnd: _m.straightJoinEnd
  // Room each end for its fillet: the arc's run (EdgeAttach.filletMargin)
  readonly property real startMargin: _natural.startMargin
  readonly property real endMargin: _natural.endMargin
  readonly property real alongLength: _natural.alongLength
  // Where the box starts away from the attach edge. Detached, a connector
  // gap's half past its lead. Attached, on the attach edge: the fillets
  // curve outside the side walls, so the band they span is the box's own
  // rather than empty padding above the content. Pushed back only as far
  // as a shallow box needs for a side wall to clear its fillet and far
  // corner.
  readonly property real naturalBoxStart: _natural.naturalBoxStart
  // Overridable: a bar's pills keep a half connector gap (sized by it)
  property real boxStart: naturalBoxStart
  // The box and the half connector gap past it (and a joined end's fillet
  // along the perpendicular stroke)
  readonly property real depth: _m.depth

  // Along the edge: box + fillet squares. Away from the edge: box +
  // connector gap.
  implicitWidth: vertical ? depth : alongLength
  implicitHeight: vertical ? alongLength : depth

  // Box sides and far edge (stroke centre line)
  readonly property real sideU: _natural.sideU
  readonly property real farSideU: _natural.farSideU
  readonly property real farV: _m.farV
  // How far in from its attach side (the backfill included) a joined end
  // covers the perpendicular stroke: its fill runs along it to the join's
  // fillet (SurfaceOutline.fillPath)
  readonly property real joinCover: _m.back + (root._straightJoinStart ? root.farV : root.farV + root.filletRadius)
  readonly property real joinCoverEnd: _m.back + (root._straightJoinEnd ? root.farV : root.farV + root.filletRadius)
  // ...to the far wall alone, fillet or not (where a host decides whether
  // it curves in from)
  // (from the metrics without the joins' straightness, which a pill bar's
  // join decides from where this wall is: PillBarJoin.filleted)
  readonly property real joinWall: root._back + root.boxStart + root.boxDepth - root._natural.half
  // The fillet each joined end curves into that stroke with, at the far
  // end of its cover (0 for one running straight into it)
  readonly property real joinFillet: root._straightJoinStart ? 0 : root.filletRadius
  readonly property real joinFilletEnd: root._straightJoinEnd ? 0 : root.filletRadius
  // ...as much of it as is out past its edge now (none while it's behind)
  readonly property real joinShown: Math.max(0, root.joinCover - root.hiddenNow)
  readonly property real joinShownEnd: Math.max(0, root.joinCoverEnd - root.hiddenNow)

  // The content box in this item's coordinates, at rest (not slid). On
  // every side but the attach edge it coincides with the outer edge of
  // the stroke, so things attaching to this surface (submenus) can
  // line their own stroke up with it.
  readonly property rect boxRect: root._rectFrom(startMargin, boxStart, boxAlong, boxDepth)

  // What it covers, in this item's coordinates at rest
  // (SurfaceOutline.footprint): the box, its fillets and backfill
  readonly property var footprint: SurfaceOutline.footprint(root._spec, root._m, root.width, root.height)

  // An edge-local rectangle (u, v, along, deep) in item coordinates
  function _rectFrom(u, v, along, deep) {
    const r = SurfaceOutline.rectFrom(edge, width, height, _back, u, v, along, deep);
    return Qt.rect(r.x, r.y, r.width, r.height);
  }
  // Its attach side's fillet at its start or end, with its anti-aliased
  // fringe, as a stroke hole: a surface joined beside it (a submenu on the
  // stroke it grows from) runs on along that stroke, over the fillet
  function attachFilletHole(atStart) {
    const along = (atStart ? root.startMargin : root.endMargin) + root.strokeWidth + 1;
    return root._rectFrom(atStart ? 0 : root.alongLength - along, -1, along, root.filletRadius + root.strokeWidth + 2);
  }
  // Its stroke holes under a submenu (SubPopout): `hole`, the stroke the
  // submenu covers on the box's side (in the window's coordinates, or
  // null), and joined to the stroke the box grows from (`sideJoined`, on
  // its start side with `atStart`), the fillet there
  function submenuHoles(hole, sideJoined, atStart) {
    const holes = hole ? [Qt.rect(hole.x - root.x, hole.y - root.y, hole.width, hole.height)] : [];
    return sideJoined ? holes.concat([root.attachFilletHole(atStart)]) : holes;
  }

  // Its fill as blur region pieces in this item's coordinates, slid as
  // drawn (SurfaceOutline.blurRegion): what the blur window asks the
  // compositor to blur for it, where that blurs only what a window asks
  function blurPieces() {
    return SurfaceOutline.blurRegion(root._spec, root._m, root.width, root.height, slideContainer.slideX, slideContainer.slideY, {
      "start": root.startNearRadius,
      "end": root.endNearRadius
    });
  }

  // Fill: the outline, closed back along the attach edge.
  // Joined ends also cover the perpendicular stroke up to the fillet.
  readonly property string fillPath: SurfaceOutline.fillPath(root._spec, root._m, root.width, root.height)

  // Stroke: the outline alone, open along the attach edge and on joined
  // ends, whose ends sit exactly on the strokes they continue
  readonly property string strokePath: SurfaceOutline.strokePath(root._spec, root._m, root.width, root.height)

  SlideAnimation {
    id: slideContainer
    anchors.fill: parent

    active: root.active
    slideFromRight: root.attachRight
    slideFromLeft: root.attachLeft
    slideFromTop: root.attachTop
    slideFromBottom: root.attachBottom
    animationDuration: root.animationDuration

    containerHeight: root.height
    containerWidth: root.width
    enableFade: false
    // (and the row past a joined end, joinBackfill, which it covers)
    overflow: Math.max(root.shadowReach, root.joinBackfill)

    // The shadow the outline casts, only outside it (none shows
    // through a translucent fill), from a copy of it filled (its own fill
    // may be the blur window's): the content doesn't need its own
    OutsideShadow {
      id: ownShadow
      target: shadowShape
      hideTarget: true
      active: root._ownShadow
      look: root.shadowLook
      // Nothing past a joined end: what it joins (the border's frame, a
      // pill) runs on there, under this window, as the blur window's cut
      // to every shape leaves it. Nor on the stroke it grows out of, beside
      // it: this window is over that stroke's, so the shadow there dimmed
      // it, darkest under this surface's soft edge, a seam where the two
      // strokes meet (none on a bare edge, which has no stroke).
      holes: {
        const runs = root._runsOn.map(r => r.hole);
        if (root.detached)
          return runs;
        const reach = ownShadow.reach;
        const v = -root._back - reach, deep = root._back + root.depth + reach * 2;
        // (to the stroke's outer edge where it is in the window, not where
        // it is on the surface still behind its edge: there the band let a
        // line of this shadow through over the stroke, beside its wall,
        // doubling the shadow of what it grows from)
        const band = root.straight ? [] : [root._rectFrom(-reach, v, root.alongLength + reach * 2, reach + root._back + root.strokeWidth + root.hiddenNow)];
        // A straight joined end's far wall runs on into the stroke it
        // joins (its first stroke's width of the end lies over that
        // stroke): what it joins casts beside the wall up to its outer
        // edge, as the band leaves a flush end's to it
        const far = root.farV + root.half, sw = root.strokeWidth;
        const straightStart = root.joinStart && root._straightJoinStart ? [root._rectFrom(-reach, far, reach + sw, reach)] : [];
        const straightEnd = root.joinEnd && root._straightJoinEnd ? [root._rectFrom(root.alongLength - sw, far, reach + sw, reach)] : [];
        return (root.joinStart ? [root._rectFrom(-reach, v, reach, deep)] : []).concat(root.joinEnd ? [root._rectFrom(root.alongLength, v, reach, deep)] : [], straightStart, straightEnd, band, root.shadowHoles, runs);
      }
    }

    Item {
      id: shadowShape
      anchors.fill: parent
      visible: root._ownShadow

      Shape {
        anchors.fill: parent
        visible: !root.detached
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          fillColor: "black"
          strokeColor: "transparent"
          strokeWidth: 0

          PathSvg {
            path: root.fillPath
          }
        }

        ShapePath {
          fillColor: "transparent"
          strokeColor: "black"
          strokeWidth: root.strokeWidth
          capStyle: ShapePath.FlatCap
          joinStyle: ShapePath.MiterJoin

          PathSvg {
            path: root.strokePath
          }
        }
      }

      // Where its shape runs on past its outline (shadowRunOn)
      Repeater {
        model: root._shadowRunOn.length

        Rectangle {
          required property int index
          readonly property rect area: root._shadowRunOn[index] ?? Qt.rect(0, 0, 0, 0)
          x: area.x
          y: area.y
          width: area.width
          height: area.height
          color: "black"
        }
      }
      // ...and past the walls surfaces running on from its box continue
      Repeater {
        model: root._runsOn.length

        Rectangle {
          required property int index
          readonly property rect area: root._runsOn[index]?.source ?? Qt.rect(0, 0, 0, 0)
          x: area.x
          y: area.y
          width: area.width
          height: area.height
          color: "black"
        }
      }

      Rectangle {
        visible: root.detached
        x: detachedBox.x
        y: detachedBox.y
        width: detachedBox.width
        height: detachedBox.height
        topLeftRadius: detachedBox.topLeftRadius
        topRightRadius: detachedBox.topRightRadius
        bottomLeftRadius: detachedBox.bottomLeftRadius
        bottomRightRadius: detachedBox.bottomRightRadius
        color: "black"
      }
    }

    // The outline (or detached box)
    Item {
      id: outlineLayer
      anchors.fill: parent

      HoledItem {
        anchors.fill: parent
        visible: !root.detached
        holes: root.strokeHoles
        keepLayer: root._holesReady && !root.detached

        Shape {
          id: outline
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer

          ShapePath {
            fillColor: root._fill
            strokeColor: "transparent"
            strokeWidth: 0

            PathSvg {
              path: root.fillPath
            }
          }

          ShapePath {
            fillColor: "transparent"
            strokeColor: root._stroke
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin

            PathSvg {
              path: root.strokePath
            }
          }
        }
      }

      // Detached: a box of its own, not joined to anything. Its far
      // corners square as the outline's do (start/endCornerRadius, the
      // stroke's centre line: the outer edge is half a stroke out).
      HoledItem {
        anchors.fill: parent
        visible: root.detached
        holes: root.strokeHoles
        keepLayer: root._holesReady && root.detached

        Rectangle {
          id: detachedBox
          readonly property real startRadius: root.startCornerRadius > 0 ? root.startCornerRadius + root.half : 0
          readonly property real endRadius: root.endCornerRadius > 0 ? root.endCornerRadius + root.half : 0
          // Far corners from start/endRadius, near ones from start/endNearRadius
          topLeftRadius: root.attachBottom || root.attachRight ? detachedBox.startRadius : root.startNearRadius
          topRightRadius: root.attachLeft ? detachedBox.startRadius : root.attachBottom ? detachedBox.endRadius : root.attachTop ? root.endNearRadius : root.startNearRadius
          bottomLeftRadius: root.attachTop ? detachedBox.startRadius : root.attachRight ? detachedBox.endRadius : root.attachBottom ? root.startNearRadius : root.endNearRadius
          bottomRightRadius: root.attachTop || root.attachLeft ? detachedBox.endRadius : root.endNearRadius
          x: root.boxRect.x
          y: root.boxRect.y
          width: root.boxRect.width
          height: root.boxRect.height
          color: root._fill
          border.color: root._stroke
          border.width: root.strokeWidth
        }
      }
    }

    // Past a joined end (joinBackfill), outside the shadowed outline
    Rectangle {
      readonly property rect area: root.joinStart ? root._rectFrom(-root.joinBackfill, -root._back, root.joinBackfill, root._back + root.boxStart + root.boxDepth) : root._rectFrom(root.alongLength, -root._back, root.joinBackfill, root._back + root.boxStart + root.boxDepth)
      visible: !root.detached && root.joinBackfill > 0 && (root.joinStart || root.joinEnd)
      x: area.x
      y: area.y
      width: area.width
      height: area.height
      color: root._fill
    }
    // ...with a straight join's far wall running on through it
    // (SurfaceOutline's joinThroughStart/End)
    Rectangle {
      readonly property rect area: root._rectFrom(-root._m.joinThroughStart, root._m.farV - root._m.half, root._m.joinThroughStart, root.strokeWidth)
      visible: !root.detached && root._m.joinThroughStart > 0
      x: area.x
      y: area.y
      width: area.width
      height: area.height
      color: root._stroke
    }
    Rectangle {
      readonly property rect area: root._rectFrom(root.alongLength, root._m.farV - root._m.half, root._m.joinThroughEnd, root.strokeWidth)
      visible: !root.detached && root._m.joinThroughEnd > 0
      x: area.x
      y: area.y
      width: area.width
      height: area.height
      color: root._stroke
    }

    // Content box: same placement the old bordered Rectangle had, so
    // popout content is laid out exactly as before
    Item {
      id: contentContainer
      x: root.boxRect.x
      y: root.boxRect.y
      width: root.boxWidth
      height: root.boxHeight
    }
  }
}
