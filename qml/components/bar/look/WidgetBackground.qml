pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods

// What a bar widget sits on, in its bar's look (barConfig.look), composed of
// the look's pieces: its box and line (LookBox), split's icon part
// (SplitPart), a level (LevelFill), and over them a press's tint, the bar
// editor's highlight and the hover outline (ShapeOverlay), each in the
// shape its caps give (BarShapes). A tab (the look's shape tab) is set
// reaching out to the edge it hangs from by its WidgetGroup, which hands it
// what bounds its ends (`tabLimits`). WidgetGroup draws one under each
// widget with a background, and one under each merged run.
Item {
  id: root

  required property var barConfig
  // The colors to draw in (BarsConfig.widgetColors), or null for none
  property var colors: null
  property string startCap: "round"
  property string endCap: "round"
  // The start as it shows (BarShapes.segment): the hover outline and the
  // highlight trace what's in view, inside it, not the part a powerline
  // neighbour covers
  property string shownStart: startCap
  // Ends that meet a powerline neighbour edge to edge (BarShapes.segment)
  property bool seamStart: false
  property bool seamEnd: false
  // Ends a merged run carries on past into the next section's, drawn
  // apart (WidgetGroup): no line across them (BarOutlines.path's open ends)
  property bool openStart: false
  property bool openEnd: false
  // A clickable widget under the pointer (its hoverOutline)
  property bool hovered: false
  // A clickable widget being pressed: a tint in its shape
  property bool pressed: false
  // The bar editor's selected widget
  property bool highlighted: false
  // A level (0-1) filled in its shape along the bar, up a vertical one
  // (the module's `backgroundLevel`); -1 for none
  property real backgroundLevel: -1
  property color backgroundLevelColor: "transparent"
  // The caps the level is drawn in (BarShapes.segment's levelStartCap /
  // levelEndCap): in a merged run the widget's own, not the run's
  property string levelStartCap: startCap
  property string levelEndCap: endCap
  // Where it starts and ends along its bar (0-1), for the bar's gradient,
  // or -1 for none (WidgetGroup, from where it's laid out)
  property real gradientStart: -1
  property real gradientEnd: -1

  // A split widget's parts (BarWidgetHost.split): along it, the middle of
  // the gap between its icon part and its label, -1 when it doesn't split;
  // what the icon part holds, in its coordinates
  property real splitAt: -1
  property rect splitPart: Qt.rect(0, 0, 0, 0)

  // What bounds a tab's ends along the bar (BarTabs.tabLimits)
  property var tabLimits: [null, null]

  // Its widget draws its own parts as segments of the run (BarWidget's
  // `segmented`: Workspaces' cells with its Background off): no box of its
  // own, only its states (the press, the hover outline, the highlight)
  property bool bare: false

  readonly property var _look: barConfig.look
  // A tab's shape (BarTabs.tab), or null
  readonly property var _tab: BarTabs.barTab(barConfig, tabLimits)
  // What a press tints: in a merged run, a widget filling its own part
  // (on hover) in the caps it has alone
  readonly property var _pressCaps: BarShapes.pressCaps({
    "shownStart": root.shownStart,
    "endCap": root.endCap,
    "levelStartCap": root.levelStartCap,
    "levelEndCap": root.levelEndCap
  }, root._look.grouping, root.colors !== null && Qt.color(root.colors.fill).a > 0)
  // What of it draws the bar's gradient (its colors' `gradient`: its fill,
  // stroke, line or split's icon part), and the slice of it from `from`
  // to `to` along it (0-1), else null
  readonly property string _gradientPart: root.gradientStart >= 0 ? (root.colors?.gradient?.part ?? "") : ""
  function _sliceOf(from, to) {
    const stops = root.barConfig.palette.gradientStops;
    if (root._gradientPart === "" || stops === null)
      return null;
    const span = root.gradientEnd - root.gradientStart;
    return BarGradient.gradientSlice(stops, root.gradientStart + span * from, root.gradientStart + span * to, root.colors.gradient.alpha);
  }
  readonly property var _slice: root._sliceOf(0, 1)
  readonly property real _along: barConfig.vertical ? height : width

  // Its box (the level's caps: the widget's own, but in a merged run the
  // ones it has alone, where only a widget filled on hover draws anything;
  // the run draws the rest) and the look's line
  LookBox {
    visible: root.colors !== null
    bar: root.barConfig
    boxed: root._look.traits.boxed && !root.bare
    outline: ({
        "startCap": root.levelStartCap,
        "endCap": root.levelEndCap,
        "seamStart": root.seamStart,
        "seamEnd": root.seamEnd,
        "openStart": root.openStart,
        "openEnd": root.openEnd,
        "tab": root._tab
      })
    fill: root.colors?.fill ?? "transparent"
    stroke: root.colors?.stroke ?? "transparent"
    line: root.colors?.indicator ?? "transparent"
    strokeWidth: root._look.outline?.width ?? 0
    strokeStyle: root._look.outline?.stroke ?? "solid"
    fillSlice: root._gradientPart === "fill" ? root._slice : null
    strokeSlice: root._gradientPart === "stroke" ? root._slice : null
    lineSlice: root._gradientPart === "indicator" ? root._slice : null
  }

  SplitPart {
    visible: root.colors !== null
    bar: root.barConfig
    at: root.splitAt
    part: root.splitPart
    startCap: root.startCap
    tab: root._tab
    color: root.colors?.iconFill ?? "transparent"
    // Its own slice, along it from `start` for `length`
    sliceOf: (start, length) => root._gradientPart === "iconFill" && root._along > 0 ? root._sliceOf(start / root._along, (start + length) / root._along) : null
  }

  LevelFill {
    bar: root.barConfig
    level: root.backgroundLevel
    color: root.backgroundLevelColor
    startCap: root.levelStartCap
    endCap: root.levelEndCap
    seamStart: root.seamStart
    seamEnd: root.seamEnd
    tab: root._tab
  }

  // A press
  ShapeOverlay {
    shown: root._look.traits.boxed
    bar: root.barConfig
    tab: root._tab
    startCap: root._pressCaps.start
    endCap: root._pressCaps.end
    fill: Qt.alpha(root.colors?.text ?? Theme.foreground, root.pressed && root.colors !== null ? 0.2 : 0)
  }

  // The bar editor's highlight
  ShapeOverlay {
    shown: root.highlighted
    bar: root.barConfig
    tab: root._tab
    startCap: root.shownStart
    endCap: root.endCap
    fill: Qt.alpha(Theme.accent, 0.15)
    stroke: Theme.accent
    strokeWidth: 2
    glides: false
  }

  // The hover outline
  ShapeOverlay {
    bar: root.barConfig
    tab: root._tab
    startCap: root.shownStart
    endCap: root.endCap
    stroke: root.hovered ? Theme.border : Qt.alpha(Theme.border, 0)
    strokeWidth: Appearance.borderWidth
    duration: Appearance.animNormal
  }
}
