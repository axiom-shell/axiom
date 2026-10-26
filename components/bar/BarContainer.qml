pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout
import qs.components.reusable

// Lays out a bar's five widget sections along its main axis in one pass,
// so they can never overlap: `left`/`right` hug the ends, `center` stays
// centered on the bar with `leftCenter`/`rightCenter` beside it. When the
// side sections crowd it, the center block slides towards the roomier side
// (unless the bar's `lockCenter` pins it, making each side make room on its
// own half instead); then elastic widgets shrink, and if even their minimum sizes don't fit,
// the lowest-priority widgets anywhere on the bar are hidden (see
// WidgetGroup for how a section fits itself into what it's given).
Rectangle {
  id: root

  required property var barConfig
  property var screen
  property var panel

  readonly property bool isVertical: barConfig.vertical
  readonly property real length: isVertical ? height : width

  // Emitted whenever widgets may have moved, so an open popout can follow
  // its anchor
  signal layoutUpdated

  // The surface layer paints the bar
  color: "transparent"

  readonly property bool pills: barConfig.pills
  // A floating bar: islands held off the edge, read like pills by the
  // popouts (pillRects), but drawn on their own (as boxes, from pillShapes)
  readonly property bool islands: barConfig.island
  // What each end meets (BarEnds): the frame, or a bar it makes way for
  readonly property var ends: barConfig.ends
  // How far in from an end islands may reach: their float gap from the
  // stroke there (bar-window 0 past its reach onto it), or held clear of
  // a bar it makes way for, as a surface held off an edge
  function _islandInset(end) {
    return end.held ? end.over + end.gap : end.reach + root.barConfig.floatGap;
  }
  // Where islands may reach along the bar, from its start
  readonly property real islandFrom: root._islandInset(root.ends.start)
  readonly property real islandEnd: root.length - root._islandInset(root.ends.end)
  // Fillet room each side of a pill, as for popouts (AttachedSurface)
  readonly property int pillConnector: Appearance.connectorGap
  // Kept clear at each end. A pill at an end instead sits flush on the
  // perpendicular edge's stroke (bar-window 0 along a bar inside the
  // border) and joins it, so its widgets only need the pill inset (the
  // stroke and the padding, or the screen margin too on a bare edge). An
  // island's widgets sit inside its stroke and padding. A transparent
  // bar's keep the gap they keep across it, past the stroke there; a solid
  // one's the screen margin, or on a bare edge at least that gap. At an
  // end held clear of another bar, a pill's free end and its fillet stay
  // past the held gap, and a plain bar's widgets at least its padding past
  // that bar.
  function _endMargin(end) {
    if (root.pills) {
      if (!end.held)
        return root.barConfig.pillInset;
      const fillet = Appearance.screenBorder ? EdgeAttach.filletMargin(Appearance.borderWidth, Appearance.borderRadius) : 0;
      return end.over + end.gap + fillet + root.barConfig.pillGap;
    }
    if (root.islands)
      return root._islandInset(end) + root.barConfig.islandGap;
    if (end.held)
      return end.over + Math.max(end.gap, root.barConfig.padding);
    // The gap its widgets keep across the bar, from what covers its outer
    // edge, kept past the stroke at the end too (or the bare screen edge)
    const across = root.barConfig.crossStart - (root.barConfig.insideBorder ? Appearance.borderWidth : 0);
    if (!root.barConfig.solid)
      return end.reach + across;
    return Appearance.screenBorder ? Appearance.screenMargin : Math.max(Appearance.screenMargin, across);
  }
  readonly property var endMargins: [root._endMargin(root.ends.start), root._endMargin(root.ends.end)]

  // One { start, length, joinStart, joinEnd } per pill along the bar: each
  // non-empty section, merged with its neighbour when they're at most
  // pillMerge apart, grown by the pill gap. Pills reaching an end are
  // stretched onto it and join it. On a floating bar, its islands
  // (BarLayout.islandRects): one along it, or one per group.
  // Pills asked to reach an end run there, or a stub grows there for them
  // (BarLayout.endReaches, setRequest).
  readonly property var pillRects: {
    if (islands)
      return BarLayout.islandRects(root._spans, root.barConfig.islandGap, root.barConfig.pillMerge, root.islandFrom, root.islandEnd, !root.barConfig.islandPills);
    return root.pills ? root._endReach.rects : [];
  }
  readonly property var _endReach: BarLayout.endReaches(root.sectionPills, root._endReachList, root.length, root.barConfig.pillMerge, root.pillConnector)
  readonly property var sectionPills: {
    if (!pills)
      return [];
    const spans = root._spans.slice();
    const merged = [];
    spans.forEach(span => {
      const last = merged[merged.length - 1];
      if (last && span.start - last.end <= root.barConfig.pillMerge)
        last.end = Math.max(last.end, span.end);
      else
        merged.push(span);
    });
    // A free end sits the pill gap out from its widgets. An end that would
    // reach the frame (the end sections, which sit endMargin in) joins it,
    // the frame standing in for the gap; not a bar it makes way for, which
    // has no stroke to join (BarEnds).
    const gap = root.barConfig.pillGap;
    const reach = root.barConfig.overlap + 0.5;
    return merged.map(m => {
      const joinStart = root.ends.start.joinable && m.start - gap <= reach;
      const joinEnd = root.ends.end.joinable && m.end + gap >= root.length - reach;
      const start = joinStart ? 0 : m.start - gap;
      const end = joinEnd ? root.length : m.end + gap;
      return {
        "start": start,
        "length": end - start,
        "joinStart": joinStart,
        "joinEnd": joinEnd
      };
    });
  }

  // The sections with widgets showing, as { start, end } along the bar.
  // Dividers at a section's end facing another section stand in the gap
  // between them, outside its pill (BarLayout.edgeHang); at the first and
  // last sections showing, they stay in it, as padding.
  readonly property var _spans: {
    const shown = root._groups.filter(g => g.drawnLength > 0.5).sort((a, b) => a.drawnPos - b.drawnPos);
    return shown.map((g, i) => ({
          "start": g.drawnPos + (i > 0 ? g.drawnHang.lead : 0),
          "end": g.drawnPos + g.drawnLength - (i < shown.length - 1 ? g.drawnHang.trail : 0)
        }));
  }

  // The pills (or islands) as drawn: stretched to carry the surfaces open
  // on them, and joining any they then reach, while those are open
  readonly property var pillShapes: BarLayout.stretchIslands(root.pillRects, root._shownStretches, root.barConfig.pillMerge)

  // What the surfaces standing on or joining this bar ask of it, by owner
  // (PillStretch: a bar popout, an edge popout, a dock, a submenu, a pill
  // bar merging into this one's corner), each { stretch, opening,
  // endReach }, drawn as sent: each owner sets the pace it changes at.
  // - stretch: a pill stretched past its ends to carry a surface's fillets
  //   ({ index, start, end, squareStart, squareEnd, joinStart, joinEnd },
  //   EdgeAttach.place's stretch; `covered`, false while its surface is
  //   still all behind the stroke, EdgePlacement). pillRects stays
  //   unstretched.
  // - opening: where a surface covers a pill's (or island's) inner stroke,
  //   { start, end } along the bar (`keepFill`: while opaque, only the
  //   stroke and its outer edge, for a surface joining it end-on, which
  //   covers the stroke but nothing inside it). While surfaces are
  //   translucent the stroke is left open there (their fill no longer
  //   hides it).
  // - endReach: a pill asked to run from an end of the bar ({ atStart, to,
  //   straight }, BarLayout.endReaches), by a surface joining this bar from
  //   the perpendicular edge: a pill bar merging into this one's corner
  //   (CornerMerge), a popout whose side joins it (PillBarJoin)
  // Each part is kept by itself, so one changing never re-runs what reads
  // the others: a stretch sent as drawn reads the pills, which end reaches
  // shape (pillRects).
  property var _stretches: ({})
  property var _endReaches: ({})
  property var _openings: ({})
  readonly property var _stretchList: BarLayout.onPills(root.pillRects, Object.keys(root._stretches).map(k => root._stretches[k])).concat(root.pills ? root._endReach.stretches : [])
  readonly property var _endReachList: Object.keys(root._endReaches).map(k => root._endReaches[k])
  readonly property var _openingList: Object.keys(root._openings).map(k => root._openings[k])
  // `map` with `owner`'s entry set to `value` (or with null cleared), or
  // null where that changes nothing
  function _withEntry(map, owner, value) {
    if (Utils.deepEqual(map[owner] ?? null, value ?? null))
      return null;
    const next = Object.assign({}, map);
    if (value)
      next[owner] = value;
    else
      delete next[owner];
    return next;
  }
  // Sets (or with null clears) `owner`'s request
  function setRequest(owner, request) {
    const stretches = root._withEntry(root._stretches, owner, request?.stretch);
    const endReaches = root._withEntry(root._endReaches, owner, request?.endReach);
    const openings = root._withEntry(root._openings, owner, request?.opening);
    if (stretches)
      root._stretches = stretches;
    if (endReaches)
      root._endReaches = endReaches;
    if (openings)
      root._openings = openings;
  }
  // A solid bar's own inner stroke (border off) around the openings
  readonly property var _strokePieces: Utils.subtractSpans(0, root.length, root._openingList)

  // A stretch changing while its popout is open (the calendar opening its
  // editor) was drawn but not shown: the bar's next frame was rendered,
  // yet the compositor kept showing the one before until something else
  // made the bar commit again (a hover, the clock). So for a few frames
  // after a stretch or an opening changes, the bar draws a frame of its
  // own (an invisible pixel flipping), and the last one shown is the right
  // one: an opening follows a surface sliding in another window.
  on_ShownStretchesChanged: repaint.burst()
  on_OpeningListChanged: repaint.burst()

  // A stretch along the bar (from..to, in this item's coordinates) that a
  // surface joined to the border's inner stroke covers there, as
  // SurfaceManager.setBorderOpening takes it (screen px along the edge), so
  // the border leaves its stroke open under a translucent fill: a pill, a
  // popout merged into the bar or on a solid bar's inner edge. Null while
  // surfaces are solid, with the border off, or until the bar's place on
  // screen is known (the bar editor's preview has none).
  function borderOpening(from, to) {
    if (!Appearance.translucent || !Appearance.screenBorder || !root.blurOrigin || to <= from)
      return null;
    const at = root.isVertical ? root.blurOrigin.y : root.blurOrigin.x;
    return {
      "screen": root.blurScreen,
      "edge": Bar.edgeName(root.barConfig.location),
      "start": at + from,
      "end": at + to
    };
  }
  // The same for a surface's joined end (`surface`, an AttachedSurface in
  // this item, joined at its start or end): it covers the perpendicular
  // edge's stroke, from the bar's outer edge to its join's fillet
  function joinOpening(surface, atStart) {
    if (!Appearance.translucent || !Appearance.screenBorder || !root.blurOrigin)
      return null;
    const from = root.isVertical ? root.blurOrigin.x + surface.x : root.blurOrigin.y + surface.y;
    const span = (root.isVertical ? root.panel?.screen?.width : root.panel?.screen?.height) ?? 0;
    return Object.assign({
      "screen": root.blurScreen
    }, EdgeAttach.joinOpening(Bar.edgeName(root.barConfig.location), atStart, from, root.isVertical ? surface.width : surface.height, (atStart ? surface.joinShown : surface.joinShownEnd), span, atStart ? surface.joinFillet : surface.joinFilletEnd));
  }

  // The bar an end makes way for, as its container, when it's of `kind`
  // (BarEnds' end kind) and showing: a solid bar with the border off
  // ("solidBar"), whose inner stroke a pill joined there curves into, or a
  // pill bar ("pillBar"), whose end pill this bar's end pill merges into
  // (CornerMerge)
  function barAt(atStart, kind) {
    if ((atStart ? root.ends.start : root.ends.end).kind !== kind)
      return null;
    const panel = ShellManager.barOn(root.blurScreen, root.isVertical ? (atStart ? Bar.Top : Bar.Bottom) : (atStart ? Bar.Left : Bar.Right));
    return panel?.visible ? panel.container : null;
  }
  readonly property var solidStart: root.barAt(true, "solidBar")
  readonly property var solidEnd: root.barAt(false, "solidBar")
  readonly property var pillBarStart: root.barAt(true, "pillBar")
  readonly property var pillBarEnd: root.barAt(false, "pillBar")
  // Where a surface in this item (`surface`, joined at its start or end)
  // covers the stroke of the bar it joins there (`other`), along that bar
  // (its coordinates), as EdgeAttach.joinOpening for the border's: on
  // whole pixels (SurfaceContext.opening), as the fillet's tail and the
  // stroke would each cover half of a part one, leaving a dark notch. Its
  // fillet (AttachedSurface.joinFillet) lies at the end for a surface on
  // this bar's near side, and that bar's shadow follows round it.
  function _solidJoinOf(surface, atStart, other) {
    const origin = other?.blurOrigin ?? null;
    if (!origin || !root.blurOrigin)
      return null;
    const from = root.isVertical ? root.blurOrigin.x + surface.x : root.blurOrigin.y + surface.y;
    const span = (root.isVertical ? root.panel?.screen?.width : root.panel?.screen?.height) ?? 0;
    const opening = EdgeAttach.joinOpening(Bar.edgeName(root.barConfig.location), atStart, from, root.isVertical ? surface.width : surface.height, atStart ? surface.joinShown : surface.joinShownEnd, span);
    const at = root.isVertical ? origin.x : origin.y;
    // (its fillet at the far end of its cover: the stretch's end from the
    // near side, its start from the far one)
    const fillet = atStart ? surface.joinFillet : surface.joinFilletEnd;
    const far = root.barConfig.right || root.barConfig.bottom;
    return SurfaceContext.opening(opening.start - at, opening.end - at, far ? fillet : 0, far ? 0 : fillet);
  }

  // Each end merging into a pill bar it makes way for (CornerMerge)
  CornerMerge {
    bar: root
    atStart: true
  }
  CornerMerge {
    bar: root
    atStart: false
  }

  // The stretches as drawn (BarLayout.shownStretches): as their owners
  // send them, already paced (a pill grows out to carry a surface before
  // it slides out, and draws back after it; one joining from the
  // perpendicular edge follows it along). The pill itself follows its
  // sections as drawn (Section.drawnPos).
  readonly property var _shownStretches: BarLayout.shownStretches(root.pillRects, root._stretchList, root.length)
  FrameNudge {
    id: repaint
  }

  readonly property var _groups: [leftGroup, leftCenterGroup, centerGroup, rightCenterGroup, rightGroup]
  // Per section, the model indices hidden so the minimum sizes fit
  readonly property var hidden: BarLayout.overflowHidden(root._groups.map(g => g.measures), root.length, root.endMargins, root.barConfig.spacing, root.barConfig.groupSpacing, root.barConfig.lockCenter)
  readonly property var slots: BarLayout.layoutSections(root._groups.map(g => g.preferredLength), root._groups.map(g => g.minimumLength), root.length, root.endMargins, root.barConfig.spacing, root.barConfig.lockCenter, centerGroup.layoutHang)
  // Bindings re-run on any module change; only signal real moves
  property string _slotsKey: ""
  onSlotsChanged: {
    const key = JSON.stringify(slots);
    if (key !== _slotsKey) {
      _slotsKey = key;
      root.layoutMoved();
    }
  }
  // Widgets and sections glide to a new layout (BarWidgetHost, Section),
  // so what's anchored to them (an open popout) is told again once
  // they've arrived
  function layoutMoved() {
    layoutUpdated();
    _settle.restart();
  }
  Timer {
    id: _settle
    interval: Appearance.animNormal
    onTriggered: root.layoutUpdated()
  }

  // A section's shown widgets; `configIndex` is each one's place in the
  // section's config, which hidden widgets leave out
  function widgetModel(widgetConfigArray) {
    return (widgetConfigArray || []).map((widgetConf, i) => ({
          "component": Paths.widgetUrl(widgetConf.type),
          "properties": widgetConf.properties || {},
          "layout": widgetConf.layout || {},
          "configIndex": i,
          "visible": widgetConf.visible !== false
        })).filter(widget => widget.visible);
  }

  // While the bar editor is on screen, what it shows of this bar (see
  // BarManager.live): the widgets hidden for want of room, by section, and
  // how the selected widget is sized
  readonly property var editorReport: BarManager.editing ? {
    "source": root.barConfig.sourceId,
    "screen": root.screen?.name ?? "",
    "hidden": root._groups.reduce((out, g) => Utils.withEntry(out, g.zone, g.crowdedOut), {}),
    "selected": root._groups.map(g => g.selectedMeasure).find(m => m !== null) ?? null
  } : null
  property string _reportedId: ""
  readonly property string _reportKey: JSON.stringify(root.editorReport)
  on_ReportKeyChanged: root._report()
  Component.onDestruction: BarManager.clearLive(root._reportedId, root.screen?.name ?? "")

  function _report() {
    const id = root.editorReport ? root.barConfig.id : "";
    if (root._reportedId !== "" && root._reportedId !== id)
      BarManager.clearLive(root._reportedId, root.screen?.name ?? "");
    root._reportedId = id;
    BarManager.setLive(id, root.editorReport);
  }

  // A section: the group sits inside its slot at `align` (0 = start,
  // 1 = end), which only matters once hidden modules leave it spare room.
  // Inline components can't see this file's ids, hence `bar`.
  component Section: WidgetGroup {
    id: section
    required property Item bar
    required property int slotIndex
    required align

    readonly property var slot: section.bar.slots[section.slotIndex]
    readonly property real mainPos: Math.round(section.slot.offset + (section.slot.extent - section.usedLength) * section.align)

    barConfig: section.bar.barConfig
    panel: section.bar.panel
    screen: section.bar.screen
    maxExtent: section.slot.extent
    hiddenIndices: section.bar.hidden[section.slotIndex]

    // crossStart in from the bar's outer edge (see Bar.enrichBarConfig)
    readonly property real crossPos: {
      const across = section.bar.isVertical ? section.bar.width : section.bar.height;
      const size = section.bar.isVertical ? width : height;
      const start = Math.round(section.barConfig.crossStart);
      const farSide = section.barConfig.right || section.barConfig.bottom;
      return farSide ? across - start - size : start;
    }

    // Where it's drawn along the bar, and how long: gliding to the layout's
    // (as its widgets do, BarWidgetHost), which pills follow. Off until
    // first placed, so a new bar doesn't slide its sections in.
    property real drawnPos: section.mainPos
    property real drawnLength: section.usedLength
    property bool _settled: false
    Component.onCompleted: Qt.callLater(() => section._settled = true)
    Glide on drawnPos {
      enabled: section._settled
    }
    Glide on drawnLength {
      enabled: section._settled
    }

    x: section.bar.isVertical ? section.crossPos : section.drawnPos
    y: section.bar.isVertical ? section.drawnPos : section.crossPos

    onAllocationUpdated: section.bar.layoutMoved()
  }

  // The shadow the bar's surface casts, evenly and only outside it, so
  // none shows through a translucent one. Cast from a black copy of the surface (its pieces each put one here),
  // as its own fill may be the blur window's.
  // Backed, the blur window casts it instead, from the same shapes
  // (BlurShape.shadow), with everything joined to them
  OutsideShadow {
    target: shadowShape
    hideTarget: true
    active: !root.backed
    look: root.barConfig
    // Not under the surfaces open on its pills or islands (where they
    // cover the far stroke, whether or not the pill stretches for them),
    // from the outer edge they stand on out, nor on the solid bars its
    // ends make way for (whose stroke a pill's fillet curves into)
    holes: [].concat(...root._openingHoles.map(h => h.rects)).concat([].concat(...root._flushEnds.map(f => f.holes)), root._endBarHole(true, root.solidStart ?? root.pillBarStart), root._endBarHole(false, root.solidEnd ?? root.pillBarEnd)).filter(hole => hole !== null)
    // ...and a joined surface's fillet (a pill's or popout's curving into
    // a solid bar's stroke) only as far as its curve, not the square it
    // sits in: past the curve the shadow runs on round it
    fillets: [].concat(...root._openingHoles.map(h => h.fillets))
  }
  readonly property var _openingHoles: root._openingList.map(o => root._shadowHoles(o))
  // Where an opening keeps the shadow off: `rects`, and the corners of the
  // fillets curving into it at its ends (OutsideShadow.fillets): there
  // only as far as their curve, the shadow running on round them
  function _shadowHoles(o) {
    const reach = root.barConfig.shadowSize * 2;
    const extent = root.barConfig.extent;
    const fs = o.startFillet ?? 0, fe = o.endFillet ?? 0;
    const start = o.start + fs, end = o.end - fe;
    const along = end - start;
    const deep = (root.isVertical ? root.width : root.height) - extent + reach;
    const near = root.barConfig.left || root.barConfig.top;
    // The inner edge across the bar
    const inner = near ? extent : (root.isVertical ? root.width : root.height) - extent;
    const rect = root.isVertical ? Qt.rect(near ? extent : -reach, start, deep, along) : Qt.rect(start, near ? extent : -reach, along, deep);
    // `from` along the bar; `atEnd`: the surface's wall is before it
    const fillet = (from, f, atEnd) => root.isVertical ? {
        "x": near ? inner : inner - f,
        "y": from,
        "radius": f,
        "left": near,
        "top": atEnd
      } : {
        "x": from,
        "y": near ? inner : inner - f,
        "radius": f,
        "left": atEnd,
        "top": near
      };
    return {
      "rects": along > 0 ? [rect] : [],
      "fillets": (fs > 0 ? [fillet(o.start, fs, false)] : []).concat(fe > 0 ? [fillet(o.end - fe, fe, true)] : [])
    };
  }
  // The pill and island ends squared for a surface whose wall runs on
  // from them past the inner edge, its shadow run on with it
  // (BarLayout.flushEnds)
  readonly property var _flushEnds: {
    const across = root.isVertical ? root.width : root.height;
    const near = root.barConfig.left || root.barConfig.top;
    const rect = a => root.isVertical ? Qt.rect(a.from, a.along, a.deep, a.length) : Qt.rect(a.along, a.from, a.length, a.deep);
    return BarLayout.flushEnds(root._stretchList, root.pillShapes, {
      "reach": root.barConfig.shadowSize * 2,
      "across": across,
      "inner": near ? root.barConfig.extent : across - root.barConfig.extent,
      "near": near
    }).map(e => ({
          "source": rect(e.source),
          "holes": e.holes.map(rect)
        }));
  }
  // The bar an end makes way for (`other`, its container: a solid bar, or
  // a pill bar its end pill merges into), from its inner edge on: a shadow
  // falling along this bar, or spread round a pill's fillet, would land on
  // its stroke where this bar's window overlaps it
  function _endBarHole(atStart, other) {
    const origin = other?.blurOrigin ?? null;
    if (!origin || !root.blurOrigin)
      return null;
    const reach = root.barConfig.shadowSize * 2;
    const at = root.isVertical ? origin.y - root.blurOrigin.y : origin.x - root.blurOrigin.x;
    const size = root.isVertical ? other.height : other.width;
    const extent = other.barConfig.extent;
    const from = atStart ? -reach : at + size - extent;
    const to = atStart ? at + extent : root.length + reach;
    const across = (root.isVertical ? root.width : root.height) + reach * 2;
    return root.isVertical ? Qt.rect(-reach, from, across, to - from) : Qt.rect(from, -reach, to - from, across);
  }

  Item {
    id: shadowShape
    anchors.fill: parent
    visible: !root.backed

    Repeater {
      model: root._flushEnds.length

      Rectangle {
        required property int index
        readonly property rect area: root._flushEnds[index]?.source ?? Qt.rect(0, 0, 0, 0)
        x: area.x
        y: area.y
        width: area.width
        height: area.height
        color: "black"
      }
    }
  }

  // The blur window draws the bar's fill (BlurManager), once
  // its window is placed on screen: where its shapes are, the container's
  // top-left on screen (the bar editor's preview has none, and fills itself)
  readonly property var blurOrigin: root.panel?.screenOrigin ? Qt.point(root.panel.screenOrigin.x + (root.parent?.x ?? 0), root.panel.screenOrigin.y + (root.parent?.y ?? 0)) : null
  readonly property string blurScreen: root.panel?.screen?.name ?? ""
  readonly property bool backed: BlurManager.backsOn(root.blurScreen, false) && root.blurOrigin !== null

  // What the bar paints under its widgets: its background, inner stroke
  // and pills, which the shadow follows
  Item {
    id: surface
    anchors.fill: parent

    Rectangle {
      id: solidFill
      anchors.fill: parent
      visible: root.barConfig.solid
      color: root.backed ? "transparent" : BlurManager.fillOn(Theme.background, root.blurScreen)

      Rectangle {
        parent: shadowShape
        anchors.fill: parent
        visible: solidFill.visible
        color: "black"
      }

      BlurShape {
        source: solidFill
        kind: "rect"
        screen: root.blurScreen
        x: root.blurOrigin?.x ?? 0
        y: root.blurOrigin?.y ?? 0
        shown: root.backed && solidFill.visible
        shadow: root.barConfig
      }
    }

    // With the border off nothing else draws a solid bar's inner stroke,
    // left open under the surfaces joined to it (a popout, a pill bar's
    // end pill): opaque or not, as they're separate windows whose stacking
    // isn't the bar's to choose, and the bar's fill shows there as theirs
    Repeater {
      model: root.barConfig.innerStroke ? root._strokePieces.length : 0

      Rectangle {
        required property int index
        readonly property var piece: root._strokePieces[index] ?? {
          "start": 0,
          "end": 0
        }
        color: Theme.foreground
        width: root.isVertical ? Appearance.borderWidth : piece.end - piece.start
        height: root.isVertical ? piece.end - piece.start : Appearance.borderWidth
        x: root.isVertical ? (root.barConfig.left ? root.width - width : 0) : piece.start
        y: root.isVertical ? piece.start : (root.barConfig.top ? root.height - height : 0)
      }
    }

    // Islands: rounded boxes in from the edge, an inner corner squared
    // where a popout runs flush into that end. Modelled by count, as pills.
    Repeater {
      model: root.islands ? root.pillShapes.length : 0

      Rectangle {
        id: island
        required property int index
        readonly property var rect: root.pillShapes[index] ?? {
          "start": 0,
          "length": 0,
          "squareStart": false,
          "squareEnd": false
        }
        readonly property real depth: root.barConfig.extent - root.barConfig.islandStart
        readonly property real across: root.barConfig.right || root.barConfig.bottom ? (root.isVertical ? root.width : root.height) - root.barConfig.islandStart - depth : root.barConfig.islandStart
        readonly property real corner: Appearance.borderRadius
        // The inner side's corners at the bar's start and end
        property real startInner: rect.squareStart ? 0 : corner
        property real endInner: rect.squareEnd ? 0 : corner

        x: root.isVertical ? across : rect.start
        y: root.isVertical ? rect.start : across
        width: root.isVertical ? depth : rect.length
        height: root.isVertical ? rect.length : depth
        color: root.backed ? "transparent" : BlurManager.fillOn(Theme.background, root.blurScreen)
        // The stroke drawn by the one below, left open where a popout joins
        border.width: 0

        HoledItem {
          anchors.fill: parent
          keepLayer: Appearance.translucent
          // On the inner side, the stroke and its fringe under each opening
          holes: root._openingList.map(o => {
            const along = root.isVertical ? island.y : island.x;
            const start = Math.max(0, o.start - along);
            const end = Math.min(root.isVertical ? island.height : island.width, o.end - along);
            if (end <= start)
              return null;
            const row = Appearance.borderWidth + 1;
            const across = root.barConfig.left || root.barConfig.top ? (root.isVertical ? island.width : island.height) - row : 0;
            return root.isVertical ? Qt.rect(across, start, row, end - start) : Qt.rect(start, across, end - start, row);
          }).filter(hole => hole !== null)

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.foreground
            border.width: Appearance.borderWidth
            topLeftRadius: island.topLeftRadius
            topRightRadius: island.topRightRadius
            bottomLeftRadius: island.bottomLeftRadius
            bottomRightRadius: island.bottomRightRadius
          }
        }

        // Its shape, for the bar's shadow
        Rectangle {
          parent: shadowShape
          x: island.x
          y: island.y
          width: island.width
          height: island.height
          topLeftRadius: island.topLeftRadius
          topRightRadius: island.topRightRadius
          bottomLeftRadius: island.bottomLeftRadius
          bottomRightRadius: island.bottomRightRadius
          color: "black"
        }

        BlurShape {
          source: island
          kind: "rect"
          screen: root.blurScreen
          x: (root.blurOrigin?.x ?? 0) + island.x
          y: (root.blurOrigin?.y ?? 0) + island.y
          shown: root.backed
          shadow: root.barConfig
        }
        // Inner side: bottom on a top bar, right on a left one, and so on
        topLeftRadius: root.barConfig.bottom || root.barConfig.right ? startInner : corner
        topRightRadius: root.barConfig.bottom ? endInner : root.barConfig.left ? startInner : corner
        bottomLeftRadius: root.barConfig.top ? startInner : root.barConfig.right ? endInner : corner
        bottomRightRadius: root.barConfig.top || root.barConfig.left ? endInner : corner

        Glide on startInner {}
        Glide on endInner {}
      }
    }

    // Pills: each grows out of the bar's outer edge (the border, or the
    // screen edge with the border off) like a popout does, covering the
    // border's stroke where it joins. Modelled by count, so a clock changing
    // width moves its pill without rebuilding it.
    Repeater {
      model: root.pills ? root.pillShapes.length : 0

      AttachedSurface {
        id: pill
        required property int index
        // Stretched to carry the surfaces open on it, as islands are
        readonly property var span: root.pillShapes[index] ?? {
          "start": 0,
          "length": 0,
          "joinStart": false,
          "joinEnd": false,
          "squareStart": false,
          "squareEnd": false
        }
        readonly property real alongStart: span.start - startMargin
        // Depth reached from the outer edge; the surface's far half-gap is empty
        readonly property real depthBox: Math.max(0, root.barConfig.pillDepth - connectorGap / 2)
        boxStart: connectorGap / 2

        edge: root.barConfig.location
        active: true
        connectorGap: root.pillConnector
        boxWidth: root.isVertical ? depthBox : span.length
        boxHeight: root.isVertical ? span.length : depthBox
        joinStart: span.joinStart
        joinEnd: span.joinEnd
        // Without the border, pills grow straight out of the screen edges,
        // and an end pill runs straight off a bare one, or curves into a
        // solid bar's stroke there as into the border's (BarEnds)
        straight: !Appearance.screenBorder
        straightJoinStart: root.ends.start.straight || (index === 0 && root._endReach.straightStart)
        straightJoinEnd: root.ends.end.straight || (index === root.pillShapes.length - 1 && root._endReach.straightEnd)
        // Square where a popout runs flush into it
        startCornerRadius: span.squareStart ? 0 : cornerRadius
        endCornerRadius: span.squareEnd ? 0 : cornerRadius

        Glide on startCornerRadius {}
        Glide on endCornerRadius {}

        width: implicitWidth
        height: implicitHeight
        x: root.isVertical ? (root.barConfig.right ? root.width - width : 0) : alongStart
        y: root.isVertical ? alongStart : (root.barConfig.bottom ? root.height - height : 0)
        backed: root.backed
        opaque: BlurManager.opaqueOn(root.blurScreen)
        // Grown out of the border's stroke, which it covers there...
        readonly property real _along: root.isVertical ? pill.y : pill.x
        BorderOpening {
          opening: root.borderOpening(pill._along + pill.coverStart, pill._along + pill.coverStart + pill.coverLength)
        }
        // ...and, joined to a perpendicular edge, that edge's
        // (not a pill bar's it merges into: its pill covers that, CornerMerge)
        BorderOpening {
          opening: pill.joinStart && root.ends.start.kind !== "pillBar" ? root.joinOpening(pill, true) : null
        }
        BorderOpening {
          opening: pill.joinEnd && root.ends.end.kind !== "pillBar" ? root.joinOpening(pill, false) : null
        }
        // ...or, with the border off, a solid bar's own stroke there
        PillStretch {
          owner: "solidJoin:" + root.barConfig.id + ":" + pill.index + ":start"
          container: pill.joinStart ? root.solidStart : null
          opening: root._solidJoinOf(pill, true, container)
        }
        PillStretch {
          owner: "solidJoin:" + root.barConfig.id + ":" + pill.index + ":end"
          container: pill.joinEnd ? root.solidEnd : null
          opening: root._solidJoinOf(pill, false, container)
        }
        // The far stroke and its fringe under each opening (in the pill's
        // coordinates), and a joined end's fillet where one reaches it: a
        // surface joined to the same edge runs on down it, over the fillet
        strokeHoles: [].concat(...root._openingList.map(o => {
          const along = root.isVertical ? pill.y : pill.x;
          const start = Math.max(o.start, along);
          const end = Math.min(o.end, along + pill.alongLength);
          if (end <= start)
            return [];
          const R = pill.filletRadius, h = pill.half, L = pill.alongLength;
          const joins = [];
          if (pill.joinStart && start <= along + 1)
            joins.push(pill._rectFrom(0, pill.farV - h - 1, h + R + 1, R + h + 2));
          if (pill.joinEnd && end >= along + L - 1)
            joins.push(pill._rectFrom(L - h - R - 1, pill.farV - h - 1, h + R + 1, R + h + 2));
          return [pill._farHole(start, end, o.keepFill && !Appearance.translucent ? "outer" : "both")].concat(joins);
        }))
        // The stroke, with its anti-aliased fringe a pixel either side
        // (`fringe` "both"), outside it alone ("outer": the fill inside
        // stays), or that fringe's row inside the pill alone ("inner")
        function _farHole(start, end, fringe) {
          const row = Appearance.borderWidth + 2;
          const foot = root.barConfig.pillDepth;
          const far = root.isVertical ? root.width : root.height;
          const near = root.barConfig.left || root.barConfig.top;
          const from = near ? foot - row + 1 : far - foot - 1;
          const across = fringe === "inner" ? (near ? from : from + row - 1) : fringe === "outer" && near ? from + 1 : from;
          const depth = fringe === "inner" ? 1 : fringe === "outer" ? row - 1 : row;
          const r = root.isVertical ? Qt.rect(across, start, depth, end - start) : Qt.rect(start, across, end - start, depth);
          return Qt.rect(r.x - pill.x, r.y - pill.y, r.width, r.height);
        }
        // Under a `keepFill` opening the stroke's soft edge inside the pill
        // is painted over while surfaces are opaque (the surface joining
        // end-on covers only the stroke); translucent, a second coat would
        // show as a line
        Repeater {
          model: Appearance.translucent ? [] : root._openingList.filter(o => o.keepFill ?? false)
          Rectangle {
            required property var modelData
            readonly property real _along: root.isVertical ? pill.y : pill.x
            readonly property real _start: Math.max(modelData.start, _along)
            readonly property real _end: Math.min(modelData.end, _along + pill.alongLength)
            readonly property rect area: pill._farHole(_start, _end, "inner")
            visible: _end > _start
            // (in the content box, where a surface's children go)
            x: area.x - pill.boxRect.x
            y: area.y - pill.boxRect.y
            width: area.width
            height: area.height
            color: BlurManager.fillOn(Theme.background, root.blurScreen)
          }
        }

        // Its shape, for the bar's shadow
        AttachedSurfaceCopy {
          parent: shadowShape
          source: pill
          x: pill.x
          y: pill.y
          fillColor: "black"
          mirrorStroke: "black"
        }
        // ...and where it runs on past its outline: off a bare screen
        // edge, into what it joins straight (AttachedSurface.shadowRunOn)
        readonly property var _runOnShadow: pill.shadowRunOn(Math.ceil(root.barConfig.shadowSize * 1.25))
        Repeater {
          model: pill._runOnShadow.length

          Rectangle {
            required property int index
            readonly property rect area: pill._runOnShadow[index] ?? Qt.rect(0, 0, 0, 0)
            parent: shadowShape
            x: pill.x + area.x
            y: pill.y + area.y
            width: area.width
            height: area.height
            color: "black"
          }
        }

        BlurShape {
          source: pill
          screen: root.blurScreen
          x: (root.blurOrigin?.x ?? 0) + pill.x
          y: (root.blurOrigin?.y ?? 0) + pill.y
          shown: root.backed
          shadow: root.barConfig
        }
      }
    }
  }

  // A line along the bar's inner or outer edge, from its color fading
  // into another along the bar. Inline components can't see this file's
  // ids, hence `bar`.
  component AccentLine: Rectangle {
    id: line
    required property Item bar
    // Along the bar, and in from its outer edge
    required property real start
    required property real length
    required property real inset

    readonly property bool vertical: bar.isVertical
    readonly property real thickness: bar.barConfig.accentLineWidth
    readonly property bool far: bar.barConfig.right || bar.barConfig.bottom
    readonly property real across: far ? (vertical ? bar.width : bar.height) - inset - thickness : inset
    readonly property color from: Theme.resolveColor(bar.barConfig.accentLineColor)

    x: vertical ? across : start
    y: vertical ? start : across
    width: vertical ? thickness : length
    height: vertical ? length : thickness
    gradient: Gradient {
      orientation: line.vertical ? Gradient.Vertical : Gradient.Horizontal
      GradientStop {
        position: 0
        color: line.from
      }
      GradientStop {
        position: 1
        color: line.bar.barConfig.accentLineFade ? Theme.resolveColor(line.bar.barConfig.accentLineFade) : line.from
      }
    }
  }

  // How far in from the outer edge the accent line sits: inside whatever
  // stroke is there (the border strip's or the bar's own on a solid bar's
  // inner edge, the border's under a floating bar's outer edge)
  readonly property real _accentInset: {
    const width = root.barConfig.accentLineWidth;
    if (root.barConfig.accentLine === "outer") {
      if (root.islands)
        return root.barConfig.islandStart + Appearance.borderWidth;
      return root.pills ? root.barConfig.overlap : root.barConfig.insideBorder ? Appearance.borderWidth : 0;
    }
    if (root.pills)
      return root.barConfig.pillDepth - Appearance.borderWidth - width;
    return root.barConfig.extent - width - (root.barConfig.solid || root.islands ? Appearance.borderWidth : 0);
  }

  // Along a plain bar: its whole length, or clear of the border's sides
  // inside the border and of a bar it makes way for
  AccentLine {
    visible: root.barConfig.accentLine !== "none" && !root.pills && !root.islands
    bar: root
    start: root.barConfig.insideBorder || root.ends.start.held ? root.endMargins[0] : 0
    length: root.length - start - (root.barConfig.insideBorder || root.ends.end.held ? root.endMargins[1] : 0)
    inset: root._accentInset
  }

  // Along each pill, clear of its rounded corners on the inner side
  Repeater {
    model: root.barConfig.accentLine !== "none" && (root.pills || root.islands) ? root.pillRects.length : 0

    AccentLine {
      required property int index
      readonly property var rect: root.pillRects[index] ?? {
        "start": 0,
        "length": 0
      }
      // Pills only round their inner side; islands both
      readonly property real corner: root.islands || root.barConfig.accentLine === "inner" ? Appearance.borderRadius : 0

      bar: root
      start: rect.start + (rect.joinStart ? 0 : corner)
      length: Math.max(0, rect.length - (rect.joinStart ? 0 : corner) - (rect.joinEnd ? 0 : corner))
      inset: root._accentInset
    }
  }

  Section {
    id: leftGroup
    bar: root
    slotIndex: 0
    zone: "left"
    align: 0
    widgets: root.widgetModel(root.barConfig.widgets?.left)
  }

  Section {
    id: leftCenterGroup
    bar: root
    slotIndex: 1
    zone: "leftCenter"
    align: 1
    widgets: root.widgetModel(root.barConfig.widgets?.leftCenter)
  }

  Section {
    id: centerGroup
    bar: root
    slotIndex: 2
    zone: "center"
    align: 0.5
    widgets: root.widgetModel(root.barConfig.widgets?.center)
  }

  Section {
    id: rightCenterGroup
    bar: root
    slotIndex: 3
    zone: "rightCenter"
    align: 0
    widgets: root.widgetModel(root.barConfig.widgets?.rightCenter)
  }

  Section {
    id: rightGroup
    bar: root
    slotIndex: 4
    zone: "right"
    align: 1
    widgets: root.widgetModel(root.barConfig.widgets?.right)
  }
}
