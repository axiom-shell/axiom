pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.reusable
import qs.components.methods

// What a switcher shows after its workspaces on a strip monitor (loaded
// only there, shown only while the workspace has windows: `hasWindows`):
// a divider in the bar's separator style (a line when that's none), then
// the active workspace's windows in strip order, a box each
// (StripWindows) or all in one (StripWindowsBox) as `windows` says,
// cross-fading to the next workspace's when it changes. Down to one
// workspace shown (`stripOnly`), the windows show alone, without the
// divider. With `windows` off nothing loads. As segments of the bar's run
// (the widget's Background off: `run`) its boxes take the bar's widget
// shape, cells `chainFirst` on of the widget's `chainCount`, and in a
// powerline chain on from the row's with no divider.
Loader {
  id: root

  required property var barConfig
  required property int workspaceId
  // "horizontal" | "vertical" on a strip monitor, else "" (nothing loads)
  required property string stripDirection
  // How many workspaces the switcher shows
  required property int shownCount
  // The widget's `stripWindows`: "off", "each" or "one"
  required property string windows
  required property real cell
  required property real cellRadius
  required property color activeColor
  required property color occupiedColor
  required property color textColor
  required property color hoverColor
  property bool clickable: true
  // The row's (StripWindows')
  property real cellSpacing: barConfig.innerGap
  property bool solid: false
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null
  // The widget's place in the bar's run, its cells being segments of it
  // (Workspaces' `_run`), else null; where its cells start among the
  // widget's chained ones, and how many those are
  property var run: null
  property int chainFirst: 0
  property int chainCount: cells

  readonly property bool isVertical: barConfig.vertical
  readonly property bool stripVertical: stripDirection === "vertical"
  readonly property bool hasWindows: active && CompositorManager.stripWindows(root.workspaceId, root.stripVertical).length > 0
  // The strip is all there is: its windows show alone while it has any
  // (the switcher's cell stands in while it's empty)
  readonly property bool stripOnly: shownCount <= 1 && hasWindows
  // How many cells it shows: a box each, or one
  readonly property int cells: !hasWindows ? 0 : windows === "one" ? 1 : CompositorManager.stripWindows(root.workspaceId, root.stripVertical).length
  // A powerline's segments chain on from the row's, with no divider
  readonly property bool _chained: run !== null && barConfig.look.grouping === "powerline"
  readonly property bool _divided: !stripOnly && !_chained

  active: stripDirection !== "" && windows !== "off"
  visible: hasWindows

  sourceComponent: Grid {
    // Only what's shown: a Grid keeps spacing for an empty column or row
    rows: root.isVertical && root._divided ? 2 : 1
    columns: !root.isVertical && root._divided ? 2 : 1
    spacing: root.barConfig.innerGap

    SeparatorMark {
      visible: root._divided
      style: root.barConfig.look.separators.style === "none" ? "line" : root.barConfig.look.separators.style
      color: Theme.resolveColor(root.barConfig.look.separators.color)
      thickness: root.barConfig.look.separators.thickness
      length: root.cell * (style === "chevron" ? 0.6 : 0.5)
      vertical: root.isVertical
      width: root.isVertical ? root.cell : implicitWidth
      height: root.isVertical ? implicitHeight : root.cell
    }

    // Clipped: a longer strip fading out is held to the new one's length,
    // but for what its cells draw past it as segments (BarShapes.cellMargins:
    // back under the one before, a flared tab's fillets past its ends, out
    // to a tab's edge)
    MarginClip {
      readonly property var _margins: BarShapes.cellMargins(root._shapeOf(root.chainFirst), root._shapeOf(root.chainCount - 1), root.isVertical)

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

  // Between its boxes: chained in a powerline as segments
  readonly property real _gap: run ? BarShapes.cellGap(barConfig.look.grouping, cellSpacing) : cellSpacing
  // The shape of its cell at `cell` of the widget's chained ones, for what
  // its first and last draw past it (BarShapes.cellShape), or null
  function _shapeOf(cell) {
    return root.run && root.cells > 0 ? BarShapes.cellShape(root.barConfig, root.run, BarLook.cellTraits(root.barConfig.look, root.solid).boxedInRun, false, root._gap, cell, root.chainCount) : null;
  }

  Component {
    id: boxEach

    StripWindows {
      required property var value
      barConfig: root.barConfig
      workspaceId: value
      stripVertical: root.stripVertical
      isVertical: root.isVertical
      thickness: root.cell
      cellLength: root.cell
      radius: root.cellRadius
      activeColor: root.activeColor
      occupiedColor: root.occupiedColor
      textColor: root.textColor
      hoverColor: root.hoverColor
      cellSpacing: root.cellSpacing
      solid: root.solid
      clickable: root.clickable
      hitArea: root.hitArea
      run: root.run
      chainFirst: root.chainFirst
      chainCount: root.chainCount
    }
  }

  Component {
    id: oneBox

    StripWindowsBox {
      required property var value
      barConfig: root.barConfig
      workspaceId: value
      stripVertical: root.stripVertical
      isVertical: root.isVertical
      thickness: root.cell
      cellLength: root.cell
      radius: root.cellRadius
      activeColor: root.activeColor
      occupiedColor: root.occupiedColor
      textColor: root.textColor
      hoverColor: root.hoverColor
      cellSpacing: root.cellSpacing
      solid: root.solid
      clickable: root.clickable
      hitArea: root.hitArea
      run: root.run
      chainFirst: root.chainFirst
      chainCount: root.chainCount
    }
  }
}
