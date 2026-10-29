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
  readonly property string grouping: root.barConfig.widgetGrouping
  // Room the bar's section layout gives this group along the main axis
  property real maxExtent: Infinity
  // Which way the group grows within its slot (0 start, 1 end, 0.5 center)
  property real align: 0.5
  // Model indices the bar has hidden to make everything fit
  property var hiddenIndices: []

  readonly property bool isVertical: barConfig.vertical

  property var _modules: []

  readonly property var measures: root._modules.map(m => ({
        "pref": m.preferredSize,
        "min": m.minimumSize,
        "priority": m.priority,
        "divides": m.divides
      }))
  readonly property var _shown: root.measures.map((m, i) => m.pref > 0 && !root.hiddenIndices.includes(i))

  // Main-axis size wanted with every shown module at its preferred size,
  // and the least it can be squeezed to without hiding anything more
  readonly property real preferredLength: BarLayout.span(root.measures.map((m, i) => root._shown[i] ? m.pref : 0), root.spacing)
  readonly property real minimumLength: BarLayout.span(root.measures.map((m, i) => root._shown[i] ? m.min : 0), root.spacing)

  readonly property var allocation: BarLayout.allocate(root.measures, root._shown, root.maxExtent, root.spacing)
  readonly property real usedLength: BarLayout.span(root.allocation.sizes, root.spacing)
  // The dividers (Separators) at the section's ends, which the bar places
  // in the gap beside it (BarLayout.edgeHang): as measured, for laying the
  // sections out, and as allocated, for its pill
  readonly property var _dividers: root.measures.map(m => m.divides)
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
  readonly property var _insetPlaces: BarLayout.runPlaces(root._modules.map(m => m.naturalSize > 0 ? m.hasBackground : null))
  readonly property var _drawn: root._modules.map((m, i) => (root.allocation.visible[i] ?? false) && (root.allocation.sizes[i] ?? 0) > 0 ? m.hasBackground : null)
  readonly property var _drawPlaces: BarLayout.runPlaces(root._drawn)
  readonly property var _drawRuns: BarLayout.runs(root._drawn)
  // Opaque fills hide what's under them: a powerline segment can then
  // start square beneath the one before
  readonly property bool _opaque: root.barConfig.widgetStyle === "filled"
  // A widget with no background in a powerline (a Separator) splits the
  // chain, keeping the bar's spacing to the widgets beside it in the
  // section as between separate widgets. At the section's end the gap to
  // the next section stands in, as on any other bar.
  readonly property real _looseGap: root.grouping === "powerline" ? root.barConfig.spacing : 0
  // The first and last widgets with something to show (from their
  // content, never the room they're given)
  readonly property var _hasContent: root._modules.map(m => m.naturalSize > 0)
  readonly property int _firstContent: root._hasContent.indexOf(true)
  readonly property int _lastContent: root._hasContent.lastIndexOf(true)

  // The index of the next widget shown after `index`, or -1
  function _nextShown(index) {
    for (let k = index + 1; k < root.allocation.sizes.length; k++) {
      if (root.allocation.sizes[k] > 0)
        return k;
    }
    return -1;
  }

  // The caps and insets at `place` in a run (BarShapes.segment)
  function segmentAt(place) {
    return BarShapes.segment(root.barConfig.widgetShape, root.barConfig.widgetEnds, root.grouping, root._opaque, place?.index ?? 0, place?.count ?? 1, root.barConfig.widgetSize);
  }

  // Emitted when modules moved or resized within the group
  signal allocationUpdated
  property string _allocationKey: ""
  onAllocationChanged: {
    const key = JSON.stringify(allocation);
    if (key !== _allocationKey) {
      _allocationKey = key;
      allocationUpdated();
    }
  }

  implicitWidth: isVertical ? root.barConfig.widgetSize : usedLength
  implicitHeight: isVertical ? usedLength : root.barConfig.widgetSize

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

      z: -2
      barConfig: root.barConfig
      colors: BarsConfig.groupColors(root.barConfig)
      startCap: root.segmentAt({
        "index": 0,
        "count": run.count
      }).startCap
      endCap: root.segmentAt({
        "index": run.count - 1,
        "count": run.count
      }).endCap
      x: first?.x ?? 0
      y: first?.y ?? 0
      width: root.isVertical ? (first?.width ?? 0) : (last?.x ?? 0) + (last?.width ?? 0) - x
      height: root.isVertical ? (last?.y ?? 0) + (last?.height ?? 0) - y : (first?.height ?? 0)
    }
  }

  // A divider in each gap between shown widgets (Bars[].separatorStyle),
  // except beside a Separator widget
  Repeater {
    model: root.barConfig.separatorStyle !== "none" ? root.widgets.length : 0

    delegate: SeparatorMark {
      id: mark
      required property int index
      readonly property int next: root._nextShown(index)
      readonly property bool between: (root.allocation.sizes[index] ?? 0) > 0 && next >= 0
      // From its widget as drawn, so it moves with it
      readonly property var host: root._modules[index] ?? null
      readonly property real center: (host ? (root.isVertical ? host.y + host.height : host.x + host.width) : 0) + root.spacing / 2

      visible: between && !(root._modules[index]?.divides ?? false) && !(root._modules[next]?.divides ?? false)
      style: root.barConfig.separatorStyle
      color: Theme.resolveColor(root.barConfig.separatorColor)
      thickness: root.barConfig.separatorThickness
      length: BarLayout.dividerLength(mark.style, root.barConfig.widgetSize)
      vertical: root.isVertical
      x: root.isVertical ? Math.round((root.width - width) / 2) : mark.center - width / 2
      y: root.isVertical ? mark.center - height / 2 : Math.round((root.height - height) / 2)
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
      // colors while its host is still drawn, so it shrinks and fades
      // with it rather than vanishing
      readonly property var _place: root._drawPlaces[index] ?? null
      readonly property var _colors: host?.background ?? null
      property var _last: null
      readonly property bool _drawn: (host?._drawnMain ?? 0) > 0.5 && (host?.opacity ?? 0) > 0
      readonly property var _shown: _place !== null && _colors !== null ? {
        "place": _place,
        "colors": _colors
      } : _drawn ? _last : null
      on_ShownChanged: if (_place !== null && _colors !== null)
        _last = _shown
      readonly property var place: _shown?.place ?? null
      readonly property var segment: root.segmentAt(place)

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
      fillShare: host?.fillShare ?? -1
      fillShareColor: host?.fillShareColor ?? "transparent"
      highlighted: host?.highlighted ?? false
      visible: place !== null
      opacity: (host?.contentOpacity ?? 1) * (host?.opacity ?? 1)
      x: (host?.x ?? 0) - (root.isVertical ? 0 : segment.back)
      y: (host?.y ?? 0) - (root.isVertical ? segment.back : 0)
      width: (host?.width ?? 0) + (root.isVertical ? 0 : segment.back)
      height: (host?.height ?? 0) + (root.isVertical ? segment.back : 0)
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
      readonly property var modelData: root.widgets[index] ?? {
        "component": "",
        "properties": {},
        "layout": {}
      }

      // Clear of its caps; a widget with no background sits loose
      readonly property var _place: root._insetPlaces[module.index] ?? null
      readonly property var _segment: root.segmentAt(_place)
      leadInset: module.hasBackground ? module._segment.lead : (module.index > root._firstContent ? root._looseGap : 0)
      // Hovered and clicked in its background's shape as drawn
      readonly property var _drawnPlace: root._drawPlaces[module.index] ?? null
      hitShape: module._drawnPlace !== null ? root.segmentAt(module._drawnPlace) : null
      trailInset: module.hasBackground ? module._segment.trail : (module.index < root._lastContent ? root._looseGap : 0)

      barConfig: root.barConfig
      properties: module.modelData.properties || {}
      layoutOverrides: module.modelData.layout || {}
      componentPath: module.modelData.component
      highlighted: BarManager.isSelectedWidget(root.barConfig.sourceId, root.zone, module.modelData.configIndex ?? -1)
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
