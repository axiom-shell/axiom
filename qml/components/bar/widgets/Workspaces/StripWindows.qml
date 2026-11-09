pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.services.system
import qs.components.methods

// A strip workspace's windows as bar cells (WorkspaceCell), in strip order
// (CompositorManager.stripWindows), each showing its app icon: the one
// focused last in the active look, the rest as occupied. Click one to focus
// it. Laid out along the bar; the strip switchers put it after the active
// workspace's cell, the strip popout after every workspace's. As segments
// of the bar's run (`run`: the widget's Background off) each takes the
// bar's widget shape and room for its caps, cells `chainFirst` on of the
// widget's `chainCount`.
Grid {
  id: root

  required property var barConfig
  required property int workspaceId
  // The strip's own direction, which orders the windows
  required property bool stripVertical
  // Along the bar's direction, which lays the cells out
  required property bool isVertical
  required property real thickness
  required property real cellLength
  property real radius: 0
  required property color activeColor
  required property color occupiedColor
  required property color textColor
  required property color hoverColor
  property bool clickable: true
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null
  property bool animated: true
  // Between its cells (the widget's `spacing`), and every cell a filled
  // box (`solidBoxes`), as in the workspace row
  property real cellSpacing: barConfig.innerGap
  property bool solid: false
  // The widget's place in the bar's run, its cells being segments of it
  // (Workspaces' `_run`), else null; where its cells start among the
  // widget's chained ones, and how many those are
  property var run: null
  property int chainFirst: 0
  property int chainCount: addresses.length
  // Between its cells: chained in a powerline as segments
  readonly property real _gap: run ? BarShapes.cellGap(barConfig.look.grouping, cellSpacing) : cellSpacing
  // As segments of a merged run, the cells draw a box of their own there
  // only solid or split (BarWidgetStyle.cell)
  // On the bar in a merged run, the run draws their box (BarsConfig.cellColors'
  // onBar)
  readonly property bool _inGroup: hitArea !== null && barConfig.look.grouping === "merged"
  readonly property var _traits: BarLook.cellTraits(barConfig.look, solid)
  readonly property bool _boxedInRun: _traits.cellBoxedInRun

  readonly property var windows: CompositorManager.stripWindows(root.workspaceId, root.stripVertical)
  // A string, so the cells are only rebuilt when the windows or their
  // order change, not on every compositor event
  readonly property string _key: root.windows.map(w => w.id).join(",")
  readonly property var addresses: root._key === "" ? [] : root._key.split(",")
  readonly property string focused: CompositorManager.lastFocused(root.windows)?.id ?? ""

  // Nothing (not even a gap beside it) on an empty workspace
  visible: root.addresses.length > 0
  flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
  rows: root.isVertical ? Math.max(1, root.addresses.length) : 1
  columns: root.isVertical ? 1 : Math.max(1, root.addresses.length)
  spacing: root._gap

  Repeater {
    model: root.addresses.length

    WorkspaceCell {
      id: windowCell
      required property int index
      readonly property string address: root.addresses[index] ?? ""
      readonly property var window: root.windows.find(w => w.id === address) ?? null

      barConfig: root.barConfig
      isActive: address === root.focused
      look: BarsConfig.cellColors(root.barConfig, isActive ? root.activeColor : root.occupiedColor, root.textColor, isActive ? "active" : "occupied", {
        "hovered": windowCell.lit,
        "solid": root.solid,
        "onBar": root.hitArea !== null
      })
      solid: root.solid
      thickness: root.thickness
      inRun: root._inGroup
      // Drawn over the next, which may start beneath it (BarShapes.cellSegment)
      z: -index
      shape: root.run ? BarShapes.cellShape(root.barConfig, root.run, root._boxedInRun, root._traits.cellOpaque, root._gap, root.chainFirst + index, root.chainCount) : null
      room: root.run ? BarShapes.cellRoom(root.barConfig, root.run, root._boxedInRun, root.chainFirst + index, root.chainCount) : null
      length: root.cellLength + (windowCell.room ? windowCell.room.lead + windowCell.room.trail : 0)
      radius: root.radius
      hoverColor: root.hoverColor
      iconPath: window ? AppIconManager.resolveWindowIcon(window.appId, window.title) : ""
      clickable: root.clickable
      hitArea: root.hitArea
      animated: root.animated
      onClicked: CompositorManager.focusWindow(address)
    }
  }
}
