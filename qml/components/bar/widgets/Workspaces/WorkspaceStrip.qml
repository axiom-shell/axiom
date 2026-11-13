pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.reusable
import qs.components.hosts.popout
import qs.components.bar.look

// The standard layout's switcher: workspaces 1..count in a row (horizontal
// bar) or column (vertical bar), or the ones the compositor has where it
// makes them itself (CompositorManager.dynamicWorkspaces); click one to go
// there, scroll to step through them. Without `showEmpty`, and always with
// dynamic workspaces, only those with windows and the active one show. On
// a strip monitor the active workspace's windows follow the workspaces in
// strip order (ActiveStrip), scrolling scrolls the strip, and the popout
// shows every workspace's strip; down to one workspace, its windows show
// alone.
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
  // The cells chained in it: the row's, then the strip's windows'
  readonly property int _rowCells: activeStrip.stripOnly ? 0 : root.ids.length
  readonly property int _chainCells: root._rowCells + (activeStrip.visible ? activeStrip.cells : 0) + (specialCells.visible ? specialCells.cells : 0)

  readonly property bool isVertical: barConfig.vertical

  readonly property var monitor: CompositorManager.outputFor(root.screen)
  readonly property string output: root.monitor?.name ?? ""
  readonly property int activeId: root.monitor?.activeWorkspaceId ?? -1
  readonly property int base: CompositorManager.workspaceBase(root.output)
  // "horizontal" | "vertical" on a strip monitor, else ""
  readonly property string stripDirection: CompositorManager.stripDirection(root.screen?.name ?? "")
  // Only workspaces with windows and the active one: without `showEmpty`,
  // and where the compositor's empty one at the end is only for opening
  readonly property bool _hideEmpty: !root.properties.showEmpty || CompositorManager.dynamicWorkspaces

  // A string, so the cells are only rebuilt when the set of workspaces
  // shown changes, not on every compositor event
  readonly property string _idsKey: {
    const ids = [];
    for (const id of CompositorManager.workspaceIds(root.output)) {
      const ws = CompositorManager.workspaces.find(ws => ws.id === id);
      if (root.properties.monitorOnly && ws?.output && root.output && ws.output !== root.output)
        continue;
      if (root._hideEmpty && id !== root.activeId && (ws?.windowCount ?? 0) === 0)
        continue;
      ids.push(id);
    }
    return ids.join(",");
  }
  readonly property var ids: root._idsKey === "" ? [] : root._idsKey.split(",").map(Number)

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  // Next/previous shown workspace, wrapping at the ends
  function step(direction) {
    if (root.ids.length === 0)
      return;
    const current = root.ids.indexOf(root.activeId);
    const next = current < 0 ? (direction > 0 ? 0 : root.ids.length - 1) : (current + direction + root.ids.length) % root.ids.length;
    if (current >= 0 && next !== current + direction)
      cellRow.expectWrap(direction > 0);
    CompositorManager.goToWorkspace(root.ids[next], "go", root.output);
  }

  Connections {
    target: CompositorManager
    function onWorkspaceWrapped(output, alongRow, forward) {
      if (output === root.output)
        cellRow.expectWrap(forward);
    }
  }

  // `scrollReverse` turns the wheel's direction round, for the strip too
  NotchWheel {
    enabled: root.properties.scrollToSwitch
    onStepped: direction => {
      const step = root.properties.scrollReverse ? -direction : direction;
      if (root.stripDirection !== "")
        CompositorManager.stepStrip(step, root.output);
      else
        root.step(step);
    }
  }

  Grid {
    id: layout
    anchors.centerIn: parent
    // -1: as many as are shown (a Grid keeps spacing for an empty column
    // or row), counted by the Grid itself, so it can't lag a part showing.
    // Each 1 waits for the other to leave it, so a bar turning never makes
    // it 1 by 1
    rows: !root.isVertical && columns === -1 ? 1 : -1
    columns: root.isVertical && rows === -1 ? 1 : -1
    // A powerline's segments chain on into the strip
    spacing: root.cellLook.partGap

    WorkspaceCellRow {
      id: cellRow
      // Over the strip, whose first segment may start beneath its last
      z: 1
      visible: !activeStrip.stripOnly
      barConfig: root.barConfig
      properties: root.properties
      cellLook: root.cellLook
      monitor: root.monitor
      base: root.base
      ids: root.ids
      activeId: root.activeId
      hitArea: root.hitArea
      activeIcons: root.properties.activeWorkspaceIcons || !activeStrip.visible
      chainCount: root._chainCells
    }

    ActiveStrip {
      id: activeStrip
      barConfig: root.barConfig
      cellLook: root.cellLook
      workspaceId: root.activeId
      stripDirection: root.stripDirection
      shownCount: root.ids.length
      windows: root.properties.stripWindows
      clickable: root.properties.clickToSwitch
      hitArea: root.hitArea
      chainFirst: root._rowCells
      chainCount: root._chainCells
    }

    SpecialCells {
      id: specialCells
      barConfig: root.barConfig
      properties: root.properties
      cellLook: root.cellLook
      monitorName: root.output
      hitArea: root.hitArea
      chainFirst: root._rowCells + (activeStrip.visible ? activeStrip.cells : 0)
      chainCount: root._chainCells
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WorkspaceStrips"
    active: root.stripDirection !== "" && (CompositorManager.dynamicWorkspaces ? root.ids.length > 1 : WorkspacesConfig.size > 1) && MenusConfig.opensOwnPopout(root.properties)
    extraData: ({
        output: root.output,
        vertical: root.isVertical,
        stripVertical: root.stripDirection === "vertical",
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
