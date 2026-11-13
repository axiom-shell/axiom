pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.components.reusable
import qs.components.methods
import qs.components.bar.look

// What a switcher shows after its workspaces on a strip monitor (loaded
// only there, shown only while the workspace has windows: `hasWindows`):
// a divider in the bar's separator style (a line when that's none), then
// the active workspace's windows in strip order, a box each
// (StripWindows) or all in one (StripWindowsBox) as `windows` says,
// cross-fading to the next workspace's when it changes. Down to one
// workspace shown (`stripOnly`), the windows show alone, without the
// divider. With `windows` off nothing loads. As segments of the bar's run
// (the widget's Background off: its cell look's `run`) its boxes take the bar's widget
// shape, cells `chainFirst` on of the widget's `chainCount`, and in a
// powerline chain on from the row's with no divider.
Loader {
  id: root

  required property var barConfig
  // How the widget's cells draw on this bar (its switcher's): their size,
  // corners, spacing, run and colors
  required property CellLook cellLook
  required property int workspaceId
  // "horizontal" | "vertical" on a strip monitor, else "" (nothing loads)
  required property string stripDirection
  // How many workspaces the switcher shows
  required property int shownCount
  // The widget's `stripWindows`: "off", "each" or "one"
  required property string windows
  property bool clickable: true
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null
  // Where its cells start among the widget's chained ones (its cells
  // being segments of the bar's run: its cell look's `run`), and how many
  // those are
  property int chainFirst: 0
  property int chainCount: cells

  readonly property bool isVertical: barConfig.vertical
  readonly property real cell: cellLook.thickness
  readonly property bool stripVertical: stripDirection === "vertical"
  // Its windows a rule doesn't hide from workspace icons
  readonly property var _strip: root.active ? WindowRulesManager.shownIn("workspaces", CompositorManager.stripWindows(root.workspaceId, root.stripVertical)) : []
  readonly property bool hasWindows: root._strip.length > 0
  // The strip is all there is: its windows show alone while it has any
  // (the switcher's cell stands in while it's empty)
  readonly property bool stripOnly: shownCount <= 1 && hasWindows
  // How many cells it shows: a box each, or one
  readonly property int cells: !hasWindows ? 0 : windows === "one" ? 1 : root._strip.length
  // A powerline's segments chain on from the row's, with no divider
  readonly property bool _chained: cellLook.run !== null && barConfig.look.grouping === "powerline"
  readonly property bool _divided: !stripOnly && !_chained

  active: stripDirection !== "" && windows !== "off"
  visible: hasWindows

  sourceComponent: Grid {
    // Only what's shown: a Grid keeps spacing for an empty column or row
    rows: root.isVertical && root._divided ? 2 : 1
    columns: !root.isVertical && root._divided ? 2 : 1
    spacing: root.barConfig.innerGap

    StripDivider {
      visible: root._divided
      barConfig: root.barConfig
      cell: root.cell
    }

    // Clipped: a longer strip fading out is held to the new one's length,
    // but for what its cells draw past it as segments (BarCells.cellMargins:
    // back under the one before, a flared tab's fillets past its ends, out
    // to a tab's edge)
    MarginClip {
      readonly property var _margins: BarCells.cellMargins(root._shapeOf(root.chainFirst), root._shapeOf(root.chainFirst + root.cells - 1), root.isVertical)

      implicitWidth: fade.implicitWidth
      implicitHeight: fade.implicitHeight
      leftMargin: _margins.left
      topMargin: _margins.top
      rightMargin: _margins.right
      bottomMargin: _margins.bottom

      CrossFade {
        id: fade
        anchors.fill: parent
        value: root.workspaceId
        delegate: root.windows === "one" ? oneBox : boxEach
      }
    }
  }

  // The shape of its cell at `cell` of the widget's chained ones, for what
  // its first and last draw past it (CellLook.shapeOf), or null
  function _shapeOf(cell) {
    return root.cells > 0 ? root.cellLook.shapeOf(cell, root.chainCount, false, root.cellLook.iconContent) : null;
  }

  Component {
    id: boxEach

    StripWindows {
      required property var value
      barConfig: root.barConfig
      cellLook: root.cellLook
      workspaceId: value
      stripVertical: root.stripVertical
      isVertical: root.isVertical
      placed: root.x + root.y
      clickable: root.clickable
      hitArea: root.hitArea
      chainFirst: root.chainFirst
      chainCount: root.chainCount
    }
  }

  Component {
    id: oneBox

    StripWindowsBox {
      required property var value
      barConfig: root.barConfig
      cellLook: root.cellLook
      workspaceId: value
      stripVertical: root.stripVertical
      isVertical: root.isVertical
      placed: root.x + root.y
      clickable: root.clickable
      hitArea: root.hitArea
      chainFirst: root.chainFirst
      chainCount: root.chainCount
    }
  }
}
