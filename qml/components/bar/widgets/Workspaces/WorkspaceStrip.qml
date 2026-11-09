pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.reusable
import qs.components.hosts.popout

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
  // Where a point of its active cell sits along the bar, for the bar's
  // gradient (BarWidget.barSpotOf), or null
  property var barSpotOf: null
  property var barConfig
  property var properties
  // Room kept to the widget's background across the bar
  property real inset: 0

  readonly property bool isVertical: barConfig.vertical
  // A cell's thickness across the bar, and its corners within the
  // background's
  readonly property real cell: barConfig.thickness - inset * 2
  readonly property real cellRadius: BarsConfig.cellRadius(barConfig, cell, inset)
  // Along the bar: square, or narrower for dots straight on the bar
  readonly property real cellLength: barConfig.widgetBoxed || properties.labels !== "dots" || properties.showAppIcons || CompositorManager.dynamicWorkspaces ? cell : Math.round(cell * 0.6)

  readonly property color activeColor: Theme.resolveColor(properties.activeColor)
  readonly property color occupiedColor: Theme.resolveColor(properties.occupiedColor)
  readonly property color emptyColor: Theme.resolveColor(properties.emptyColor)
  readonly property color textColor: Theme.resolveColor(properties.textColor)
  readonly property color hoverColor: BarsConfig.cellHoverColor(properties)

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

  NotchWheel {
    enabled: root.properties.scrollToSwitch
    onStepped: direction => {
      if (root.stripDirection !== "")
        CompositorManager.stepStrip(direction, root.output);
      else
        root.step(direction);
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
    spacing: root.barConfig.innerGap

    WorkspaceCellRow {
      id: cellRow
      visible: !activeStrip.stripOnly
      barConfig: root.barConfig
      properties: root.properties
      monitor: root.monitor
      base: root.base
      ids: root.ids
      activeId: root.activeId
      cell: root.cell
      cellLength: root.cellLength
      cellRadius: root.cellRadius
      activeColor: root.activeColor
      occupiedColor: root.occupiedColor
      emptyColor: root.emptyColor
      textColor: root.textColor
      hitArea: root.hitArea
      barSpotOf: root.barSpotOf
      hoverColor: root.hoverColor
    }

    ActiveStrip {
      id: activeStrip
      barConfig: root.barConfig
      workspaceId: root.activeId
      stripDirection: root.stripDirection
      shownCount: root.ids.length
      cell: root.cell
      cellRadius: root.cellRadius
      activeColor: root.activeColor
      occupiedColor: root.occupiedColor
      textColor: root.textColor
      hoverColor: root.hoverColor
      clickable: root.properties.clickToSwitch
      hitArea: root.hitArea
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WorkspaceStrips"
    active: root.stripDirection !== "" && (CompositorManager.dynamicWorkspaces ? root.ids.length > 1 : WorkspacesConfig.size > 1) && EdgeMenusConfig.opensOwnPopout(root.properties)
    extraData: ({
        output: root.output,
        vertical: root.isVertical,
        stripVertical: root.stripDirection === "vertical",
        // The cells' own size and corners, as on the bar
        cellSize: root.cell,
        cellLength: root.cellLength,
        barConfig: root.barConfig,
        cellSpacing: root.barConfig.innerGap,
        radius: root.cellRadius,
        properties: root.properties
      })
  }
}
