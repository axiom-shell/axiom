pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.services.system
import qs.components.content.base
import qs.components.bar.widgets.Workspaces
import qs.components.reusable

// The Workspaces bar widget's popout in the grid layout: the monitor's
// whole columns × rows grid, with the row (or column, on a vertical bar)
// the bar shows at full strength. Cells are the bar's (WorkspaceCell, in its
// widget style, with the widget's colors, labels, app icons and click to
// switch), so it reads as the bar row expanded.
Panel {
  id: root

  // From the widget's payload (BarPopouts copies it onto these, and the
  // widget's options onto `properties`, once the popout has loaded: until
  // then `properties` is empty, hence the few `??` below)
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
  property int fontSize: Appearance.fontSize

  readonly property color activeColor: Theme.resolveColor(root.properties.activeColor)
  readonly property color occupiedColor: Theme.resolveColor(root.properties.occupiedColor)
  readonly property color emptyColor: Theme.resolveColor(root.properties.emptyColor)
  readonly property color textColor: Theme.resolveColor(root.properties.textColor)
  readonly property color hoverColor: BarsConfig.cellHoverColor(root.properties)
  readonly property int base: CompositorManager.workspaceBase(root.output)
  // Not `cols`/`rows`: those are Panel's slot size
  readonly property int gridColumns: WorkspacesConfig.columns
  readonly property int gridRows: WorkspacesConfig.rows
  readonly property int activeId: root.monitor?.activeWorkspaceId ?? -1
  readonly property int activeIndex: {
    const index = root.activeId - root.base;
    return index >= 0 && index < root.gridColumns * root.gridRows ? index : 0;
  }

  implicitWidth: grid.implicitWidth + margins * 2

  // The payload and `properties` land just after creation (BarPopouts'
  // onLoaded), so the cells first bind to fallbacks: animate only once
  // they've settled, or the opening cells fade in from the wrong color
  property bool _settled: false
  Component.onCompleted: Qt.callLater(() => root._settled = true)

  function wsById(id) {
    return CompositorManager.workspaces.find(ws => ws.id === id) ?? null;
  }

  Grid {
    id: grid
    columns: root.gridColumns
    spacing: root.cellSpacing

    Repeater {
      // None until the payload brings the bar's style
      model: root.barConfig ? root.gridColumns * root.gridRows : 0

      WorkspaceCell {
        id: wsCell
        required property int index

        readonly property int wsId: root.base + index
        readonly property var workspace: root.wsById(wsId)
        readonly property bool hasWindows: (workspace?.windowCount ?? 0) > 0
        // In the row (or column) the bar shows
        readonly property bool inBar: root.vertical ? index % root.gridColumns === root.activeIndex % root.gridColumns : Math.floor(index / root.gridColumns) === Math.floor(root.activeIndex / root.gridColumns)
        readonly property var windowData: root.properties.showAppIcons && hasWindows ? CompositorManager.biggestWindowForWorkspace(wsId) : null

        barConfig: root.barConfig
        isActive: wsId === root.activeId
        look: BarsConfig.cellColors(root.barConfig, isActive ? root.activeColor : hasWindows ? root.occupiedColor : root.emptyColor, isActive || hasWindows ? root.textColor : Theme.foreground, isActive ? "active" : hasWindows ? "occupied" : "empty")
        thickness: root.cellSize
        length: root.cellLength
        radius: root.radius
        hoverColor: root.hoverColor
        labels: root.properties.labels
        // The workspace id, or its place in the grid counted from 1, as on the bar
        label: root.properties.relativeNumbers ? index + 1 : wsId
        iconPath: windowData ? AppIconManager.resolveWindowIcon(windowData.appId, windowData.title) : ""
        clickable: root.properties.clickToSwitch ?? false
        animated: root._settled
        opacity: inBar ? 1.0 : 0.85
        onClicked: CompositorManager.goToWorkspace(wsId, "go", root.output)

        Glide on opacity {
          enabled: root._settled
          duration: Appearance.animNormal
        }
      }
    }
  }
}
