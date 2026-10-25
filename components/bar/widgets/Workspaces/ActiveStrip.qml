pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.bar
import qs.components.reusable

// What a switcher shows after its workspaces on a strip monitor: a divider
// in the bar's separator style (a line when that's none), then the active
// workspace's windows in strip order (StripWindows), cross-fading to the
// next workspace's when it changes. Nothing, divider included, while the
// workspace has none (`hasWindows`). Without `divider` (the windows shown
// alone) only the windows.
Grid {
  id: root

  required property var barConfig
  required property int workspaceId
  required property bool stripVertical
  required property real cell
  required property real cellRadius
  required property color activeColor
  required property color occupiedColor
  required property color textColor
  required property color hoverColor
  property bool clickable: true
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null
  property bool divider: true

  readonly property bool isVertical: barConfig.vertical
  readonly property bool hasWindows: CompositorManager.stripWindows(root.workspaceId, root.stripVertical).length > 0

  // Only what's shown: a Grid keeps spacing for an empty column or row
  rows: isVertical && divider ? 2 : 1
  columns: !isVertical && divider ? 2 : 1
  spacing: barConfig.widgetSpacing

  SeparatorMark {
    visible: root.divider
    style: root.barConfig.separatorStyle === "none" ? "line" : root.barConfig.separatorStyle
    color: Theme.resolveColor(root.barConfig.separatorColor)
    thickness: root.barConfig.separatorThickness
    length: root.cell * (style === "chevron" ? 0.6 : 0.5)
    vertical: root.isVertical
    width: root.isVertical ? root.cell : implicitWidth
    height: root.isVertical ? implicitHeight : root.cell
  }

  // Clipped: a longer strip fading out is held to the new one's length
  CrossFade {
    clip: true
    value: root.workspaceId
    delegate: StripWindows {
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
      clickable: root.clickable
      hitArea: root.hitArea
    }
  }
}
