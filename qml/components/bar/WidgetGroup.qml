pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

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
  // The outer edge is past the far side of the widgets (a bottom or right bar)
  readonly property bool _outerFar: root.barConfig.right || root.barConfig.bottom
  // A tab's reach across: before the widgets' near side (in from the
  // outer edge) or past their far one
  readonly property real _reachNear: root._outerFar ? 0 : root._reach
  readonly property real _reachFar: root._outerFar ? root._reach : 0
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
  // The flags pass through a string key (_flagsKey), as `_idsKey`s do, so
  // the places and all that's built from them (insets, shapes, a segmented
  // widget's cells) change only when the flags do: any widget's new size
  // re-reads them, mostly to the same values.
  readonly property string _insetKey: root._flagsKey(root._modules.map(m => m.naturalSize > 0 ? m.hasBackground : null))
  readonly property var _insetFlags: root._flagsOf(root._insetKey)
  readonly property bool _chainInsets: root.grouping === "powerline"
  readonly property var _insetPlaces: BarLayout.runPlaces(root._insetFlags, root._chainInsets && root.chainStart, root._chainInsets && root.chainEnd)
  readonly property string _drawnKey: root._flagsKey(root._modules.map((m, i) => (root.allocation.visible[i] ?? false) && (root.allocation.sizes[i] ?? 0) > 0 ? m.hasBackground : null))
  readonly property var _drawn: root._flagsOf(root._drawnKey)
  readonly property var _drawPlaces: BarLayout.runPlaces(root._drawn, root.chainStart, root.chainEnd)
  // Run flags (true, false, null) as a string and back
  function _flagsKey(flags) {
    return flags.map(f => f === null ? "-" : f ? "1" : "0").join("");
  }
  function _flagsOf(key) {
    return key.split("").map(c => c === "-" ? null : c === "1");
  }
  // Whether its first and last widgets with something to show have
  // backgrounds (from content, as the insets): a joined boundary carries a
  // run on only between two such (BarContainer.sectionJoins)
  readonly property bool startsInRun: root._insetFlags.find(f => f !== null) === true
  readonly property bool endsInRun: root._insetFlags.slice().reverse().find(f => f !== null) === true
  readonly property var _drawRuns: BarLayout.runs(root._drawn)
  // Opaque fills hide what's under them: a powerline segment can then
  // start square beneath the one before (the look's `opaque` trait)
  readonly property bool _opaque: root.barConfig.look.traits.opaque
  // A widget with no background in a powerline (a Separator) splits the
  // chain, keeping the bar's spacing to the widgets beside it in the
  // section as between separate widgets. At the section's end the gap to
  // the next section stands in, as on any other bar.
  readonly property real _looseGap: root.grouping === "powerline" ? root.barConfig.widgetGap : 0
  // The first and last widgets with something to show (from their
  // content, never the room they're given)
  readonly property var _hasContent: root._modules.map(m => m.naturalSize > 0)
  readonly property int _firstContent: root._hasContent.indexOf(true)
  readonly property int _lastContent: root._hasContent.lastIndexOf(true)

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
  // The last widget shown
  readonly property int _lastShown: {
    for (let i = root.allocation.sizes.length - 1; i >= 0; i--) {
      if (root.allocation.sizes[i] > 0 && !root._fills[i])
        return i;
    }
    return -1;
  }

  // The index of the next widget shown after `index`, or -1
  function _nextShown(index) {
    for (let k = index + 1; k < root.allocation.sizes.length; k++) {
      if (root.allocation.sizes[k] > 0)
        return k;
    }
    return -1;
  }

  // How far a run's last widget at `place` runs on past it into the next
  // section's run it joins (chainEnd), else 0
  function _reachOf(place) {
    return place !== null && place.index < place.count - 1 && root.chainEnd ? root.joinEndReach : 0;
  }

  // Where `along` (in the group, as laid out) sits along the bar (0-1)
  function _barSpot(along) {
    return BarGradient.spot(along, 0, root.barStart, root.barLength);
  }

  // The caps and insets at `place` in a run (BarShapes.segment), its
  // content an icon or a label at the bar's font size
  function segmentAt(place) {
    return BarShapes.segment(root.barConfig.look.shape, root.grouping, root._opaque, place?.index ?? 0, place?.count ?? 1, root.barConfig.thickness, root.barConfig.fontSize);
  }

  implicitWidth: isVertical ? root.barConfig.thickness : usedLength
  implicitHeight: isVertical ? usedLength : root.barConfig.thickness

  // Merged runs' shared backgrounds, under everything
  Repeater {
    model: root.grouping === "merged" ? root._drawRuns.length : 0

    delegate: WidgetBackground {
      required property int index
      readonly property var run: root._drawRuns[index] ?? {
        "start": 0,
        "count": 1,
        "members": [0]
      }
      readonly property var first: root._modules[run.members[0]] ?? null
      readonly property var last: root._modules[run.members[run.count - 1]] ?? null
      // Joined across a section's end to the next section's run (its
      // places carry on there): no cap there, the background running on
      // over the gap between them
      readonly property var _firstPlace: root._drawPlaces[run.members[0]] ?? null
      readonly property var _lastPlace: root._drawPlaces[run.members[run.count - 1]] ?? null
      readonly property real _reach: root._reachOf(_lastPlace)
      // Along the group as laid out, for the bar's gradient: one strip of
      // it from the run's start to its end
      readonly property real _from: root.allocation.offsets[run.members[0]] ?? 0
      readonly property real _to: (root.allocation.offsets[run.members[run.count - 1]] ?? 0) + (root.allocation.sizes[run.members[run.count - 1]] ?? 0) + _reach

      z: -2
      barConfig: root.barConfig
      colors: BarsConfig.groupColors(root.barConfig, root._graded ? root._barSpot((_from + _to) / 2) : -1)
      gradientStart: root._graded ? root._barSpot(_from) : -1
      gradientEnd: root._graded ? root._barSpot(_to) : -1
      startCap: root.segmentAt(_firstPlace).startCap
      endCap: root.segmentAt(_lastPlace).endCap
      // Carried on from the section before, and on into the next: its
      // stroke left open there, so no divider shows at the join
      openStart: (_firstPlace?.index ?? 0) > 0
      openEnd: _lastPlace !== null && _lastPlace.index < _lastPlace.count - 1
      // From its first widget to its last, on past a joined end, and out
      // to a tab's edge
      readonly property var _box: BarShapes.boxRect({
        "x": first?.x ?? 0,
        "y": first?.y ?? 0,
        "width": root.isVertical ? (first?.width ?? 0) : (last?.x ?? 0) + (last?.width ?? 0) - (first?.x ?? 0),
        "height": root.isVertical ? (last?.y ?? 0) + (last?.height ?? 0) - (first?.y ?? 0) : (first?.height ?? 0)
      }, 0, root._reachNear, root._reachFar, root.isVertical, _reach)
      x: _box.x
      y: _box.y
      width: _box.width
      height: _box.height
      tabLimits: root.tabLimitsOf(root.isVertical ? (first?.y ?? 0) : (first?.x ?? 0), root.isVertical ? height : width)
    }
  }

  // A divider in each gap between shown widgets (the look's separators),
  // and in the gap to the next section where it joins (joinEnd), except
  // beside a Separator widget
  Repeater {
    model: root.barConfig.look.separators.style !== "none" ? root.widgets.length : 0

    delegate: SeparatorMark {
      id: mark
      required property int index
      readonly property int next: root._nextShown(index)
      readonly property bool _joined: next < 0 && index === root._lastShown && root.joinEnd
      readonly property bool between: (root.allocation.sizes[index] ?? 0) > 0 && (next >= 0 || _joined)
      // From its widget as drawn, so it moves with it
      readonly property var host: root._modules[index] ?? null
      readonly property real center: (host ? (root.isVertical ? host.y + host.height : host.x + host.width) : 0) + (_joined ? root.joinEndReach : root.spacing) / 2

      visible: between && !(root._modules[index]?.divides ?? false) && !(root._modules[next]?.divides ?? false)
      style: root.barConfig.look.separators.style
      color: Theme.resolveColor(root.barConfig.look.separators.color)
      thickness: root.barConfig.look.separators.thickness
      length: BarLayout.dividerLength(mark.style, root.barConfig.thickness)
      vertical: root.isVertical
      // Across, centred as the tabs' content is (BarTabs.tabShift)
      readonly property real _shift: BarTabs.tabShift(root._reach, root._outerFar)
      x: root.isVertical ? Math.round((root.width - width) / 2) + _shift : mark.center - width / 2
      y: root.isVertical ? mark.center - height / 2 : Math.round((root.height - height) / 2) + _shift
    }
  }

  // Each widget's background, under it: a powerline segment reaches back
  // under the one before, so earlier ones are drawn over later ones
  Repeater {
    model: root.widgets.length

    delegate: WidgetBackground {
      required property int index
      readonly property var host: root._modules[index] ?? null
      // A widget going (hidden, or out of room) keeps its last place and
      // colors while its host is still fading or shrinking out, so it goes
      // with it rather than vanishing; a host that stays (a reused
      // delegate, a widget dropping its background) lets go once settled
      readonly property var _place: root._drawPlaces[index] ?? null
      readonly property var _colors: host?.background ?? null
      property var _last: null
      readonly property bool _drawn: (host?._drawnMain ?? 0) > 0.5 && (host?.opacity ?? 0) > 0 && (host.opacity < 1 || host._resizing)
      readonly property var _shown: _place !== null && _colors !== null ? {
        "place": _place,
        "colors": _colors
      } : _drawn ? _last : null
      on_ShownChanged: if (_place !== null && _colors !== null)
        _last = _shown
      readonly property var place: _shown?.place ?? null
      readonly property var segment: root.segmentAt(place)
      // Along the group as laid out, back under a powerline neighbour too
      readonly property real _from: (root.allocation.offsets[index] ?? 0) - segment.back

      z: -1 - index / Math.max(1, root.widgets.length)
      barConfig: root.barConfig
      colors: _shown?.colors ?? null
      startCap: segment.startCap
      endCap: segment.endCap
      seamStart: segment.seamStart
      seamEnd: segment.seamEnd
      shownStart: segment.shownStart
      hovered: host?.outlined ?? false
      pressed: host?.pressed ?? false
      backgroundLevel: host?.backgroundLevel ?? -1
      backgroundLevelColor: host?.backgroundLevelColor ?? "transparent"
      levelStartCap: segment.levelStartCap
      levelEndCap: segment.levelEndCap
      gradientStart: root._graded ? root._barSpot(_from) : -1
      gradientEnd: root._graded ? root._barSpot((root.allocation.offsets[index] ?? 0) + (root.allocation.sizes[index] ?? 0)) : -1
      highlighted: host?.editorOutlined ?? false
      // Its widget draws its parts itself (BarWidgetHost.segments)
      bare: host?.segments ?? false
      // Its split parts, from the host's start to its own (back under the
      // one before)
      readonly property var _split: host?.split ?? null
      splitAt: _split ? _split.at + segment.back : -1
      // (and across, past a tab's reach on the near side)
      splitPart: _split ? Qt.rect(_split.part.x + (root.isVertical ? root._reachNear : segment.back), _split.part.y + (root.isVertical ? segment.back : root._reachNear), _split.part.width, _split.part.height) : Qt.rect(0, 0, 0, 0)
      visible: place !== null
      opacity: (host?.contentOpacity ?? 1) * (host?.opacity ?? 1)
      // A tab reaches out past the widget (tabReach)
      readonly property var _box: BarShapes.boxRect({
        "x": host?.x ?? 0,
        "y": host?.y ?? 0,
        "width": host?.width ?? 0,
        "height": host?.height ?? 0
      }, segment.back, root._reachNear, root._reachFar, root.isVertical)
      x: _box.x
      y: _box.y
      width: _box.width
      height: _box.height
      tabLimits: root.tabLimitsOf(root.isVertical ? y : x, root.isVertical ? height : width)
    }
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
      readonly property var _place: root._insetPlaces[module.index] ?? null
      readonly property var _segment: root.segmentAt(_place)
      leadInset: module.segments ? 0 : module.hasBackground ? module._segment.lead : ((module.index > root._firstContent || root.joinStart) && !module.fills ? root._looseGap : 0)
      // Hovered and clicked in its background's shape as drawn
      readonly property var _drawnPlace: root._drawPlaces[module.index] ?? null
      hitShape: module._drawnPlace !== null ? root.segmentAt(module._drawnPlace) : null
      trailInset: module.segments ? 0 : module.hasBackground ? module._segment.trail : ((module.index < root._lastContent || root.joinEnd) && !module.fills ? root._looseGap : 0)
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
