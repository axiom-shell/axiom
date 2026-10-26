pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.ui
import qs.components.methods

// A thin hover strip on a screen edge that fires `triggered` once the
// pointer has rested on it for `hoverDelay`
PanelWindow {
  id: root

  signal triggered

  readonly property alias containsMouse: mouseArea.containsMouse

  // A ScreenEdge value, shared with bars and popouts
  property int edge: ScreenEdge.Right
  // Along the edge: 0-1 of the free length, plus pixels
  property real position: 0.5
  property real positionOffset: 0

  // Depth across the edge, and length along it
  property int triggerWidth: PopoutsConfig.edgeTriggerSize
  property int triggerLength: 200 // fixed px: a hover strip on the screen's edge, like edgeTriggerSize
  property int hoverDelay: PopoutsConfig.openDelay

  // Integrated edge menus' zones (ScreenEdgeManager) move the surfaces this
  // triggers inwards, so the trigger follows: past a zone on its own edge,
  // and along it as the edge's free length shrinks from either end
  readonly property bool _vertical: root.edge === ScreenEdge.Left || root.edge === ScreenEdge.Right
  property real edgeInset: ScreenEdgeManager.zoneOn(root.screen?.name ?? "", ScreenEdge.name(root.edge))
  property real startInset: ScreenEdgeManager.zoneOn(root.screen?.name ?? "", root._vertical ? "top" : "left")
  property real endInset: ScreenEdgeManager.zoneOn(root.screen?.name ?? "", root._vertical ? "bottom" : "right")
  // Its centre along the edge in screen px, overriding the above (NaN:
  // from `position`)
  property real centre: NaN
  // The trigger's centre along the edge, within the free length
  readonly property real _centre: !isNaN(root.centre) ? root.centre : root.startInset + ((root._vertical ? root.screen?.height ?? 0 : root.screen?.width ?? 0) - root.startInset - root.endInset) * root.position + root.positionOffset

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  // Anchor the attach edge, plus both sides of the perpendicular axis: a
  // wlr-layer-shell margin only takes effect on an anchored edge, and
  // positioning along the edge (the margins below) needs both anchored,
  // not just one, else the surface centers itself.
  anchors {
    left: root.edge !== ScreenEdge.Right
    right: root.edge !== ScreenEdge.Left
    top: root.edge !== ScreenEdge.Bottom
    bottom: root.edge !== ScreenEdge.Top
  }

  implicitWidth: root._vertical ? root.triggerWidth : root.triggerLength
  implicitHeight: root._vertical ? root.triggerLength : root.triggerWidth

  margins {
    left: root.edge === ScreenEdge.Left ? root.edgeInset : root._vertical ? 0 : Math.max(0, root._centre - root.triggerLength / 2)
    right: root.edge === ScreenEdge.Right ? root.edgeInset : root._vertical ? 0 : Math.max(0, (root.screen?.width ?? 0) - root._centre - root.triggerLength / 2)
    top: root.edge === ScreenEdge.Top ? root.edgeInset : !root._vertical ? 0 : Math.max(0, root._centre - root.triggerLength / 2)
    bottom: root.edge === ScreenEdge.Bottom ? root.edgeInset : !root._vertical ? 0 : Math.max(0, (root.screen?.height ?? 0) - root._centre - root.triggerLength / 2)
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: hoverTimer.restart()
    onExited: hoverTimer.stop()
  }

  Timer {
    id: hoverTimer
    interval: root.hoverDelay
    onTriggered: {
      if (mouseArea.containsMouse)
        root.triggered();
    }
  }
}
