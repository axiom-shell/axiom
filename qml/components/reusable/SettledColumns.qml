pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// Columns that settle: units placed by ColumnSplit, their splits followed while settling (after a build, a resize or relayout()) and fixed once no split height has changed for a quiet spell, so a unit folding later never moves across columns.
QtObject {
  id: root

  // Each unit's live height, by index
  property var heights: []
  // The heights the splits are made from (a unit's height as if every fold
  // were open); the live ones by default
  property var splitHeights: root.heights
  // Which units span every column (from the schema only)
  property var wide: []
  // Which units start a run of columns
  property var starts: []
  property int count: 1
  property real gap: 0
  // A run with fewer units than columns widens (the page's cards), or
  // keeps the column width (a card's rows)
  property bool fill: true
  property bool settling: true
  // Each run's split, fixed once settled
  property var splits: []

  readonly property var placed: ColumnSplit.placeN(root.heights, root.wide, root.splits, root.count, root.gap, root.starts, root.fill)

  // The splits are fixed
  signal settled

  // Records a unit's live height
  function setHeight(i, height) {
    if (root.heights[i] === height)
      return;
    const next = root.heights.slice();
    next[i] = height;
    root.heights = next;
  }

  // Follows the heights again until they stop changing
  function relayout() {
    root.settling = true;
    root._follow();
  }

  onSplitHeightsChanged: root._follow()
  onWideChanged: root._follow()
  onStartsChanged: root._follow()
  onCountChanged: root.relayout()

  function _follow() {
    if (!root.settling)
      return;
    root.splits = ColumnSplit.splitsN(root.splitHeights, root.wide, root.count, root.gap, root.starts);
    root._quiet.restart();
  }

  // A quiet spell, restarted by every change: a behaviour timing, not an
  // animation (animNormal is 0 with motion off)
  readonly property Timer _quiet: Timer {
    interval: 150
    running: true
    onTriggered: {
      root.settling = false;
      root.settled();
    }
  }
}
