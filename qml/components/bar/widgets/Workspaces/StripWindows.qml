pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.services.system
import qs.components.bar.look

// A strip workspace's windows as bar cells (WorkspaceCell), in strip order
// (CompositorManager.stripWindows), each showing its app icon: the one
// focused last in the active look, the rest as occupied. Click one to focus
// it. Laid out along the bar; the strip switchers put it after the active
// workspace's cell, the strip popout after every workspace's. As segments
// of the bar's run (its cell look's `run`: the widget's Background off)
// each takes the bar's widget shape and room for its caps, cells
// `chainFirst` on of the widget's `chainCount`.
Grid {
  id: root

  required property var barConfig
  // How the widget's cells draw on this bar or popout: their size,
  // corners, spacing and colors
  required property CellLook cellLook
  required property int workspaceId
  // The strip's own direction, which orders the windows
  required property bool stripVertical
  // Along the bar's direction, which lays the cells out
  required property bool isVertical
  required property color activeColor
  required property color occupiedColor
  required property color textColor
  property bool clickable: true
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null
  property bool animated: true
  // Where its cells start among the widget's chained ones, and how many
  // those are
  property int chainFirst: 0
  property int chainCount: addresses.length

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
  // Between its cells: chained in a powerline as segments
  spacing: root.cellLook.gap

  Repeater {
    model: root.addresses.length

    WorkspaceCell {
      id: windowCell
      required property int index
      readonly property string address: root.addresses[index] ?? ""
      readonly property var window: root.windows.find(w => w.id === address) ?? null

      barConfig: root.barConfig
      cellLook: root.cellLook
      isActive: address === root.focused
      look: root.cellLook.colorsOf(isActive ? root.activeColor : root.occupiedColor, root.textColor, isActive ? "active" : "occupied", {
        "hovered": windowCell.lit
      })
      thickness: root.cellLook.thickness
      // Drawn over the next, which may start beneath it (BarCells.cellSegment)
      z: -index
      shape: root.cellLook.shapeOf(root.chainFirst + index, root.chainCount, root.cellLook.opaque, root.cellLook.iconContent)
      room: root.cellLook.roomOf(root.chainFirst + index, root.chainCount, root.cellLook.iconContent)
      length: root.cellLook.thickness + (windowCell.room ? windowCell.room.lead + windowCell.room.trail : 0)
      iconPath: window ? AppIconManager.resolveWindowIcon(window.appId, window.title) : ""
      clickable: root.clickable
      hitArea: root.hitArea
      animated: root.animated
      onClicked: CompositorManager.focusWindow(address)
    }
  }
}
