pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.methods

// A strip workspace's windows as bar cells (WorkspaceCell), in strip order
// (CompositorManager.stripWindows), each showing its app icon: the one
// focused last in the active look, the rest as occupied. Click one to focus
// it. Laid out along the bar; the strip switchers put it after the active
// workspace's cell, the strip popout after every workspace's.
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
  spacing: root.barConfig.widgetSpacing

  Repeater {
    model: root.addresses.length

    WorkspaceCell {
      required property int index
      readonly property string address: root.addresses[index] ?? ""
      readonly property var window: root.windows.find(w => w.id === address) ?? null

      barConfig: root.barConfig
      isActive: address === root.focused
      look: BarsConfig.cellColors(root.barConfig, isActive ? root.activeColor : root.occupiedColor, root.textColor, isActive ? "active" : "occupied")
      thickness: root.thickness
      length: root.cellLength
      radius: root.radius
      hoverColor: root.hoverColor
      iconPath: window ? IconResolver.resolveWindowIcon(window.appId, window.title) : ""
      clickable: root.clickable
      hitArea: root.hitArea
      animated: root.animated
      onClicked: CompositorManager.focusWindow(address)
    }
  }
}
