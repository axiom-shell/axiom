pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.bar.look

// What a bar section (WidgetGroup) draws round its widgets, under them and
// filling it: each merged run's shared background, a separator mark in
// each gap (the look's separators), and each widget's background, placed
// from the hosts as drawn (BarShapes.boxRect) by what BarRuns decides. A
// widget's background follows its host's fade, and a widget going keeps
// its last place and colors while its host is still fading or shrinking
// out, so it goes with it rather than vanishing.
Item {
  id: root

  required property var barConfig
  // The section's BarRuns.context
  required property var ctx
  // Its hosts (BarWidgetHost), in order, and how many widgets it has
  required property var hosts
  required property int count
  // Its allocation (BarLayout.allocate: offsets and sizes as laid out)
  required property var allocation
  // Its runs and run places as drawn (BarLayout.runs, runPlaces)
  required property var runs
  required property var places
  // Its separator marks (BarRuns.marks)
  required property var marks
  // The gap between its widgets, and its end's join to the next section:
  // its run carried on (`chainEnd`) and the next section's widgets
  // `joinEndReach` on
  required property real spacing
  required property bool chainEnd
  required property real joinEndReach
  // A tab's reach across past the widgets (BarTabs.reachAcross), and the
  // reach itself (the marks centre as the tabs' content: BarTabs.tabShift)
  required property var reachAcross
  required property real tabReach
  // What bounds a tab drawn from `start` for `length` along the section
  required property var tabLimitsOf
  // With the bar's gradient: where a point along the section (as laid
  // out) sits along the bar (0-1)
  required property bool graded
  required property var barSpot

  readonly property bool _vertical: barConfig.vertical
  readonly property bool _outerFar: barConfig.right || barConfig.bottom

  anchors.fill: parent

  // Merged runs' shared backgrounds, under everything
  Repeater {
    model: root.ctx.grouping === "merged" ? root.runs.length : 0

    delegate: WidgetBackground {
      required property int index
      readonly property var _run: BarRuns.runBackground(root.ctx, root.runs[index] ?? {
        "start": 0,
        "count": 1,
        "members": [0]
      }, root.places, root.allocation.offsets, root.allocation.sizes, root.chainEnd, root.joinEndReach)
      readonly property var first: root.hosts[_run.first] ?? null
      readonly property var last: root.hosts[_run.last] ?? null

      z: -2
      barConfig: root.barConfig
      colors: BarsConfig.groupColors(root.barConfig, root.graded ? root.barSpot((_run.from + _run.to) / 2) : -1)
      gradientStart: root.graded ? root.barSpot(_run.from) : -1
      gradientEnd: root.graded ? root.barSpot(_run.to) : -1
      startCap: _run.startCap
      endCap: _run.endCap
      openStart: _run.openStart
      openEnd: _run.openEnd
      // From its first widget to its last, on past a joined end, and out
      // to a tab's edge
      readonly property var _box: BarShapes.boxRect({
        "x": first?.x ?? 0,
        "y": first?.y ?? 0,
        "width": root._vertical ? (first?.width ?? 0) : (last?.x ?? 0) + (last?.width ?? 0) - (first?.x ?? 0),
        "height": root._vertical ? (last?.y ?? 0) + (last?.height ?? 0) - (first?.y ?? 0) : (first?.height ?? 0)
      }, 0, root.reachAcross.near, root.reachAcross.far, root._vertical, _run.reach)
      x: _box.x
      y: _box.y
      width: _box.width
      height: _box.height
      tabLimits: root.tabLimitsOf(root._vertical ? (first?.y ?? 0) : (first?.x ?? 0), root._vertical ? height : width)
    }
  }

  // A mark in each gap between shown widgets, and in the gap to the next
  // section where it joins
  Repeater {
    model: root.barConfig.look.separators.style !== "none" ? root.count : 0

    delegate: SeparatorMark {
      id: mark
      required property int index
      readonly property var _slot: root.marks[index] ?? {
        "shown": false,
        "joined": false
      }
      // From its widget as drawn, so it moves with it
      readonly property var host: root.hosts[index] ?? null
      readonly property real center: (host ? (root._vertical ? host.y + host.height : host.x + host.width) : 0) + (_slot.joined ? root.joinEndReach : root.spacing) / 2

      visible: _slot.shown
      style: root.barConfig.look.separators.style
      color: Theme.resolveColor(root.barConfig.look.separators.color)
      thickness: root.barConfig.look.separators.thickness
      length: BarLayout.dividerLength(mark.style, root.barConfig.thickness)
      vertical: root._vertical
      // Across, centred as the tabs' content is (BarTabs.tabShift)
      readonly property real _shift: BarTabs.tabShift(root.tabReach, root._outerFar)
      x: root._vertical ? Math.round((root.width - width) / 2) + _shift : mark.center - width / 2
      y: root._vertical ? mark.center - height / 2 : Math.round((root.height - height) / 2) + _shift
    }
  }

  // Each widget's background, under it: a powerline segment reaches back
  // under the one before, so earlier ones are drawn over later ones
  Repeater {
    model: root.count

    delegate: WidgetBackground {
      required property int index
      readonly property var host: root.hosts[index] ?? null
      // A widget going (hidden, or out of room) keeps its last place and
      // colors while its host is still fading or shrinking out, so it goes
      // with it rather than vanishing; a host that stays (a reused
      // delegate, a widget dropping its background) lets go once settled
      readonly property var _place: root.places[index] ?? null
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
      readonly property var segment: BarRuns.segmentAt(root.ctx, place)
      // Along the section as laid out, back under a powerline neighbour too
      readonly property real _from: (root.allocation.offsets[index] ?? 0) - segment.back

      z: -1 - index / Math.max(1, root.count)
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
      gradientStart: root.graded ? root.barSpot(_from) : -1
      gradientEnd: root.graded ? root.barSpot((root.allocation.offsets[index] ?? 0) + (root.allocation.sizes[index] ?? 0)) : -1
      highlighted: host?.editorOutlined ?? false
      // Its widget draws its parts itself (BarWidgetHost.segments)
      bare: host?.segments ?? false
      // Its split parts, from the host's start to its own (back under the
      // one before)
      readonly property var _split: host?.split ?? null
      splitAt: _split ? _split.at + segment.back : -1
      // (and across, past a tab's reach on the near side)
      splitPart: _split ? Qt.rect(_split.part.x + (root._vertical ? root.reachAcross.near : segment.back), _split.part.y + (root._vertical ? segment.back : root.reachAcross.near), _split.part.width, _split.part.height) : Qt.rect(0, 0, 0, 0)
      splitInner: _split ? _split.inner.map(s => ({
            "from": s.from + segment.back,
            "at": s.at + segment.back,
            "part": Qt.rect(s.part.x + (root._vertical ? root.reachAcross.near : segment.back), s.part.y + (root._vertical ? segment.back : root.reachAcross.near), s.part.width, s.part.height)
          })) : []
      visible: place !== null
      opacity: (host?.contentOpacity ?? 1) * (host?.opacity ?? 1)
      // A tab reaches out past the widget (tabReach)
      readonly property var _box: BarShapes.boxRect({
        "x": host?.x ?? 0,
        "y": host?.y ?? 0,
        "width": host?.width ?? 0,
        "height": host?.height ?? 0
      }, segment.back, root.reachAcross.near, root.reachAcross.far, root._vertical)
      x: _box.x
      y: _box.y
      width: _box.width
      height: _box.height
      tabLimits: root.tabLimitsOf(root._vertical ? y : x, root._vertical ? height : width)
    }
  }
}
