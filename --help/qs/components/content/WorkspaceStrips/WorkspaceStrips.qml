pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.bar.widgets.Workspaces

// The Workspaces bar widget's popout on a strip monitor: each of the
// monitor's workspaces with windows (and the active one) as its number
// cell followed by its windows in strip order (StripWindows), one line
// per workspace across the bar. Cells are the bar's (WorkspaceCell, in its
// widget style and the widget's colors): click a number to go to that
// workspace, a window to focus it.
WorkspacePopoutPanel {
  id: root

  // From the widget's payload, beside WorkspacePopoutPanel's
  property bool stripVertical: false

  // A string, so the lines are only rebuilt when the set of workspaces
  // shown changes, not on every compositor event
  readonly property string _idsKey: CompositorManager.workspaceIds(root.output).filter(id => id === root.activeId || CompositorManager.windows.some(w => w.workspaceId === id)).join(",")
  readonly property var ids: root._idsKey === "" ? [] : root._idsKey.split(",").map(Number)

  implicitWidth: lines.implicitWidth + margins * 2

  CellContents {
    id: contents
    barConfig: root.barConfig
    properties: root.properties
    base: root.base
    thickness: root.cellSize
    restLength: root.cellLength
  }

  // Lines stacked across the bar: rows under a horizontal bar, columns
  // beside a vertical one
  Grid {
    id: lines
    rows: root.vertical ? 1 : Math.max(1, root.ids.length)
    columns: root.vertical ? Math.max(1, root.ids.length) : 1
    spacing: root.cellSpacing

    Repeater {
      // None until the payload brings the bar's style
      model: root.barConfig ? root.ids.length : 0

      Grid {
        id: line
        required property int index
        readonly property int wsId: root.ids[index] ?? 0
        readonly property bool isActive: wsId === root.activeId
        // What its cell shows, as on the bar, less app icons: its windows
        // follow it
        readonly property var shows: contents.of(wsId, "", false)
        readonly property bool _text: shows.kind === "text" || shows.kind === "name"

        rows: root.vertical ? 2 : 1
        columns: root.vertical ? 1 : 2
        spacing: root.cellSpacing

        WorkspaceCell {
          barConfig: root.barConfig
          isActive: line.isActive
          // Every workspace shown has windows or is the active one
          look: BarsConfig.workspaceCellColors(root.barConfig, root, line.isActive, true, line.shows.urgent)
          urgent: line.shows.urgent
          solid: root.solidBoxes
          pulse: root.pulse.value
          thickness: root.cellSize
          length: line._text ? line.shows.length : root.cellLength
          radius: root.radius
          hoverColor: root.hoverColor
          labels: root.properties.labels
          label: line.shows.number
          text: line._text ? line.shows.text : ""
          textPlain: line.shows.plain
          leadIcon: line.shows.kind === "text" ? line.shows.lead : ""
          leadPlain: line.shows.leadPlain
          clickable: root.properties.clickToSwitch ?? false
          animated: root._settled
          onClicked: CompositorManager.goToWorkspace(line.wsId, "go", root.output)
        }

        StripWindows {
          barConfig: root.barConfig
          workspaceId: line.wsId
          stripVertical: root.stripVertical
          isVertical: root.vertical
          thickness: root.cellSize
          cellLength: root.cellSize
          radius: root.radius
          hoverColor: root.hoverColor
          activeColor: root.activeColor
          occupiedColor: root.occupiedColor
          textColor: root.textColor
          clickable: root.properties.clickToSwitch ?? false
          animated: root._settled
          cellSpacing: root.cellSpacing
          solid: root.solidBoxes
        }
      }
    }
  }
}
