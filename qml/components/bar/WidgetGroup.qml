pragma ComponentBehavior: Bound

import QtQuick

import qs.services.ui
import qs.components.methods

// One bar section: a row (or column, on a vertical bar) of BarWidgetHosts that
// fits itself into `maxExtent` along the main axis by shrinking elastic
// modules. Which modules to drop when the whole bar overflows is decided
// bar-wide by BarContainer (`hiddenIndices`); should the minimum sizes
// still not fit, the lowest-priority modules here are hidden as a last
// resort. Sizes are measured from the modules and never from the
// allocation, so this can't feed back into itself.
Item {
  id: root

  required property var barConfig
  property var panel
  property var screen
  // The section's key in the bar's `widgets`
  property string zone: ""
  // The section's widgets (BarContainer.widgetModel entries). Modelled by
  // count, so edits to a widget's options reach it in place instead of
  // rebuilding every widget in the section.
  property var widgets: []

  // A powerline's widgets touch (BarsConfig.enrichBarConfig)
  readonly property int spacing: root.barConfig.groupSpacing
  readonly property string grouping: root.barConfig.look.grouping
  // Room the bar's section layout gives this group along the main axis
  property real maxExtent: Infinity
  // Which way the group grows within its slot (0 start, 1 end, 0.5 center)
  property real align: 0.5
  // Model indices the bar has hidden to make everything fit
  property var hiddenIndices: []

  readonly property bool isVertical: barConfig.vertical

  // Tabs (the look's shape tab): backgrounds reach `tabReach` past the
  // widgets' outer side, out to the edge they hang from, their ends
  // bounded by `tabBounds` (BarTabs.tabLimits; along it, in its own
  // coordinates). Both set by BarContainer.
  property real tabReach: 0
  property var tabBounds: []
  readonly property bool _tabs: root.barConfig.look.shape.name === "tab"
  readonly property real _reach: root._tabs ? root.tabReach : 0
  // A tab's reach across: before the widgets' near side (in from the
  // outer edge) or past their far one (the outer edge past their far side:
  // a bottom or right bar)
  readonly property var _reachAcross: BarTabs.reachAcross(root._reach, root.barConfig.right || root.barConfig.bottom)
  // What bounds a tab drawn from `start` for `length` along the group
  function tabLimitsOf(start, length) {
    return root._tabs ? BarTabs.tabLimits(start, start + length, root.tabBounds) : [null, null];
  }

  // The bar's gradient (its look's `gradient`) runs along the whole
  // bar, `barLength` long (0 with none), each widget showing its slice:
  // where the group starts along the bar as laid out. Laid-out places,
  // never gliding ones, so nothing re-reads them each frame of a glide.
  property real barStart: 0
  property real barLength: 0
  readonly property bool _graded: root.barLength > 0 && root.barConfig.look.gradient !== null

  property var _modules: []

  readonly property var measures: root._modules.map(m => ({
        "pref": m.preferredSize,
        "min": m.minimumSize,
        "priority": m.priority,
        "divides": m.divides,
        "fill": m.fills
      }))
  // What decides the joins between sections (BarLayout.sectionJoins): a
  // widget's own size, without the insets that follow the joins
  readonly property var joinMeasures: root._modules.map(m => ({
        "pref": m._preferred,
        "divides": m.divides,
        "fill": m.fills
      }))
  // Spacers (`fill`) are shown at any size: they take the free room
  readonly property var _fills: root.measures.map(m => m.fill)
  readonly property var _shown: root.measures.map((m, i) => (m.pref > 0 || m.fill) && !root.hiddenIndices.includes(i))
  // How many spacers it has: a side with any stretches to the center
  // (BarLayout.layoutSections)
  readonly property int fillCount: root._fills.filter(f => f).length

  // Main-axis size wanted with every shown module at its preferred size,
  // and the least it can be squeezed to without hiding anything more
  readonly property real preferredLength: BarLayout.span(root.measures.map((m, i) => root._shown[i] ? m.pref : 0), root.spacing, root._fills)
  readonly property real minimumLength: BarLayout.span(root.measures.map((m, i) => root._shown[i] ? m.min : 0), root.spacing, root._fills)
  // ...and with none hidden for want of room (for the bar editor)
  readonly property real wantedLength: BarLayout.span(root.measures.map(m => m.pref), root.spacing, root._fills)

  // As the center: its parts around the group it keeps centered when it
  // has spacers (BarLayout.centerParts, for laying the sections out), and
  // the room each of its spacers takes there (BarLayout.centerFillWeights;
  // unset, its spacers share its room equally)
  readonly property var centerParts: BarLayout.centerParts(root.measures, root._shown, root.spacing, "pref")
  property var fillWeights: undefined
  readonly property var allocation: BarLayout.allocate(root.measures, root._shown, root.maxExtent, root.spacing, root.fillWeights)
  readonly property real usedLength: BarLayout.span(root.allocation.sizes, root.spacing, root._fills)
  // The dividers (Separators) at the section's ends, which the bar places
  // in the gap beside it (BarLayout.edgeHang): as measured, for laying the
  // sections out, and as allocated, for its pill. Not spacers: they're
  // room of the section's own.
  readonly property var _dividers: root.measures.map(m => m.divides && !m.fill)
  readonly property var layoutHang: BarLayout.edgeHang(root.measures.map((m, i) => root._shown[i] ? m.pref : 0), root._dividers, root.spacing)
  readonly property var drawnHang: BarLayout.edgeHang(root.allocation.sizes, root._dividers, root.spacing)
  // The widgets with something to show that are hidden for want of room,
  // by their index in the section's config (for the bar editor)
  readonly property var crowdedOut: root.widgets.filter((w, i) => (root.measures[i]?.pref ?? 0) > 0 && !root.allocation.visible[i]).map(w => w.configIndex)
  // How the widget the bar editor has selected is sized here, else null
  readonly property var selectedMeasure: root._modules.find(m => m.highlighted)?.measure ?? null

  // Neighbouring widgets with backgrounds form runs (merged backgrounds,
  // powerline chains). Insets come from what each widget has to show,
  // never from the room it's given, which they help decide; shapes from
  // what's actually shown. A widget showing nothing (null) leaves a run
  // whole; one shown without a background (false) splits it.
  // Joined to the next section's run (chainStart/chainEnd), a run at
  // that end carries on past it. A merged widget keeps its cap room as
  // if alone; a powerline segment's insets are those of one mid-chain.
  // The flags pass through a string key (BarRuns.flagsKey), as `_idsKey`s
  // do, so the places and all that's built from them (insets, shapes, a
  // segmented widget's cells) change only when the flags do: any widget's
  // new size re-reads them, mostly to the same values.
  readonly property string _insetKey: BarRuns.flagsKey(root._modules.map(m => m.naturalSize > 0 ? m.hasBackground : null))
  readonly property var _insetFlags: BarRuns.flagsOf(root._insetKey)
  readonly property bool _chainInsets: root.grouping === "powerline"
  readonly property var _insetPlaces: BarLayout.runPlaces(root._insetFlags, root._chainInsets && root.chainStart, root._chainInsets && root.chainEnd)
  readonly property string _drawnKey: BarRuns.flagsKey(root._modules.map((m, i) => (root.allocation.visible[i] ?? false) && (root.allocation.sizes[i] ?? 0) > 0 ? m.hasBackground : null))
  readonly property var _drawn: BarRuns.flagsOf(root._drawnKey)
  readonly property var _drawPlaces: BarLayout.runPlaces(root._drawn, root.chainStart, root.chainEnd)
  // Whether its first and last widgets with something to show have
  // backgrounds (from content, as the insets): a joined boundary carries a
  // run on only between two such (BarContainer.sectionJoins)
  readonly property bool startsInRun: root._insetFlags.find(f => f !== null) === true
  readonly property bool endsInRun: root._insetFlags.slice().reverse().find(f => f !== null) === true
  readonly property var _drawRuns: BarLayout.runs(root._drawn)
  // What of the bar its runs read (its shape, grouping, opaque trait,
  // sizes, and the loose gap a widget with no background keeps in a
  // powerline: BarRuns.context)
  readonly property var _ctx: BarRuns.context(root.barConfig)
  // The first and last widgets with something to show (from their
  // content, never the room they're given), and whether its ends join
  // (for the insets: BarRuns.insets)
  readonly property var _hasContent: root._modules.map(m => m.naturalSize > 0)
  readonly property var _section: ({
      "first": root._hasContent.indexOf(true),
      "last": root._hasContent.lastIndexOf(true),
      "joinStart": root.joinStart,
      "joinEnd": root.joinEnd
    })

  // Its groups of widgets as drawn, [{ start, end }] along it in its own
  // coordinates: the runs of shown widgets between its ends and its
  // spacers, a spacer given room splitting one (BarContainer joins them
  // into pills, islands and merged backgrounds, BarLayout.joinGroups)
  readonly property var drawnGroups: {
    const out = [];
    let open = null;
    root._modules.forEach((m, i) => {
      const size = root.allocation.sizes[i] ?? 0;
      if (m.fills) {
        if (size > 0)
          open = null;
        return;
      }
      if (!(root.allocation.visible[i] ?? false) || size <= 0)
        return;
      const start = root.isVertical ? m.y : m.x;
      const end = start + (root.isVertical ? m.height : m.width);
      if (open) {
        open.end = end;
      } else {
        open = {
          "start": start,
          "end": end
        };
        out.push(open);
      }
    });
    return out;
  }
  // Its start joins the section before it, and its end the next one, the
  // next one's widgets starting `joinEndReach` on past its last
  // (BarContainer.sectionJoins, BarLayout.sectionJoins): a separator mark
  // in that gap, and its run carried on where both widgets facing it have
  // backgrounds (`chainStart`/`chainEnd`): one merged background, one
  // powerline chain across the sections
  property bool joinStart: false
  property bool joinEnd: false
  property bool chainStart: false
  property bool chainEnd: false
  property real joinEndReach: 0

  implicitWidth: isVertical ? root.barConfig.thickness : usedLength
  implicitHeight: isVertical ? usedLength : root.barConfig.thickness

  // Under its widgets: the merged runs' backgrounds, the separator marks
  // and each widget's background
  WidgetDecorations {
    barConfig: root.barConfig
    ctx: root._ctx
    hosts: root._modules
    count: root.widgets.length
    allocation: root.allocation
    runs: root._drawRuns
    places: root._drawPlaces
    marks: BarRuns.marks(root.allocation.sizes, root._modules.map(m => m.divides), root._fills, root.joinEnd)
    spacing: root.spacing
    chainEnd: root.chainEnd
    joinEndReach: root.joinEndReach
    reachAcross: root._reachAcross
    tabReach: root._reach
    tabLimitsOf: root.tabLimitsOf
    graded: root._graded
    // Where `along` (in the group, as laid out) sits along the bar (0-1)
    barSpot: along => BarGradient.spot(along, 0, root.barStart, root.barLength)
  }

  Repeater {
    id: repeater
    model: root.widgets.length

    onItemAdded: (index, item) => {
      const modules = root._modules.slice();
      modules.splice(index, 0, item);
      root._modules = modules;
    }
    onItemRemoved: (index, item) => {
      root._modules = root._modules.filter(m => m !== item);
    }

    delegate: BarWidgetHost {
      id: module
      required property int index
      readonly property var modelData: root.widgets[index] ?? {}

      // Clear of its caps; a widget with no background sits loose, and
      // one laying its parts out as segments keeps their room itself
      // (BarRuns.insets)
      readonly property var _place: root._insetPlaces[module.index] ?? null
      readonly property var _room: BarRuns.insets(root._ctx, module._place, {
        "background": module.hasBackground,
        "segments": module.segments,
        "fills": module.fills,
        "contentAcross": module.contentAcross
      }, module.index, root._section)
      leadInset: module._room.lead
      trailInset: module._room.trail
      // Hovered and clicked in its background's shape as drawn
      readonly property var _drawnPlace: root._drawPlaces[module.index] ?? null
      hitShape: module._drawnPlace !== null ? BarRuns.segmentAt(root._ctx, module._drawnPlace) : null
      // Its place in the run, for its parts to take as segments of it:
      // their room from what's shown, their shapes from where they're
      // drawn, a tab's ends bounded as its own background's would be
      // (from where it's laid out, never as it glides). Through a string
      // key, so a neighbour's new size (moving it, the places re-read)
      // rebuilds its parts only when the place changes.
      readonly property string _runKey: module.segments ? JSON.stringify({
        "sized": module._place,
        "drawn": module._drawnPlace,
        "tabLimits": root.tabLimitsOf(module._offset, module.mainSize)
      }) : ""
      runPlace: module._runKey !== "" ? JSON.parse(module._runKey) : null
      // Its tab's reach past its outer side (a tab hangs only from a background)
      tabReach: module.hasBackground ? root._reach : 0

      barConfig: root.barConfig
      barStart: root._graded ? root.barStart + module._offset : 0
      barLength: root._graded ? root.barLength : 0
      widget: module.modelData
      highlighted: BarManager.isSelectedWidget(root.barConfig.sourceId, root.zone, module.modelData.configIndex ?? -1)
      hoverHighlighted: BarManager.isHoveredWidget(root.barConfig.sourceId, root.zone, module.modelData.configIndex ?? -1)
      // The bar editor's chip of the widget under the pointer looks hovered
      onPointerHoveredChanged: if (BarManager.editing)
        BarManager.setBarHover(root.barConfig.sourceId, root.zone, module.modelData.configIndex ?? -1, module.pointerHovered)
      panel: root.panel
      screen: root.screen

      readonly property real _offset: root.allocation.offsets[module.index] ?? 0
      mainSize: root.allocation.sizes[module.index] ?? 0
      shown: root.allocation.visible[module.index] ?? false
      x: root.isVertical ? 0 : module._offset
      y: root.isVertical ? module._offset : 0
    }
  }
}
