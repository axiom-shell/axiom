pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.reusable
import qs.components.hosts.popout

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
  property var panel
  // The widget's (BarWidget.hitArea), which its popout reads hover from
  property var hitArea: null
  property var barConfig
  property var properties
  // Room kept to the widget's background across the bar
  property real inset: 0

  readonly property bool isVertical: barConfig.vertical

  readonly property color activeColor: Theme.resolveColor(properties.activeColor)
  readonly property color occupiedColor: Theme.resolveColor(properties.occupiedColor)
  readonly property color emptyColor: Theme.resolveColor(properties.emptyColor)
  readonly property color iconColor: Theme.resolveColor(properties.textColor)
  readonly property color hoverColor: Bar.cellHoverColor(properties)

  readonly property var monitor: CompositorManager.outputFor(root.screen)
  readonly property string output: root.monitor?.name ?? ""
  readonly property int base: CompositorManager.workspaceBase(root.output)
  readonly property int columns: WorkspacesConfig.columns
  readonly property int rows: WorkspacesConfig.rows
  readonly property int activeId: root.monitor?.activeWorkspaceId ?? -1
  // "horizontal" | "vertical" on a strip monitor, else ""
  readonly property string stripDirection: CompositorManager.stripDirection(root.screen?.name ?? "")
  // One workspace shown on a strip monitor: its windows show alone while it
  // has any (WorkspaceStrip.stripOnly)
  readonly property bool stripOnly: root.lineIds(root.activeLine, root.activeId).length <= 1 && root.stripDirection !== "" && ((activeStrip.item as ActiveStrip)?.hasWindows ?? false)
  // The active workspace's place in the grid (the first cell when the
  // monitor is on a workspace outside it)
  readonly property int activeIndex: {
    const index = root.activeId - root.base;
    return index >= 0 && index < root.columns * root.rows ? index : 0;
  }
  readonly property int activeRow: Math.floor(root.activeIndex / root.columns)
  readonly property int activeColumn: root.activeIndex % root.columns
  // The row (column on a vertical bar) the bar shows
  readonly property int activeLine: root.isVertical ? root.activeColumn : root.activeRow

  // A cell's size on the bar (inside the background), and its corners
  // within the background's
  readonly property real cell: root.barConfig.widgetSize - root.inset * 2
  readonly property real cellRadius: Bar.cellRadius(root.barConfig, root.cell, root.inset)
  readonly property real spacing: root.barConfig.widgetSpacing
  // Along the bar: square, or narrower for dots straight on the bar
  readonly property real cellLength: root.barConfig.widgetBoxed || root.properties.labels !== "dots" || root.properties.showAppIcons ? root.cell : Math.round(root.cell * 0.6)
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

  // Where the shown row (or column) sits among `count`: double arrows at the
  // ends, single ones between, a dot in the middle
  function positionGlyph(position, count) {
    const middle = (count - 1) / 2;
    if (position === middle)
      return "circle";
    if (root.isVertical)
      return position === 0 ? "keyboard_double_arrow_left" : position === count - 1 ? "keyboard_double_arrow_right" : position < middle ? "keyboard_arrow_left" : "keyboard_arrow_right";
    return position === 0 ? "keyboard_double_arrow_up" : position === count - 1 ? "keyboard_double_arrow_down" : position < middle ? "keyboard_arrow_up" : "keyboard_arrow_down";
  }

  WheelHandler {
    enabled: root.properties.scrollToSwitch
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    property real _accumulated: 0
    onWheel: event => {
      _accumulated += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
      if (Math.abs(_accumulated) < 120)
        return;
      const forward = _accumulated < 0;
      if (root.stripDirection !== "")
        CompositorManager.stepStrip(forward ? 1 : -1, root.output);
      else
        CompositorManager.stepWorkspace(root.isVertical ? (forward ? "down" : "up") : (forward ? "right" : "left"), "go");
      _accumulated = 0;
    }
  }

  Grid {
    id: layout
    // Only what's shown: a Grid keeps spacing for an empty column or row
    readonly property int shown: Math.max(1, (root.stripOnly ? 0 : 1) + (activeStrip.visible ? 1 : 0))
    rows: root.isVertical ? shown : 1
    columns: root.isVertical ? 1 : shown
    spacing: root.spacing

    // The active row (or column) of the grid
    CrossFade {
      visible: !root.stripOnly
      value: root.activeLine
      delegate: shownLine
    }

    Loader {
      id: activeStrip
      active: root.stripDirection !== ""
      visible: (item as ActiveStrip)?.hasWindows ?? false

      sourceComponent: ActiveStrip {
        barConfig: root.barConfig
        divider: !root.stripOnly
        workspaceId: root.activeId
        stripVertical: root.stripDirection === "vertical"
        cell: root.cell
        cellRadius: root.cellRadius
        activeColor: root.activeColor
        occupiedColor: root.occupiedColor
        textColor: root.iconColor
        hoverColor: root.hoverColor
        clickable: root.properties.clickToSwitch
        hitArea: root.hitArea
      }
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
      monitor: root.monitor
      base: root.base
      ids: line._idsKey === "" ? [] : line._idsKey.split(",").map(Number)
      activeId: _activeHere
      cell: root.cell
      cellLength: root.cellLength
      cellRadius: root.cellRadius
      activeColor: root.activeColor
      occupiedColor: root.occupiedColor
      emptyColor: root.emptyColor
      textColor: root.iconColor
      hitArea: root.hitArea
      hoverColor: root.hoverColor
      // The active arrow takes the active cell's place
      glyphOf: (id, active) => active && root.properties.showActiveIcon ? root.positionGlyph(line.value, root.isVertical ? root.columns : root.rows) : ""

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
    active: WorkspacesConfig.size > 1 && EdgeMenusConfig.opensOwnPopout(root.properties)
    extraData: ({
        output: root.output,
        vertical: root.isVertical,
        // The cells' own size and corners, as on the bar
        cellSize: root.cell,
        cellLength: root.cellLength,
        barConfig: root.barConfig,
        cellSpacing: root.spacing,
        radius: root.cellRadius,
        fontSize: root.barConfig.fontSize,
        properties: root.properties
      })
  }
}
