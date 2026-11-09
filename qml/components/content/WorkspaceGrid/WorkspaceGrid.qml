pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.bar.widgets.Workspaces
import qs.components.reusable

// The Workspaces bar widget's popout in the grid layout: the monitor's
// whole columns × rows grid, with the row (or column, on a vertical bar)
// the bar shows at full strength. Cells are the bar's (WorkspaceCell, in its
// widget style, with the widget's colors, labels, app icons and click to
// switch), so it reads as the bar row expanded.
WorkspacePopoutPanel {
  id: root

  // Not `cols`/`rows`: those are Panel's slot size
  readonly property int gridColumns: WorkspacesConfig.columns
  readonly property int gridRows: WorkspacesConfig.rows
  readonly property int activeIndex: {
    const index = root.activeId - root.base;
    return index >= 0 && index < root.gridColumns * root.gridRows ? index : 0;
  }

  implicitWidth: grid.implicitWidth + margins * 2

  CellContents {
    id: contents
    barConfig: root.barConfig
    properties: root.properties
    base: root.base
    thickness: root.cellSize
    restLength: root.cellLength
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
        readonly property bool hasWindows: (CompositorManager.workspaces.find(ws => ws.id === wsId)?.windowCount ?? 0) > 0
        // In the row (or column) the bar shows
        readonly property bool inBar: root.vertical ? index % root.gridColumns === root.activeIndex % root.gridColumns : Math.floor(index / root.gridColumns) === Math.floor(root.activeIndex / root.gridColumns)
        // What it shows, as on the bar (its number is its place in the
        // grid counted from 1 with relative numbers)
        readonly property var shows: contents.of(wsId, "", true)

        barConfig: root.barConfig
        cellLook: root.cellLook
        isActive: wsId === root.activeId
        look: root.cellLook.workspaceColorsOf(root, isActive, hasWindows, shows.urgent, {
          "hovered": wsCell.lit
        })
        urgent: shows.urgent
        pulse: root.pulse.value
        urgentColor: root.urgentColor
        thickness: root.cellSize
        length: shows.length
        labels: root.properties.labels
        label: shows.number
        text: shows.kind === "text" || shows.kind === "name" ? shows.text : ""
        textPlain: shows.plain
        leadIcon: shows.kind === "text" ? shows.lead : ""
        leadPlain: shows.leadPlain
        iconPaths: shows.icons
        iconLayout: contents.iconLayout
        iconSlots: contents.iconSlots
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
