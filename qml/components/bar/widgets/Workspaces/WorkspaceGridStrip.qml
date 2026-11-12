pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.reusable
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.look

// The grid layout's switcher: this monitor's columns × rows workspaces, of
// which the bar shows the active row (horizontal bar) or column (vertical
// bar), and the popout the whole grid. As in the standard layout's
// switcher, the active cell is twice as long with `wideActive`, and on a
// strip monitor the active workspace's windows follow in strip order
// (ActiveStrip), where scrolling scrolls the strip. Moving to another row
// (column) cross-fades the bar's to it. Without `showEmpty` a row shows
// only its workspaces with windows and the active one; down to that one on
// a strip monitor, its windows show alone.
Item {
  id: root
  property var screen
  // The widget's (BarWidget.hitArea), which its popout reads hover from
  property var hitArea: null
  property var barConfig
  property var properties
  // How the widget's cells draw on this bar (Workspaces'): their size
  // inside its box, corners, spacing, colors, and its place in the bar's
  // run where they're segments of it
  required property CellLook cellLook
  // The strip's windows chained after a row's cells
  readonly property int _stripCells: activeStrip.visible ? activeStrip.cells : 0
  // The scratchpads' cells chained after those
  readonly property int _scratchCells: scratchpads.visible ? scratchpads.cells : 0

  readonly property bool isVertical: barConfig.vertical

  readonly property var monitor: CompositorManager.outputFor(root.screen)
  readonly property string output: root.monitor?.name ?? ""
  readonly property int base: CompositorManager.workspaceBase(root.output)
  readonly property int columns: WorkspacesConfig.columns
  readonly property int rows: WorkspacesConfig.rows
  readonly property int activeId: root.monitor?.activeWorkspaceId ?? -1
  // "horizontal" | "vertical" on a strip monitor, else ""
  readonly property string stripDirection: CompositorManager.stripDirection(root.screen?.name ?? "")
  // The row (column on a vertical bar) the bar shows: the active
  // workspace's, the first when the monitor is outside the grid
  readonly property var _position: GridPosition.line(root.activeId, root.base, root.columns, root.rows, root.isVertical)
  readonly property int activeLine: root._position.line

  // Between the row and the strip after it (a powerline's segments chain
  // on into it)
  readonly property real spacing: root.cellLook.partGap
  // Cells the bar shows: a row, or a column on a vertical bar
  readonly property int shown: root.isVertical ? root.rows : root.columns

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  // The workspaces row (column on a vertical bar) `line` shows, with
  // `activeId` active: every one, or without `showEmpty` those with
  // windows and the active one
  function lineIds(line, activeId) {
    const all = Array.from({
      "length": root.shown
    }, (_, i) => root.base + (root.isVertical ? i * root.columns + line : line * root.columns + i));
    if (root.properties.showEmpty)
      return all;
    const occupied = CompositorManager.workspaces.filter(ws => ws.windowCount > 0).map(ws => ws.id);
    return all.filter(id => id === activeId || occupied.includes(id));
  }

  // A workspace's place in the grid, or -1 outside it
  function placeOf(id) {
    const place = id - root.base;
    return place >= 0 && place < root.columns * root.rows ? place : -1;
  }

  // `scrollReverse` turns the wheel's direction round, for the strip too
  NotchWheel {
    enabled: root.properties.scrollToSwitch
    onStepped: direction => {
      const step = root.properties.scrollReverse ? -direction : direction;
      if (root.stripDirection !== "")
        CompositorManager.stepStrip(step, root.output);
      else
        CompositorManager.stepWorkspace(root.isVertical ? (step > 0 ? "down" : "up") : (step > 0 ? "right" : "left"), "go");
    }
  }

  Grid {
    id: layout
    // Only what's shown: a Grid keeps spacing for an empty column or row
    readonly property int shown: Math.max(1, (activeStrip.stripOnly ? 0 : 1) + (activeStrip.visible ? 1 : 0) + (scratchpads.visible ? 1 : 0))
    rows: root.isVertical ? shown : 1
    columns: root.isVertical ? 1 : shown
    spacing: root.spacing

    // The active row (or column) of the grid, over the strip, whose first
    // segment may start beneath its last
    CrossFade {
      z: 1
      visible: !activeStrip.stripOnly
      value: root.activeLine
      delegate: shownLine
    }

    ActiveStrip {
      id: activeStrip
      barConfig: root.barConfig
      cellLook: root.cellLook
      workspaceId: root.activeId
      stripDirection: root.stripDirection
      shownCount: root.lineIds(root.activeLine, root.activeId).length
      windows: root.properties.stripWindows
      clickable: root.properties.clickToSwitch
      hitArea: root.hitArea
      chainFirst: activeStrip.stripOnly ? 0 : root.lineIds(root.activeLine, root.activeId).length
      chainCount: chainFirst + root._stripCells + root._scratchCells
    }

    ScratchpadCells {
      id: scratchpads
      barConfig: root.barConfig
      properties: root.properties
      cellLook: root.cellLook
      monitorName: root.output
      hitArea: root.hitArea
      chainFirst: activeStrip.chainFirst + root._stripCells
      chainCount: chainFirst + root._scratchCells
    }
  }

  // A row (column) of the grid
  Component {
    id: shownLine

    WorkspaceCellRow {
      id: line
      // The row (column)
      required property var value
      // The active workspace while it's in this line or outside the grid:
      // a line fading out keeps showing the one it had (`_kept`)
      readonly property bool _holds: {
        const place = root.placeOf(root.activeId);
        return place < 0 || (root.isVertical ? place % root.columns : Math.floor(place / root.columns)) === line.value;
      }
      property int _kept: -1
      readonly property int _activeHere: _holds ? root.activeId : _kept
      on_ActiveHereChanged: _kept = _activeHere
      Component.onCompleted: _kept = _activeHere
      // A string, so the cells are only rebuilt when the set shown changes
      readonly property string _idsKey: root.lineIds(line.value, line._activeHere).join(",")

      barConfig: root.barConfig
      properties: root.properties
      cellLook: root.cellLook
      monitor: root.monitor
      base: root.base
      ids: line._idsKey === "" ? [] : line._idsKey.split(",").map(Number)
      activeId: _activeHere
      hitArea: root.hitArea
      activeIcons: root.properties.activeWorkspaceIcons || !activeStrip.visible
      chainCount: line.ids.length + root._stripCells + root._scratchCells

      Connections {
        target: CompositorManager
        function onWorkspaceWrapped(output, alongRow, forward) {
          if (output === root.output && alongRow !== root.isVertical)
            line.expectWrap(forward);
        }
      }
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WorkspaceGrid"
    active: WorkspacesConfig.size > 1 && MenusConfig.opensOwnPopout(root.properties)
    extraData: ({
        output: root.output,
        vertical: root.isVertical,
        // The cells' own size and corners, as on the bar
        cellSize: root.cellLook.thickness,
        cellLength: root.cellLook.length,
        barConfig: root.barConfig,
        cellSpacing: root.cellLook.spacing,
        radius: root.cellLook.radius,
        properties: root.properties
      })
  }
}
