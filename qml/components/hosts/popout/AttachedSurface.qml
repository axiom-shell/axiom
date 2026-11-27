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
  property real boxWidth: 100 // a placeholder, always set
  property real boxHeight: 100 // a placeholder, always set
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
  // A detached box fades in and out in place instead of sliding
  property bool fade: false
  // How far it has faded in (1 unless it fades)
  readonly property real shownOpacity: slideContainer.shownOpacity
  // Where its content is from its place as it slides (what's drawn for
  // it elsewhere follows: a tiled menu's tiles' blur shapes)
  readonly property real slideX: slideContainer.slideX
  readonly property real slideY: slideContainer.slideY
  // The opacity its host draws it at, fading it itself (a detached dock
  // fading in): its copies (the blur window's fill) draw at it too
  property real hostOpacity: 1
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

  property color fillColor: Style.surfacePage
  property color strokeColor: Style.frameStroke
  // Casts the shell's shadow (SurfaceShadow), for a surface whose
  // border shows: off for a bar's own pills, which their bar's casts
  property bool castShadow: false
  // The look it casts it in: BarStyle's, or the bar it grows out of.
  // Hosts take it from what the surface grows out of
  // (SurfaceContext.shadow), so joined shapes cast one shadow
  property var shadowLook: BarStyle.look
  // How far past it the shadow reaches, which its window keeps room for
  readonly property int shadowReach: root.castShadow && root.shadowLook.shadow ? Math.ceil(root.shadowLook.shadowSize * 1.25) : 0
  // The blur window (BlurManager) draws this surface's fill and casts its
  // shadow (BlurShape.shadow): it draws its stroke and content only
  property bool backed: false
  // Filled solid while unbacked (BlurManager.opaqueOn: blur paused for a
  // fullscreen window on its screen)
  property bool opaque: false
  // Draws no box (fill, stroke or shadow) of its own, only its content,
  // which keeps the room a shadow would take (a tiled menu: MenuTiles)
  property bool hollow: false
  // A copy of a surface (AttachedSurfaceCopy): its fill in `fillColor`, its
  // stroke in `mirrorStroke`, both set per capture by the blur window
  // (Copies.draws); cut by its own `strokeHoles` through HoledCopy
  property bool mirror: false
  property color mirrorStroke: "transparent"
  // (a copy is drawn opaque: the blur window blends the strokes over the
  // fills itself, ChromeComposite)
  readonly property color _fill: root.mirror ? root.fillColor : root.backed || root.hollow ? "transparent" : root.opaque ? root.fillColor : Style.edgeFill(root.fillColor, false)
  readonly property color _stroke: root.mirror ? root.mirrorStroke : root.backed || root.hollow ? "transparent" : root.strokeColor
  // Rects (in this item's coordinates) where its outline is left open:
  // what's joined to it over them (a submenu on its side, a popout on
  // a pill's far stroke) carries on there, its fill no longer hiding it
  property var strokeHoles: []

  default property alias content: contentContainer.data
  // The pointer is on the surface (its box and fillets)
  readonly property bool hovered: surfaceHover.hovered
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
    const R = attachFilletRadius, h = half;
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
  // ...to where it ends (at its start, so nothing, once it's all behind the edge)
  readonly property real coverEnd: root.hiddenNow >= root.depth ? root.coverStart : root.alongLength - root._filletIn(root.endMargin, root._filletHidden)
  // How much of that is the fillet curving up into each wall from the
  // attach edge (0 at a joined, flush or straight end): what it covers
  // shows round its curve, not across its square (a solid bar's shadow)
  readonly property real coverStartFillet: root._natural.filletStart ? Math.max(0, root.startMargin - root.coverStart) : 0
  readonly property real coverEndFillet: root._natural.filletEnd && root.coverEnd > root.coverStart ? Math.max(0, root.endMargin - (root.alongLength - root.coverEnd)) : 0

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
  // The attach side's fillets alone: a pill, too shallow for both a full
  // fillet and its far corners, scales them alike (SurfaceOutline.fitRadii)
  property real attachFilletRadius: filletRadius
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
      "attachFilletRadius": root.attachFilletRadius,
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
  // ...as it would be with a box `boxDepth` deep: a host sizing for its
  // content at its largest, not as it eases there
  function depthFor(boxDepth) {
    const spec = Object.assign({}, root._baseSpec, {
      "boxDepth": boxDepth
    });
    return SurfaceOutline.withBoxStart(spec, SurfaceOutline.metrics(spec), root.boxStart === root.naturalBoxStart ? SurfaceOutline.metrics(spec).naturalBoxStart : root.boxStart).depth;
  }

  // Along the edge: box + fillet squares. Away from the edge: box +
  // connector gap.
  implicitWidth: vertical ? depth : alongLength
  implicitHeight: vertical ? alongLength : depth

  // Far edge (stroke centre line)
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
  readonly property real joinSide: root._back + root.boxStart + root.boxDepth - root._natural.half
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
    return root._rectFrom(atStart ? 0 : root.alongLength - along, -1, along, root.attachFilletRadius + root.strokeWidth + 2);
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
  // (a copy reads its source's: AttachedSurfaceCopy)
  property string fillPath: SurfaceOutline.fillPath(root._spec, root._m, root.width, root.height)

  // Stroke: the outline alone, open along the attach edge and on joined
  // ends, whose ends sit exactly on the strokes they continue
  // (a copy reads its source's: AttachedSurfaceCopy)
  property string strokePath: SurfaceOutline.strokePath(root._spec, root._m, root.width, root.height)

  SlideAnimation {
    id: slideContainer
    anchors.fill: parent

    active: root.active
    fade: root.fade
    slideFromRight: root.attachRight
    slideFromLeft: root.attachLeft
    slideFromTop: root.attachTop
    slideFromBottom: root.attachBottom
    animationDuration: root.animationDuration

    // Room for the shadow (and the row past a joined end, joinBackfill, which it covers)
    overflow: Math.max(root.shadowReach, root.joinBackfill)
    // A copy draws its stroke: a pixel past a wall standing on its start
    // or end edge (no fillet or join there: flush, straight), its
    // anti-aliased fringe, which the clip cut at a fractional scale; never
    // past a filleted end, whose stroke's cap there is the lower shape's
    // pixel (HoledCopy). A host keeps its window's own clip
    startOverflow: root.mirror && !root.detached && !root._natural.filletStart && !root.joinStart ? 1 : 0
    endOverflow: root.mirror && !root.detached && !root._natural.filletEnd && !root.joinEnd ? 1 : 0

    // The outline (or detached box): a host draws it plainly; a copy hands
    // it to a HoledCopy, its fill whole and its stroke outside the holes
    Item {
      id: outlineLayer
      anchors.fill: parent

      Loader {
        anchors.fill: parent
        visible: !root.mirror && !root.detached
        active: !root.mirror
        sourceComponent: outlineFill
      }

      Loader {
        anchors.fill: parent
        visible: !root.mirror && !root.detached
        active: !root.mirror
        sourceComponent: outlineStrokeOnly
      }

      HoledCopy {
        anchors.fill: parent
        visible: root.mirror
        holes: root.mirror ? root.strokeHoles : []
        fillOnly: root.mirror ? (root.detached ? detachedFill : outlineFill) : null
        strokeOnly: root.mirror ? (root.detached ? detachedStrokeOnly : outlineStrokeOnly) : null
      }

      // Detached: a box of its own, not joined to anything
      Loader {
        anchors.fill: parent
        visible: !root.mirror && root.detached
        active: !root.mirror
        sourceComponent: detachedDrawing
      }

      Component {
        id: outlineFill

        Shape {
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
        }
      }

      Component {
        id: outlineStrokeOnly

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer

          ShapePath {
            fillColor: "transparent"
            strokeColor: root._stroke
            // Drawn a 64th in on each edge (Utils.tieInset): a CurveRenderer stroke whose edge is on a device pixel's centre draws that pixel full
            strokeWidth: root.strokeWidth - Utils.tieInset * 2
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin

            PathSvg {
              path: root.strokePath
            }
          }
        }
      }

      Component {
        id: detachedDrawing

        // (in an Item: a sized Loader would resize the box to the surface)
        Item {
          DetachedBox {
            color: root._fill
            border.color: root._stroke
            border.width: root.strokeWidth
          }
        }
      }

      Component {
        id: detachedStrokeOnly

        Item {
          DetachedBox {
            color: "transparent"
            border.color: root._stroke
            border.width: root.strokeWidth
          }
        }
      }

      Component {
        id: detachedFill

        Item {
          DetachedBox {
            color: root._fill
          }
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

      // On the whole surface, which holds the content (declared here, as
      // the surface's own children are its content's)
      HoverHandler {
        id: surfaceHover
        parent: root
      }
    }
  }

  // The detached box's rect and corner radii, defined once: its far corners
  // square as the outline's do (start/endCornerRadius, the stroke's centre
  // line: the outer edge is half a stroke out), its near ones from
  // start/endNearRadius. The shadow's mask and the box drawn (host or copy)
  component DetachedBox: Rectangle {
    id: box
    readonly property real startRadius: root.startCornerRadius > 0 ? root.startCornerRadius + root.half : 0
    readonly property real endRadius: root.endCornerRadius > 0 ? root.endCornerRadius + root.half : 0
    topLeftRadius: root.attachBottom || root.attachRight ? box.startRadius : root.startNearRadius
    topRightRadius: root.attachLeft ? box.startRadius : root.attachBottom ? box.endRadius : root.attachTop ? root.endNearRadius : root.startNearRadius
    bottomLeftRadius: root.attachTop ? box.startRadius : root.attachRight ? box.endRadius : root.attachBottom ? root.startNearRadius : root.endNearRadius
    bottomRightRadius: root.attachTop || root.attachLeft ? box.endRadius : root.endNearRadius
    x: root.boxRect.x
    y: root.boxRect.y
    width: root.boxRect.width
    height: root.boxRect.height
  }
}
