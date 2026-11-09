pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.reusable

// What a switcher shows after its workspaces on a strip monitor (loaded
// only there, shown only while the workspace has windows: `hasWindows`):
// a divider in the bar's separator style (a line when that's none), then
// the active workspace's windows in strip order (StripWindows),
// cross-fading to the next workspace's when it changes. Down to one
// workspace shown (`stripOnly`), the windows show alone, without the
// divider.
Loader {
  id: root

  required property var barConfig
  required property int workspaceId
  // "horizontal" | "vertical" on a strip monitor, else "" (nothing loads)
  required property string stripDirection
  // How many workspaces the switcher shows
  required property int shownCount
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

  readonly property bool isVertical: barConfig.vertical
  readonly property bool stripVertical: stripDirection === "vertical"
  readonly property bool hasWindows: active && CompositorManager.stripWindows(root.workspaceId, root.stripVertical).length > 0
  // The strip is all there is: its windows show alone while it has any
  // (the switcher's cell stands in while it's empty)
  readonly property bool stripOnly: shownCount <= 1 && hasWindows

  active: stripDirection !== ""
  visible: hasWindows

  sourceComponent: Grid {
    // Only what's shown: a Grid keeps spacing for an empty column or row
    rows: root.isVertical && !root.stripOnly ? 2 : 1
    columns: !root.isVertical && !root.stripOnly ? 2 : 1
    spacing: root.barConfig.innerGap

    SeparatorMark {
      visible: !root.stripOnly
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
        cellSpacing: root.cellSpacing
        solid: root.solid
        clickable: root.clickable
        hitArea: root.hitArea
      }
    }
  }
}
