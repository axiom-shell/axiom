pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout
import qs.components.reusable

// Lays out a bar's three widget sections along its main axis in one pass,
// so they can never overlap: `left`/`right` hug the ends, `center` stays
// centered on the bar. When the
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
  // Any of it in view (BarPanel.inView; a container with no panel is)
  readonly property bool _onScreen: root.panel?.inView ?? true

  readonly property bool isVertical: barConfig.vertical
  readonly property real length: isVertical ? height : width

  // The surface layer paints the bar
  color: "transparent"

  readonly property bool pills: barConfig.pills
  // A floating bar: islands held off the edge, read like pills by the
  // popouts (pillRects), but drawn on their own (as boxes, from pillShapes)
  readonly property bool islands: barConfig.island
  // What each end meets (BarEnds): the frame, or a bar it makes way for
  readonly property var ends: barConfig.ends
  // How far in from an end islands may reach: where windows start there
  // (BarEnds.windowInset: the frame or the bars it makes way for, and the
  // compositor's gaps_out on that side), or held clear of a bar it makes
  // way for, as a surface held off an edge
  function _islandInset(end, atStart) {
    return end.held ? end.over + end.gap : BarEnds.windowInset(root.barConfig, end, atStart, ScreenEdgeManager.endsOptions);
  }
  // Where islands may reach along the bar, from its start
  readonly property real islandFrom: root._islandInset(root.ends.start, true)
  readonly property real islandEnd: root.length - root._islandInset(root.ends.end, false)
  // Fillet room each side of a pill, as for popouts (AttachedSurface)
  readonly property int pillConnector: Appearance.connectorGap
  // A pill's fillets off the bar's outer edge and its far corners: at a
  // high radius both don't fit across its depth (from the stroke it hangs
  // off to its far stroke), so they scale down by the same ratio until
  // they meet as one curve (SurfaceOutline.fitRadii). Joined ends keep
  // the full radius.
  readonly property var pillRadii: SurfaceOutline.fitRadii(root.pillReach - Appearance.borderWidth, Appearance.borderRadius, Math.max(0, Appearance.borderRadius - Appearance.borderWidth / 2))
  // A pill's depth from the stroke it hangs off (the window's outer edge,
  // or past the frame a pill bar on the border reaches back over:
  // stripCover)
  readonly property real pillReach: Math.max(0, root.barConfig.pillDepth - root.barConfig.stripCover)
  // Kept clear at each end. A solid or pill bar, part of the frame, has
  // its widgets the screen margin in (BarEnds.endInset): an end pill fills
  // the corner, joining the frame squarely as a solid bar does. An
  // island's widgets sit inside its stroke and padding. A transparent
  // bar's, not part of the frame, line up with the windows
  // (BarEnds.windowInset). At an end held clear of another bar, a pill's
  // free end and its fillet stay past the held gap, and a plain bar's
  // widgets at least its padding past that bar.
  function _endMargin(end, atStart) {
    if (root.islands)
      return root._islandInset(end, atStart) + root.barConfig.islandGap;
    if (end.held) {
      if (!root.pills)
        return end.over + Math.max(end.gap, root.barConfig.edgePadding);
      const fillet = Appearance.screenBorder ? EdgeAttach.filletMargin(Appearance.borderWidth, root.pillRadii.fillet) : 0;
      return end.over + end.gap + fillet + root.barConfig.pillGap;
    }
    if (root.pills || root.barConfig.solid)
      return BarEnds.endInset(root.barConfig, end, ScreenEdgeManager.endsOptions);
    return BarEnds.windowInset(root.barConfig, end, atStart, ScreenEdgeManager.endsOptions);
  }
  readonly property var endMargins: [root._endMargin(root.ends.start, true), root._endMargin(root.ends.end, false)]
  // How near a pill's end may come to an unheld end of the bar and still
  // run on to it and join it: its widgets' inset there less the pill gap
  // (on the stroke it covers, at least)
  readonly property real _pillJoinReach: Math.max(root.barConfig.overlap, ...[root.ends.start, root.ends.end].map((end, i) => end.held ? 0 : root.endMargins[i] - root.barConfig.pillGap)) + 0.5

  // Tabs (the look's shape tab) reach out to the outer edge of what the
  // widgets sit on, this far in from the window's outer edge
  // (BarEnds.tabEdge), an end by an island's or the rounded border's
  // corner taking its curve (BarEnds.tabBounds)
  readonly property bool tabs: root.barConfig.look.shape.name === "tab"
  readonly property real tabEdge: BarEnds.tabEdge(root.barConfig, Appearance.borderWidth)
  readonly property var tabBounds: root.tabs ? BarEnds.tabBounds(root.barConfig, root.length, root.islands ? root.pillShapes : [], {
    "border": Appearance.screenBorder,
    "borderWidth": Appearance.borderWidth,
    "radius": Appearance.borderRadius
  }) : []

  // One { start, length, joinStart, joinEnd } per pill along the bar: one
  // per joined group (BarLayout.joinGroups, pillRects): grown by the pill
  // gap, those reaching an end stretched onto it and joining it. On a
  // floating bar, its islands (BarLayout.islandRects): one along it, or
  // one per joined group. Pills asked to reach an end run there, or a
  // stub grows there for them (BarLayout.endReaches, setRequest).
  readonly property var pillRects: {
    if (islands)
      return BarLayout.islandRects(root.joinedGroups, root.barConfig.islandGap, root.islandFrom, root.islandEnd, !root.barConfig.islandPills);
    return root.pills ? root._endReach.rects : [];
  }
  readonly property var _endReach: BarLayout.endReaches(root.groupPills, root._endReachList, root.length, root.barConfig.joinGap, root.pillConnector)
  // The pills of its own groups, before any end reach or stretch. A free
  // end sits the pill gap out from its widgets; an end that would reach
  // the frame (the end sections, which sit endMargin in) joins it, the
  // frame standing in for the gap; not a bar it makes way for, which has
  // no stroke to join (BarEnds): within the stroke it covers there, or on
  // a bare edge, the room the end widgets keep past the pill's gap. Pills
  // too close for the fillets between them draw as one.
  readonly property var groupPills: root.pills ? BarLayout.pillRects(root.joinedGroups, root.barConfig.pillGap, 2 * root.pillConnector, root._pillJoinReach, root.length, [root.ends.start.joinable, root.ends.end.joinable]) : []

  // Each section's groups of widgets as drawn, along the bar ({ start,
  // end, section }). Dividers at a section's end facing another section
  // stand in the gap between them, outside its group (BarLayout.edgeHang);
  // at the first and last sections showing, they stay in it, as padding.
  readonly property var groupSpans: {
    const shown = root._groups.map((g, s) => ({
          "g": g,
          "s": s
        })).filter(e => e.g.drawnLength > 0.5 && e.g.drawnGroups.length > 0).sort((a, b) => a.g.drawnPos - b.g.drawnPos);
    return [].concat(...shown.map((e, i) => {
      const groups = e.g.drawnGroups;
      return groups.map((group, k) => ({
            "start": e.g.drawnPos + group.start + (i > 0 && k === 0 ? e.g.drawnHang.lead : 0),
            "end": e.g.drawnPos + group.end - (i < shown.length - 1 && k === groups.length - 1 ? e.g.drawnHang.trail : 0),
            "section": e.s
          }));
    }));
  }
  // The groups joined where they're at most joinGap apart: one pill or one
  // island each
  readonly property var joinedGroups: BarLayout.joinGroups(root.groupSpans, root.barConfig.joinGap)
  // Which section boundaries join: where a side's spacer pushed a widget
  // against the next section (BarLayout.sectionJoins). Decided from the
  // config's shape, never from where things land, so a crowded side
  // never joins and the center never moves for it. A joined boundary
  // keeps the gap between a section's widgets (`groupSpacing`) instead
  // of the gap between sections.
  readonly property var _joins: BarLayout.sectionJoins(root._groups.map(g => g.joinMeasures), root.barConfig.lockCenter)
  readonly property var _sectionGaps: BarLayout.boundaryGaps(root._joins, root.barConfig.widgetGap, root.barConfig.groupSpacing)
  // The joined boundaries, as [before, after] section pairs
  readonly property var _joinedPairs: [[0, 1, root._joins.leftCenter], [1, 2, root._joins.centerRight], [0, 2, root._joins.leftRight]].filter(pair => pair[2])
  // Per section, whether its start and end join the sections beside it,
  // and whether its run carries on there (`chainStart`/`chainEnd`: both
  // widgets facing it have backgrounds: one merged background, one
  // powerline chain) (WidgetGroup's joinStart, joinEnd, chainStart,
  // chainEnd). From content alone: the insets follow it.
  readonly property var sectionJoins: {
    const joins = root._groups.map(() => ({
          "start": false,
          "end": false,
          "chainStart": false,
          "chainEnd": false
        }));
    root._joinedPairs.forEach(([a, b]) => {
      const chain = root._groups[a].endsInRun && root._groups[b].startsInRun;
      joins[a].end = true;
      joins[a].chainEnd = chain;
      joins[b].start = true;
      joins[b].chainStart = chain;
    });
    return joins;
  }
  // Per section, how far past its last group the one it joins after it
  // starts, as drawn (WidgetGroup's joinEndReach)
  readonly property var sectionReaches: {
    const reaches = root._groups.map(() => 0);
    root._joinedPairs.forEach(([a, b]) => {
      const before = root.groupSpans.filter(span => span.section === a).pop();
      const after = root.groupSpans.find(span => span.section === b);
      reaches[a] = before && after ? Math.max(0, after.start - before.end) : 0;
    });
    return reaches;
  }

  // The pills (or islands) as drawn: stretched to carry the surfaces open
  // on them, and joining any they then reach, while those are open
  readonly property var pillShapes: BarLayout.stretchIslands(root.pillRects, root._shownStretches, root.barConfig.joinGap)

  // What the surfaces standing on or joining this bar ask of it, by owner
  // (PillStretch: a bar popout, an edge popout, a dock, a submenu, a pill
  // bar merging into this one's corner), each { stretch, opening,
  // endReach }, drawn as sent: each owner sets the pace it changes at.
  // - stretch: a pill stretched past its ends to carry a surface's fillets
  //   ({ index, start, end, squareStart, squareEnd, joinStart, joinEnd },
  //   EdgeAttach.place's stretch). pillRects stays unstretched.
  // - opening: where a surface covers a pill's (or island's) inner stroke,
  //   { start, end } along the bar. The stroke is left open there (the
  //   copies cut it, opaque or not).
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
    return Utils.deepEqual(map[owner] ?? null, value ?? null) ? null : Utils.withEntry(map, owner, value || undefined);
  }
  // Sets (or with null clears) `owner`'s request
  function setRequest(owner, request) {
    // Each map is read right before it is written: a push made while another
    // is written (a tracking stretch re-sent as an end reach reshapes
    // pillRects) is never overwritten by a map read before it
    const stretches = root._withEntry(root._stretches, owner, request?.stretch);
    if (stretches)
      root._stretches = stretches;
    const endReaches = root._withEntry(root._endReaches, owner, request?.endReach);
    if (endReaches)
      root._endReaches = endReaches;
    const openings = root._withEntry(root._openings, owner, request?.opening);
    if (openings)
      root._openings = openings;
  }

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
  // the border leaves its stroke open under the surface (the backing window's
  // copies cut it): a pill, a popout merged into the bar or on a solid
  // bar's inner edge. Null with the border off, on a bar the border's stroke
  // isn't on (stacked inside another, BarEnds' offBorder), until the
  // bar's place on screen is known, or once an auto-hiding bar has slid
  // out of view (BarPanel.inView), the stroke whole again. On whole
  // pixels (SurfaceContext.opening), as StrokeOpening._border.
  function borderOpening(from, to) {
    if (!Appearance.screenBorder || root.barConfig.offBorder || !root.blurOrigin || to <= from || !root._onScreen)
      return null;
    const at = root.isVertical ? root.blurOrigin.y : root.blurOrigin.x;
    const o = SurfaceContext.openingOrNull(at + from, at + to);
    return o ? {
      "screen": root.blurScreen,
      "edge": ScreenEdge.name(root.barConfig.location),
      "start": o.start,
      "end": o.end
    } : null;
  }
  // The same for a surface's joined end (`surface`, an AttachedSurface in
  // this item, joined at its start or end): it covers the perpendicular
  // edge's stroke, from the bar's outer edge to its join's fillet
  function joinOpening(surface, atStart) {
    if (!Appearance.screenBorder || !root.blurOrigin || !root._onScreen)
      return null;
    const s = root._joinStretch(surface, atStart);
    const o = SurfaceContext.openingOrNull(s.start, s.end, s.startFillet ?? 0, s.endFillet ?? 0);
    return o ? Object.assign({
      "screen": root.blurScreen
    }, s, o) : null;
  }
  // The stretch of the perpendicular edge a surface's joined end covers,
  // on screen (EdgeAttach.joinOpening, with its fillet), for the border's
  // opening and a solid bar's; needs `blurOrigin`
  function _joinStretch(surface, atStart) {
    const from = root.isVertical ? root.blurOrigin.x + surface.x : root.blurOrigin.y + surface.y;
    const span = (root.isVertical ? root.panel?.screen?.width : root.panel?.screen?.height) ?? 0;
    return EdgeAttach.joinOpening(ScreenEdge.name(root.barConfig.location), atStart, from, root.isVertical ? surface.width : surface.height, atStart ? surface.joinShown : surface.joinShownEnd, span, atStart ? surface.joinFillet : surface.joinFilletEnd);
  }

  // The bar an end makes way for, as its container, when it's of `kind`
  // (BarEnds' end kind) and showing: a solid bar with the border off
  // ("solidBar"), whose inner stroke a pill joined there curves into, or a
  // pill bar ("pillBar"), whose end pill this bar's end pill merges into
  // (CornerMerge); the one the end meets (`barId`) among the bars stacked
  // on that edge
  function barAt(atStart, kind) {
    const end = atStart ? root.ends.start : root.ends.end;
    if (end.kind !== kind)
      return null;
    const panel = ScreenEdgeManager.barOn(root.blurScreen, root.isVertical ? (atStart ? ScreenEdge.Top : ScreenEdge.Bottom) : (atStart ? ScreenEdge.Left : ScreenEdge.Right), end.barId);
    return panel?.present ? panel.container : null;
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
    if (!origin || !root.blurOrigin || !root._onScreen)
      return null;
    const opening = root._joinStretch(surface, atStart);
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

  readonly property var _groups: [leftGroup, centerGroup, rightGroup]
  // Per section, the model indices hidden so the minimum sizes fit
  // (as a string key and back: `hiddenIndices` follows only a change of who
  // is hidden, not each new size, as BarRuns.flagsKey)
  readonly property string _hiddenKey: JSON.stringify(BarLayout.overflowHidden(root._groups.map(g => g.measures), root.length, root.endMargins, root._sectionGaps, root.barConfig.groupSpacing, root.barConfig.lockCenter))
  readonly property var hidden: JSON.parse(root._hiddenKey)
  // Each section's room along the bar; a side with spacers stretches to
  // the center (BarLayout.layoutSections)
  readonly property var slots: BarLayout.layoutSections(root._groups.map(g => g.preferredLength), root._groups.map(g => g.minimumLength), root.length, root.endMargins, root._sectionGaps, root.barConfig.lockCenter, centerGroup.layoutHang, root._groups.map(g => g.fillCount), centerGroup.centerParts)

  // A section's shown widgets; `configIndex` is each one's place in the
  // section's config, which hidden widgets leave out. A widget drawn one
  // box per item is one entry per item (BarBoxes.expand), each with its
  // `box`, all with its configIndex.
  function widgetModel(widgetConfigArray) {
    return BarBoxes.sectionModel(widgetConfigArray, BarsConfig.boxItems);
  }

  // While the bar editor is on screen, what it shows of this bar (see
  // BarManager.live): the widgets hidden for want of room, by section;
  // how the selected widget is sized; and per section (`sections`, by
  // name) how long its widgets want to be, none hidden (`used`), and the
  // most room it could have, the others as they are (`room`,
  // BarLayout.sectionRooms)
  readonly property var editorReport: BarManager.editing ? {
    "source": root.barConfig.sourceId,
    "screen": root.screen?.name ?? "",
    "hidden": root._groups.reduce((out, g) => Utils.withEntry(out, g.zone, g.crowdedOut), {}),
    "selected": root._groups.map(g => g.selectedMeasure).find(m => m !== null) ?? null,
    "sections": root._groups.reduce((out, g, s) => Utils.withEntry(out, g.zone, {
        "used": Math.round(g.wantedLength),
        "room": Math.round(root._sectionRooms[s])
      }), {})
  } : null
  readonly property var _sectionRooms: BarLayout.sectionRooms(root._groups.map(g => g.preferredLength), root.length, root.endMargins, root._sectionGaps, root.barConfig.lockCenter, centerGroup.layoutHang, centerGroup.centerParts)
  property string _reportedId: ""
  readonly property string _reportKey: JSON.stringify(root.editorReport)
  on_ReportKeyChanged: root._report()
  // A bar made while the editor is open starts with its report: a change
  // handler never sees a first value
  Component.onCompleted: if (root.editorReport)
    root._report()
  Component.onDestruction: BarManager.clearLive(root._reportedId, root.screen?.name ?? "")

  function _report() {
    const id = root.editorReport ? root.barConfig.id : "";
    if (root._reportedId !== "" && root._reportedId !== id)
      BarManager.clearLive(root._reportedId, root.screen?.name ?? "");
    root._reportedId = id;
    BarManager.setLive(id, root.editorReport);
  }

  // A section (`slotIndex` in BarsConfig.sectionNames: left, center,
  // right): the group sits inside its slot at its `align` (start, middle,
  // end), which only matters once hidden modules leave it spare room.
  // Inline components can't see this file's ids, hence `bar`.
  component Section: WidgetGroup {
    id: section
    required property Item bar
    required property int slotIndex

    readonly property var slot: section.bar.slots[section.slotIndex]
    zone: BarsConfig.sectionNames[section.slotIndex]
    align: section.slotIndex / 2
    // The widgets as a string key and back: they follow only a change of
    // content, not each new config object of equal content (as _hiddenKey)
    readonly property string _widgetsKey: JSON.stringify(section.bar.widgetModel(section.bar.barConfig.widgets?.[section.zone]))
    widgets: JSON.parse(section._widgetsKey)
    // A powerline segment reaches back under the one before it, across
    // sections too: the earlier section is drawn over the later
    z: 2 - section.slotIndex
    // A locked center's spacers take the room the layout gives them on
    // each side of its centered group; otherwise they share its room
    // equally
    fillWeights: section.slotIndex === 1 && section.slot.leadShare !== undefined ? BarLayout.centerFillWeights(section.measures, section.slot.leadShare, section.slot.tailShare) : undefined
    joinStart: section.bar.sectionJoins[section.slotIndex].start
    joinEnd: section.bar.sectionJoins[section.slotIndex].end
    chainStart: section.bar.sectionJoins[section.slotIndex].chainStart
    chainEnd: section.bar.sectionJoins[section.slotIndex].chainEnd
    joinEndReach: section.bar.sectionReaches[section.slotIndex]
    readonly property real mainPos: Math.round(section.slot.offset + (section.slot.extent - section.usedLength) * section.align)
    // The bar's gradient runs along its whole length, wherever widgets are,
    // so a widget coming or going never shifts its colors
    barStart: section.mainPos
    barLength: section.barConfig.look.gradient !== null ? section.bar.length : 0

    barConfig: section.bar.barConfig
    panel: section.bar.panel
    screen: section.bar.screen
    maxExtent: section.slot.extent
    hiddenIndices: section.bar.hidden[section.slotIndex]

    // crossStart in from the bar's outer edge (see BarsConfig.enrichBarConfig)
    readonly property real crossPos: {
      const across = section.bar.isVertical ? section.bar.width : section.bar.height;
      const size = section.bar.isVertical ? width : height;
      const start = Math.round(section.barConfig.crossStart);
      const farSide = section.barConfig.right || section.barConfig.bottom;
      return farSide ? across - start - size : start;
    }
    // Tabs reach from the widgets out to the bar's tabEdge, their ends
    // bounded as the bar's, in the section's own coordinates
    tabReach: section.bar.tabs ? Math.max(0, Math.round(section.barConfig.crossStart) - section.bar.tabEdge) : 0
    tabBounds: section.bar.tabBounds.map(b => ({
          "start": b.start - section.drawnPos,
          "end": b.end - section.drawnPos,
          "startRadius": b.startRadius,
          "endRadius": b.endRadius
        }))

    // Where it's drawn along the bar, and how long: gliding to the layout's
    // (as its widgets do, BarWidgetHost), which pills follow. Off until
    // first placed, so a new bar doesn't slide its sections in.
    property real drawnPos: section.mainPos
    property real drawnLength: section.usedLength
    property bool _settled: false
    // A method, not a closure: the call is dropped if the section is gone
    // by then (a bar rebuilt)
    Component.onCompleted: Qt.callLater(section._settle)
    function _settle() {
      section._settled = true;
    }
    Glide on drawnPos {
      enabled: section._settled
    }
    Glide on drawnLength {
      enabled: section._settled
    }

    x: section.bar.isVertical ? section.crossPos : section.drawnPos
    y: section.bar.isVertical ? section.drawnPos : section.crossPos
    // Gives way under an outer bar's popout (coveredSpans)
    opacity: section.bar.covers(section.drawnPos, section.drawnPos + section.drawnLength) ? 0 : 1
    Behavior on opacity {
      NumberAnimation {
        duration: Appearance.animFast
        easing.type: Appearance.easing
      }
    }
  }

  // Where the blur window cuts the bar's shapes and shadow, in screen px
  // (BlurShape.clipRect): its window, for an auto-hiding bar sliding out
  // of it (BarPanel); null for none
  property var blurClip: null
  // The blur window draws the bar's fill (BlurManager), once
  // its window is placed on screen: where its shapes are, the container's
  // top-left on screen
  readonly property var blurOrigin: root.panel?.screenOrigin ? Qt.point(root.panel.screenOrigin.x + root.x, root.panel.screenOrigin.y + root.y) : null
  readonly property string blurScreen: root.panel?.screen?.name ?? ""
  readonly property bool backed: BlurManager.backsOn(root.blurScreen, root.panel?.onOverlayLayer ?? false) && root.blurOrigin !== null

  // Where the open popouts of the bars outside it on its edge lie over it,
  // along it in its own coordinates (ScreenEdgeManager.coveredOn): the
  // islands and sections there give way (fade out) while they're open, as
  // a popout's fill, drawn in the blur window under every bar, can't
  // cover them
  readonly property var coveredSpans: {
    const placed = root.panel?.screenPlaced ?? null;
    if (!placed)
      return [];
    const at = (root.isVertical ? placed.y : placed.x) + (root.isVertical ? root.y : root.x);
    return ScreenEdgeManager.coveredOn(root.panel.screen, root.barConfig).map(c => ({
          "start": c.start - at,
          "end": c.end - at
        }));
  }
  function covers(start, end) {
    return root.coveredSpans.some(c => c.start < end && c.end > start);
  }

  // What the bar paints under its widgets: its background, inner stroke
  // and pills, which the shadow follows
  Item {
    id: surface
    anchors.fill: parent

    // A transparent bar over a wallpaper its content can't read on: a soft
    // shade of the theme background, `scrim` strong along the whole bar and
    // fading out over `scrimReach` past it (the window holds that room). It
    // glides with the wallpaper.
    Rectangle {
      id: scrim
      readonly property real reach: root.barConfig.scrimReach ?? 0
      readonly property real total: root.barConfig.extent + scrim.reach
      // The bar's share of the gradient; the screen edge is its far end
      // for a bottom or right bar
      readonly property real share: scrim.total > 0 ? root.barConfig.extent / scrim.total : 1
      readonly property bool far: root.barConfig.bottom || root.barConfig.right
      x: root.isVertical && scrim.far ? -scrim.reach : 0
      y: !root.isVertical && scrim.far ? -scrim.reach : 0
      width: root.isVertical ? scrim.total : root.width
      height: root.isVertical ? root.height : scrim.total
      opacity: root.barConfig.scrim ?? 0
      visible: scrim.opacity > 0
      Glide on opacity {
        duration: Appearance.animSlow
      }
      gradient: Gradient {
        orientation: root.isVertical ? Gradient.Horizontal : Gradient.Vertical

        GradientStop {
          position: 0
          color: scrim.far ? "transparent" : Style.surfacePage
        }
        GradientStop {
          position: scrim.far ? 1 - scrim.share : scrim.share
          color: Style.surfacePage
        }
        GradientStop {
          position: 1
          color: scrim.far ? Style.surfacePage : "transparent"
        }
      }
    }

    Rectangle {
      id: solidFill
      anchors.fill: parent
      visible: root.barConfig.solid
      color: root.backed ? "transparent" : BlurManager.fillOn(Style.surfacePage, root.blurScreen)

      BlurShape {
        source: solidFill
        kind: "rect"
        screen: root.blurScreen
        x: root.blurOrigin?.x ?? 0
        y: root.blurOrigin?.y ?? 0
        shown: root.backed && solidFill.visible
        shadow: root.barConfig
        paintRank: PaintOrder.rankOf("base")
        clipRect: root.blurClip
      }
    }

    // A solid bar's inner stroke (border off) while the backing window backs
    // it: its stroke alone, over the bar's own fill (a rank above it) and
    // under what joins it, left open where the pieces below are
    // (strokeHoles, which its copy cuts). Not shown here: the pieces draw it
    // while unbacked
    Rectangle {
      id: solidStroke
      visible: false
      color: "transparent"
      width: root.isVertical ? Appearance.borderWidth : root.length
      height: root.isVertical ? root.length : Appearance.borderWidth
      x: root.isVertical ? (root.barConfig.left ? root.width - width : 0) : 0
      y: root.isVertical ? 0 : (root.barConfig.top ? root.height - height : 0)
      // The openings along it, across its whole width (the spans the pieces
      // leave out)
      readonly property var strokeHoles: root._openingList.map(o => {
        const start = Math.max(0, o.start), end = Math.min(root.length, o.end);
        if (end <= start)
          return null;
        return root.isVertical ? Qt.rect(0, start, Appearance.borderWidth, end - start) : Qt.rect(start, 0, end - start, Appearance.borderWidth);
      }).filter(hole => hole !== null)

      BlurShape {
        source: solidStroke
        kind: "rect"
        color: "transparent"
        strokeColor: Style.frameStroke
        paintRank: PaintOrder.rankOf("frame")
        screen: root.blurScreen
        x: (root.blurOrigin?.x ?? 0) + solidStroke.x
        y: (root.blurOrigin?.y ?? 0) + solidStroke.y
        shown: root.backed && root.barConfig.innerStroke && solidFill.visible
        clipRect: root.blurClip
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
        // Under an outer bar's popout it gives way (coveredSpans): faded,
        // its fill and shadow left out of the blur window
        readonly property bool covered: root.covers(rect.start, rect.start + rect.length)
        opacity: covered ? 0 : 1
        Behavior on opacity {
          NumberAnimation {
            duration: Appearance.animFast
            easing.type: Appearance.easing
          }
        }
        // The inner side's corners at the bar's start and end
        property real startInner: rect.squareStart ? 0 : corner
        property real endInner: rect.squareEnd ? 0 : corner

        x: root.isVertical ? across : rect.start
        y: root.isVertical ? rect.start : across
        width: root.isVertical ? depth : rect.length
        height: root.isVertical ? rect.length : depth
        color: root.backed ? "transparent" : BlurManager.fillOn(Style.surfacePage, root.blurScreen)
        // The stroke drawn by the one below, left open where a popout joins
        border.width: 0
        // On the inner side, the stroke and its fringe under each opening (a
        // pixel past the island's wall where the opening reaches it,
        // EdgeAttach.strokeHoleAlong): read by its copy
        readonly property var strokeHoles: root._openingList.map(o => {
          const along = root.isVertical ? island.y : island.x;
          const start = Math.max(0, o.start - along);
          const end = Math.min(root.isVertical ? island.height : island.width, o.end - along);
          if (end <= start)
            return null;
          const run = EdgeAttach.strokeHoleAlong(start, end, 0, root.isVertical ? island.height : island.width);
          const sw = Appearance.borderWidth;
          const band = EdgeAttach.strokeHoleAcross(root.barConfig.left || root.barConfig.top ? (root.isVertical ? island.width : island.height) - sw : 0, sw);
          return root.isVertical ? Qt.rect(band.start, run.start, band.size, run.end - run.start) : Qt.rect(run.start, band.start, run.end - run.start, band.size);
        }).filter(hole => hole !== null)

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: root.backed ? "transparent" : Style.frameStroke
          border.width: Appearance.borderWidth
          topLeftRadius: island.topLeftRadius
          topRightRadius: island.topRightRadius
          bottomLeftRadius: island.bottomLeftRadius
          bottomRightRadius: island.bottomRightRadius
        }

        BlurShape {
          source: island
          kind: "rect"
          screen: root.blurScreen
          x: (root.blurOrigin?.x ?? 0) + island.x
          y: (root.blurOrigin?.y ?? 0) + island.y
          // (faded with the island, covered: its border fades with it too)
          shown: root.backed && island.opacity > 0
          fade: island.opacity
          strokeColor: Style.frameStroke
          paintRank: PaintOrder.rankOf("bar")
          shadow: root.barConfig
          clipRect: root.blurClip
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
        // Its depth (pillReach), less the surface's far half-gap, which is
        // empty. At a high radius the half gap is deeper than the pill:
        // the box then starts at the pill's far side, never past it (which
        // drew the far stroke deeper than pillDepth, where what stands on
        // it and its openings take it to be)
        readonly property real depthBox: root.pillReach - pill.boxStart
        boxStart: Math.min(connectorGap / 2, root.pillReach)

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
        // Its fillets off the outer edge and its far corners, scaled
        // alike to meet across its depth (pillRadii); square where a
        // popout runs flush into it
        attachFilletRadius: root.pillRadii.fillet
        startCornerRadius: span.squareStart ? 0 : root.pillRadii.corner
        endCornerRadius: span.squareEnd ? 0 : root.pillRadii.corner

        Glide on startCornerRadius {}
        Glide on endCornerRadius {}

        width: implicitWidth
        height: implicitHeight
        x: root.isVertical ? (root.barConfig.right ? root.width - width - root.barConfig.stripCover : root.barConfig.stripCover) : alongStart
        y: root.isVertical ? alongStart : (root.barConfig.bottom ? root.height - height - root.barConfig.stripCover : root.barConfig.stripCover)
        backed: root.backed
        opaque: BlurManager.opaqueOn(root.blurScreen)
        // Grown out of the border's stroke, which it covers there...
        readonly property real _along: root.isVertical ? pill.y : pill.x
        BorderOpening {
          opening: root.borderOpening(pill._along + pill.coverStart, pill._along + pill.coverEnd)
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
        // The far stroke and its fringe under each opening (a pixel past the
        // pill's wall where the opening reaches it, EdgeAttach.strokeHoleAlong)
        // (in the pill's coordinates), and a joined end's fillet where one reaches it: a
        // surface joined to the same edge runs on down it, over the fillet
        // and, at a squared end a surface joins end-on (`coverStart`), the
        // corner under its wall from where it covers the stroke; there the band
        // stops a pixel (its fringe) short of the wall and the corner piece starts
        // with it, as at a fractional scale the band's last device row would be the
        // wall's first
        strokeHoles: [].concat(...root._openingList.map(o => {
          const along = root.isVertical ? pill.y : pill.x;
          const start = Math.max(o.start, along);
          const end = Math.min(o.end, along + pill.alongLength);
          if (end <= start)
            return [];
          const R = pill.filletRadius, h = pill.half, L = pill.alongLength;
          const joins = [];
          const run = EdgeAttach.strokeHoleAlong(start, end, pill.joinStart ? -Infinity : along + pill.startMargin, pill.joinEnd ? Infinity : along + L - pill.endMargin);
          let farStart = run.start, farEnd = run.end;
          if (pill.joinStart && start <= along + 1)
            joins.push(pill._rectFrom(0, pill.farV - h - 1, h + R + 1, R + h + 2));
          if (pill.joinEnd && end >= along + L - 1)
            joins.push(pill._rectFrom(L - h - R - 1, pill.farV - h - 1, h + R + 1, R + h + 2));
          if (o.coverStart !== undefined) {
            const at = o.coverStart - (root.isVertical ? pill.x : pill.y);
            const far = pill._rectFrom(0, pill.farV, 0, 0);
            const v = pill.farV + (root.barConfig.left || root.barConfig.top ? 1 : -1) * (at - (root.isVertical ? far.x : far.y));
            const deep = pill.farV + h + 1 - v;
            const boxEnd = L - pill.endMargin;
            if (span.squareEnd && end >= along + boxEnd - pill.strokeWidth - 1) {
              farEnd = end - 1;
              joins.push(pill._rectFrom(farEnd - along, v, boxEnd + 1 - (farEnd - along), deep));
            }
            if (span.squareStart && start <= along + pill.startMargin + pill.strokeWidth + 1) {
              farStart = start + 1;
              joins.push(pill._rectFrom(pill.startMargin - 1, v, farStart - along - pill.startMargin + 1, deep));
            }
          }
          return [pill._farHole(farStart, farEnd, false)].concat(joins);
        }))
        // The stroke, with its anti-aliased fringe a pixel either side, or
        // (`inner`) that fringe's row inside the pill alone, taken from the
        // pill's own far stroke (`farV`, its centre line) as drawn
        function _farHole(start, end, inner) {
          const band = EdgeAttach.strokeHoleAcross(pill.farV - pill.half, pill.strokeWidth);
          const along = root.isVertical ? pill.y : pill.x;
          return pill._rectFrom(start - along, band.start, end - start, inner ? 1 : band.size);
        }
        BlurShape {
          source: pill
          screen: root.blurScreen
          x: (root.blurOrigin?.x ?? 0) + pill.x
          y: (root.blurOrigin?.y ?? 0) + pill.y
          shown: root.backed
          shadow: root.barConfig
          // A pill merging into another bar's (CornerMerge) stands over it
          paintRank: PaintOrder.rankOf((pill.index === 0 && root.ends.start.kind === "pillBar") || (pill.index === root.pillShapes.length - 1 && root.ends.end.kind === "pillBar") ? "cornerJoin" : "bar")
          clipRect: root.blurClip
        }
      }
    }
  }

  // The accent line along its inner or outer edge, along the bar or each
  // pill or island (the look's accentLine)
  AccentLines {
    anchors.fill: parent
    bar: root
  }

  Section {
    id: leftGroup
    bar: root
    slotIndex: 0
  }

  Section {
    id: centerGroup
    bar: root
    slotIndex: 1
  }

  Section {
    id: rightGroup
    bar: root
    slotIndex: 2
  }
}
