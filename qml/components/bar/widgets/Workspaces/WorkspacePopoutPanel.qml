pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.content.base

// The root of the Workspaces widget's popouts (WorkspaceStrips,
// WorkspaceGrid): the widget's payload and the colours its cells take, as
// the bar's row has them, and their urgent fade (`pulse`).
Panel {
  id: root

  // From the widget's payload (BarPopouts copies it onto these, and the
  // widget's options onto `properties`, once the popout has loaded: until
  // then `properties` is empty, hence the few `??` in the popouts)
  // The output's name: the payload is a snapshot taken at opening, so its
  // state (the active workspace) is looked up live
  property string output: ""
  readonly property var monitor: CompositorManager.output(root.output)
  property bool vertical: false
  property real cellSize: Widget.height
  // Along the bar (narrower than cellSize for dots without a box)
  property real cellLength: cellSize
  // The bar's config, so the cells take its widget style
  property var barConfig: null
  // The bar's inner spacing, so the gaps match its row
  property real cellSpacing: Widget.spacing
  // The bar's, so the cells match its row
  property real radius: Widget.radius

  readonly property color activeColor: Theme.resolveColor(root.properties.activeColor)
  readonly property color occupiedColor: Theme.resolveColor(root.properties.occupiedColor)
  readonly property color urgentColor: Theme.resolveColor(root.properties.urgentColor)
  readonly property color emptyColor: Theme.resolveColor(root.properties.emptyColor)
  readonly property color textColor: Theme.resolveColor(root.properties.textColor)
  readonly property color hoverColor: BarsConfig.cellHoverColor(root.properties)
  // Every cell a filled box (`solidBoxes`; workspaceCellColors reads it)
  readonly property bool solidBoxes: root.properties.solidBoxes ?? false
  readonly property int base: CompositorManager.workspaceBase(root.output)
  readonly property int activeId: root.monitor?.activeWorkspaceId ?? -1

  // The payload and `properties` land just after creation (BarPopouts'
  // onLoaded), so the cells first bind to fallbacks: animate only once
  // they've settled, or the opening cells fade in from the wrong color
  property bool _settled: false

  // Every urgent cell's fade, in step
  readonly property UrgentPulse pulse: UrgentPulse {
    running: (root.properties.urgentPulse ?? false) && CompositorManager.workspaces.some(ws => ws.urgent)
  }
  Component.onCompleted: Qt.callLater(() => root._settled = true)
}
