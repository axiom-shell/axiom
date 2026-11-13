pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.services.core
import qs.services.compositor
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.services.ui

// One monitor's workspace board (laid out by WorkspacesConfig): wallpaper
// cells with their windows as live previews, in a box (`gridBox`), and the
// special workspaces in a box of their own beside it (`specialBox`). Input is all
// OverviewInput's; this lays out, and turns its drops and resizes into
// CompositorManager actions.
Item {
  id: root

  required property var screen
  // Open: previews capture only then
  property bool active: true
  property real availableWidth: 1920 // a placeholder, set from the screen
  property real availableHeight: 1080 // a placeholder, set from the screen

  signal closeRequested

  readonly property var monitor: CompositorManager.outputFor(root.screen)
  // The workspaces shown, one per cell, and the board's shape: one column
  // of them where the compositor keeps a list per monitor (niri's)
  readonly property var ids: CompositorManager.workspaceIds(root.monitor?.name ?? "")
  readonly property int columns: CompositorManager.dynamicWorkspaces ? 1 : WorkspacesConfig.boardColumns
  readonly property int rows: CompositorManager.dynamicWorkspaces ? Math.max(1, root.ids.length) : WorkspacesConfig.boardRows
  readonly property int activeId: root.monitor?.activeWorkspaceId ?? -1
  // Global layout origin and logical size
  readonly property real monitorX: root.monitor?.x ?? 0
  readonly property real monitorY: root.monitor?.y ?? 0
  readonly property real monitorW: root.screen?.width ?? 1920
  readonly property real monitorH: root.screen?.height ?? 1080

  readonly property real gap: Widget.spacing * 1.5
  // The boxes' padding, widened when a big outer radius would meet a cell's
  // corner: its margin is the box's stroke, the cell's widest stroke (the
  // current one's) and a spacing of air
  readonly property real pad: WorkspaceGeometry.boxPad(Widget.spacing * 2, Appearance.borderRadius, root.cellRadius, Appearance.borderWidth * 3 + Widget.spacing)
  // The monitor less its bars' reserved edges: what a cell shows
  readonly property var usable: WorkspaceGeometry.usableRect(monitorW, monitorH, root.monitor?.reserved)
  // Between the grid's cells and the special workspaces' column: both boxes'
  // padding and the room between the boxes
  readonly property real boxGap: root.gap * 2
  readonly property real sideGap: root.pad * 2 + root.boxGap
  readonly property real miniScale: WorkspaceGeometry.fitScale(availableWidth - pad * 2, availableHeight - pad * 2, usable.w, usable.h, gap, columns, rows, root.specialCount > 0 ? root.sideGap : 0)
  readonly property real cellW: Math.floor(usable.w * miniScale)
  readonly property real cellH: Math.floor(usable.h * miniScale)
  readonly property real cellRadius: Math.max(2, Widget.radius * 0.75)
  // A window preview's (and the drop box's), inside its cell's
  readonly property real previewRadius: Math.max(2, root.cellRadius * 0.6)

  // The special workspaces shown as a column in a box right of the grid.
  // Their names are fixed while the overview is open (`_frozenNames`), so the
  // column keeps its size as windows come and go: an emptied one stays as an
  // empty cell. `specialCount` comes from the names only, never from the
  // cells' size, which it decides (fitScale).
  property var _frozenNames: null
  readonly property var _liveCells: CompositorManager.supports.namedSpecial === true ? SpecialWorkspaces.cells(CompositorManager.knownSpecials, CompositorManager.specials, WorkspaceOverlayConfig.specialWorkspaces) : []
  // A string, so the cells and their Repeater are rebuilt only when the set
  // of names changes
  // (each name led by a newline, so the unnamed one, "", still makes a key)
  readonly property string _specialKey: SpecialWorkspaces.keyOf(root._frozenNames ?? root._liveCells.map(c => c.name))
  readonly property var specialIds: SpecialWorkspaces.namesOf(root._specialKey)
  readonly property int specialCount: root.specialIds.length
  // The cells and their column together, so one never pairs with a stale other
  readonly property var specialSet: {
    const cells = root.specialIds.map(name => root._liveCells.find(c => c.name === name) ?? ({
          "name": name,
          "id": 0,
          "open": false,
          "output": "",
          "windowCount": 0,
          "urgent": false,
          "windows": []
        }));
    return {
      "cells": cells,
      "names": root.specialIds,
      "column": WorkspaceGeometry.specialColumn(cells.length, root.cellW, root.cellH, root.gap, root.columns, root.rows, root.sideGap)
    };
  }
  // The special cells' names kept while the overview is open, null otherwise
  function _freeze() {
    return root.active ? root._liveCells.map(c => c.name) : null;
  }
  onActiveChanged: {
    root._frozenNames = root._freeze();
    root.keyIndex = -1;
  }
  Component.onCompleted: root._frozenNames = root._freeze()

  // The windows in the special cells, tagged with their cell (`specialCell`) and
  // special's id; sway's hidden scratchpad windows too (no output), not a
  // Hyprland group's hidden ones
  readonly property var specialWindows: {
    const list = [];
    root.specialSet.cells.forEach((special, s) => {
      (special.windows ?? []).filter(w => !w.hidden || w.output === "").forEach(w => list.push(Object.assign({}, w, {
          "specialCell": s,
          "special": special.name
        })));
    });
    return list;
  }
  // The windows on the board's workspaces: this monitor's in a grid or
  // perMonitor layout; in the standard layout workspaces are shared, so
  // any monitor's; and the special cells' (a shown special workspace's window sits
  // on a workspace on sway too: one preview per id, in its special cell)
  readonly property var windows: WindowRulesManager.shownIn("workspaces", CompositorManager.windows.filter(w => (!CompositorManager.perMonitorBlocks || w.output === root.monitor?.name) && root.ids.includes(w.workspaceId) && !w.hidden && !root.specialWindows.some(sw => sw.id === w.id)).concat(root.specialWindows))
  readonly property var byAddress: root.windows.reduce((map, w) => {
    map[w.id] = w;
    return map;
  }, {})
  // Hit-testing and layout: [{ id, floating, cell, scale, rect (board coords) }].
  // Cell indices: the workspaces first, then the special cells.
  readonly property var items: {
    const rects = {};
    const grid = root.windows.filter(w => w.specialCell === undefined);
    for (const w of grid) {
      const at = root.originOf(w.output);
      rects[w.id] = WorkspaceGeometry.windowRect(w, at.x, at.y, root.miniScale, root.cellW, root.cellH);
    }
    // A strip's tiled windows squeezed to fit, columns off the monitor too
    for (const id of root.ids) {
      const direction = root.stripOn(id);
      const tiled = direction === "" ? [] : grid.filter(w => w.workspaceId === id && !w.floating);
      if (tiled.length === 0)
        continue;
      const at = root.originOf(tiled[0].output);
      WorkspaceGeometry.stripRects(tiled, at.x, at.y, root.miniScale, root.cellW, root.cellH, direction === "vertical").forEach((r, i) => rects[tiled[i].id] = r);
    }
    const column = root.specialSet.column;
    return root.windows.map(w => {
      const special = w.specialCell !== undefined;
      const cell = special ? root.ids.length + w.specialCell : root.ids.indexOf(w.workspaceId);
      const origin = root.cellRectOf(cell);
      const scale = special ? root.miniScale * column.scale : root.miniScale;
      let r = rects[w.id];
      if (special) {
        // Its own output's usable origin; no strip squeeze in a special cell
        const at = root.originOf(w.output || root.specialSet.cells[w.specialCell].output || root.monitor?.name);
        r = WorkspaceGeometry.windowRect(w, at.x, at.y, scale, origin.w, origin.h);
      }
      return {
        id: w.id,
        floating: w.floating,
        cell: cell,
        scale: scale,
        rect: {
          x: origin.x + r.x,
          y: origin.y + r.y,
          w: r.w,
          h: r.h
        }
      };
    });
  }
  // The previews are modelled by this (through a ScriptModel, which diffs
  // it), so a window event rebuilds nothing, and a window coming or going
  // adds or removes only its own preview (and capture)
  readonly property string _addressKey: root.windows.map(w => w.id).join(",")

  // The global origin of an output's usable area (the layout origin plus its
  // reserved left and top edges), by name (this monitor's if unknown)
  function originOf(output) {
    return WorkspaceGeometry.usableOrigin(CompositorManager.output(output) ?? root.monitor);
  }

  // The origin of the monitor a workspace is on (this one if it doesn't
  // exist yet: it opens here)
  function workspaceOrigin(workspaceId) {
    const ws = CompositorManager.workspaces.find(ws => ws.id === workspaceId);
    return root.originOf(ws?.output || root.monitor?.name);
  }

  // The strip direction where a workspace is (this monitor if it doesn't
  // exist yet), "" where it tiles
  function stripOn(workspaceId) {
    const ws = CompositorManager.workspaces.find(ws => ws.id === workspaceId);
    return CompositorManager.stripDirection(ws?.output || root.screen?.name || "");
  }

  // The cell under a board point, or -1: a workspace's index, or the
  // workspaces' count plus a special cell's
  function cellAt(x, y) {
    const cell = WorkspaceGeometry.cellAt(x, y, root.cellW, root.cellH, root.gap, root.columns, root.ids.length);
    if (cell >= 0)
      return cell;
    const s = WorkspaceGeometry.specialCellAt(root.specialSet.column, x, y);
    return s >= 0 ? root.ids.length + s : -1;
  }

  // A cell's rect (board coords), by the same indices
  function cellRectOf(cell) {
    if (cell >= root.ids.length)
      return root.specialSet.column?.rects[cell - root.ids.length] ?? ({
          x: 0,
          y: 0,
          w: 0,
          h: 0
        });
    return WorkspaceGeometry.cellRect(cell, root.cellW, root.cellH, root.gap, root.columns);
  }

  function itemFor(address) {
    return root.items.find(item => item.id === address) ?? null;
  }

  // Set on each action: a drop can move keyboard focus, which clears the
  // focus grab, and that shouldn't close the overview
  property real _lastAction: 0
  function recentAction() {
    return Date.now() - root._lastAction < 1000;
  }

  // The cell the keyboard has (the board's indices), -1 for none: no ring
  // shows until the first arrow key
  property int keyIndex: -1
  readonly property int cellCount: root.ids.length + root.specialCount
  onCellCountChanged: {
    if (root.keyIndex >= root.cellCount)
      root.keyIndex = -1;
  }

  // A key press: arrows move the ring (from the active workspace on the
  // first), Enter goes to the ringed cell, a digit to the board's n-th workspace.
  // False when it isn't ours, or while a drag or resize is on.
  function handleKey(key) {
    if (input.mode !== "")
      return false;
    const names = {
      [Qt.Key_Left]: "left",
      [Qt.Key_Right]: "right",
      [Qt.Key_Up]: "up",
      [Qt.Key_Down]: "down"
    };
    const direction = names[key];
    if (direction !== undefined) {
      if (root.keyIndex < 0)
        root.keyIndex = Math.max(0, root.ids.indexOf(root.activeId));
      else
        root.keyIndex = WorkspaceGeometry.navigate(root.keyIndex, direction, root.columns, root.ids.length, root.specialCount);
      return true;
    }
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (root.keyIndex < 0)
        return false;
      root.goTo(root.keyIndex);
      return true;
    }
    // A digit n is the board's n-th cell in reading order; none, nothing
    if (key >= Qt.Key_1 && key <= Qt.Key_9) {
      const cell = WorkspaceGeometry.digitCell(key - Qt.Key_0, root.ids.length);
      if (cell >= 0)
        root.goTo(cell);
      return true;
    }
    return false;
  }

  // Esc: stop a drag or resize. False when there was none.
  function cancelInteraction() {
    return input.cancel();
  }

  // A workspace, or a special cell's special shown or hidden on this monitor
  function goTo(cell) {
    if (cell >= root.ids.length)
      CompositorManager.toggleSpecial(root.specialIds[cell - root.ids.length], root.monitor?.name ?? "");
    else
      CompositorManager.goToWorkspace(root.ids[cell], "go", root.monitor?.name ?? "");
    root.closeRequested();
  }

  function focusWindow(address) {
    CompositorManager.focusWindow(address);
    root.closeRequested();
  }

  function closeWindow(address) {
    root._lastAction = Date.now();
    CompositorManager.closeWindow(address);
  }

  // A window dropped at a board point, its preview's corner at `corner`;
  // `cursor` is the pointer in overlay coordinates
  function dropWindow(address, cell, point, corner, cursor) {
    const win = root.byAddress[address];
    if (!win || cell < 0)
      return;
    // Onto a special cell: into that special, the position ignored. The
    // unnamed one ("") takes no drops: nothing in axiom fills it
    if (cell >= root.ids.length) {
      const name = root.specialIds[cell - root.ids.length];
      if (win.special === name || name === "")
        return;
      root._lastAction = Date.now();
      CompositorManager.moveToSpecial(name, address);
      return;
    }
    const workspaceId = root.ids[cell];
    const same = win.workspaceId === workspaceId;
    root._lastAction = Date.now();
    if (win.floating) {
      const origin = WorkspaceGeometry.cellRect(cell, root.cellW, root.cellH, root.gap, root.columns);
      const at = root.workspaceOrigin(workspaceId);
      // The preview's size at grid scale (a special cell's is scaled down)
      const item = root.itemFor(address);
      const k = item ? root.miniScale / item.scale : 1;
      const size = {
        w: (item?.rect.w ?? 0) * k,
        h: (item?.rect.h ?? 0) * k
      };
      const x = Math.min(Math.max(corner.x - origin.x, 0), root.cellW - size.w);
      const y = Math.min(Math.max(corner.y - origin.y, 0), root.cellH - size.h);
      CompositorManager.placeWindow(address, workspaceId, "", "", null, same, {
        x: at.x + x / root.miniScale,
        y: at.y + y / root.miniScale
      });
      return;
    }
    const target = root.dropTargetAt(cell, point, address);
    // Alone on its workspace: nowhere else to go
    if (same && !target)
      return;
    CompositorManager.placeWindow(address, workspaceId, target?.id ?? "", target?.side ?? "", {
      x: root.monitorX + cursor.x,
      y: root.monitorY + cursor.y
    }, same, null);
  }

  // Where a tiled window dropped at a point lands (see WorkspaceGeometry)
  function dropTargetAt(cell, point, address) {
    if (cell >= root.ids.length)
      return null;
    const others = root.items.filter(item => item.cell === cell && !item.floating && item.id !== address);
    const direction = root.stripOn(root.ids[cell]);
    if (direction !== "")
      return WorkspaceGeometry.stripDropTarget(others, point.x, point.y, direction === "vertical");
    return WorkspaceGeometry.dropTarget(others, point.x, point.y, CompositorManager.splitWidthMultiplier);
  }

  // A resize step, in board pixels
  function resizeWindow(address, dw, dh, dx, dy) {
    root._lastAction = Date.now();
    const s = root.itemFor(address)?.scale ?? root.miniScale;
    CompositorManager.resizeWindow(address, dw / s, dh / s, dx / s, dy / s);
  }

  // The grid's box, as the one board has always been; the special workspaces' is
  // beside it
  readonly property alias gridBox: gridBox
  readonly property alias specialBox: specialBox
  implicitWidth: board.width + root.pad * 2
  implicitHeight: gridBox.height

  Rectangle {
    id: gridBox
    width: root.cellW * root.columns + root.gap * (root.columns - 1) + root.pad * 2
    height: board.height + root.pad * 2
    radius: Appearance.borderRadius
    color: Appearance.fill(Theme.background)
    border.color: Theme.foreground
    border.width: Appearance.borderWidth

    // Clicks on the panel's margin don't reach the backdrop (which closes)
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }
  }

  // The special workspaces' box, the grid's own style, centred on the grid's centre
  Rectangle {
    id: specialBox
    readonly property var column: root.specialSet.column
    visible: column !== null
    x: column?.x ?? 0
    y: column?.stackY ?? 0
    width: root.cellW + root.pad * 2
    height: (column?.stackH ?? 0) + root.pad * 2
    radius: Appearance.borderRadius
    color: gridBox.color
    border.color: gridBox.border.color
    border.width: gridBox.border.width

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }
  }

  Item {
    id: board
    x: root.pad
    y: root.pad
    width: root.specialSet.column?.boardWidth ?? root.cellW * root.columns + root.gap * (root.columns - 1)
    height: root.cellH * root.rows + root.gap * (root.rows - 1)

    Repeater {
      model: root.ids.length

      WorkspaceCell {
        required property int index
        readonly property var rect: WorkspaceGeometry.cellRect(index, root.cellW, root.cellH, root.gap, root.columns)

        x: rect.x
        y: rect.y
        width: root.cellW
        height: root.cellH
        wallpaper: WorkspaceOverlayConfig.wallpaper ? ThemeManager.wallpaperFor(root.screen?.name ?? "") : ""
        wallpaperRect: WorkspaceGeometry.wallpaperRect(root.usable, root.monitorW, root.monitorH, root.miniScale)
        wallpaperSize: Qt.size(Math.round(root.monitorW * root.miniScale), Math.round(root.monitorH * root.miniScale))
        color: WorkspaceOverlayConfig.color
        dim: WorkspaceOverlayConfig.dimInactive
        radius: root.cellRadius
        current: root.ids[index] === root.activeId
        hovered: input.hoveredCell === index && input.mode === ""
        dropTarget: input.mode === "drag" && input.dropCell === index
        // An empty workspace takes the whole cell
        dropFill: dropTarget && input.dropHint === null
      }
    }

    Repeater {
      model: root.specialCount

      WorkspaceCell {
        id: specialCellItem
        required property int index
        readonly property int cell: root.ids.length + index
        readonly property var rect: root.cellRectOf(cell)
        readonly property var special: root.specialSet.cells[index] ?? null

        x: rect.x
        y: rect.y
        width: rect.w
        height: rect.h
        wallpaper: WorkspaceOverlayConfig.wallpaper ? ThemeManager.wallpaperFor(root.screen?.name ?? "") : ""
        wallpaperRect: WorkspaceGeometry.wallpaperRect(root.usable, root.monitorW, root.monitorH, root.miniScale * (root.specialSet.column?.scale ?? 1))
        wallpaperSize: Qt.size(Math.round(root.monitorW * root.miniScale), Math.round(root.monitorH * root.miniScale))
        color: WorkspaceOverlayConfig.color
        dim: WorkspaceOverlayConfig.dimInactive
        radius: root.cellRadius
        tint: WorkspaceOverlayConfig.specialWorkspaceColor
        current: special?.open === true && special.output === root.monitor?.name
        hovered: input.hoveredCell === cell && input.mode === ""
        dropTarget: input.mode === "drag" && input.dropCell === cell && special?.name !== ""
        dropFill: dropTarget && input.dropHint === null
      }
    }

    Repeater {
      model: ScriptModel {
        values: root._addressKey === "" ? [] : root._addressKey.split(",")
      }

      WindowPreview {
        id: preview
        required property string modelData
        readonly property var item: root.itemFor(modelData)
        readonly property var rect: item?.rect ?? {
          x: 0,
          y: 0,
          w: 0,
          h: 0
        }

        x: rect.x
        y: rect.y
        width: rect.w
        height: rect.h
        z: item?.floating ? 2 : 1
        visible: item !== null
        windowData: root.byAddress[modelData] ?? null
        capturing: root.active
        showTitle: WorkspaceOverlayConfig.showTitles
        radius: root.previewRadius
        hovered: input.hoveredAddress === modelData && (input.mode === "" || input.mode === "resize")
        resizing: input.mode === "resize" && input.activeAddress === modelData
        opacity: input.mode === "drag" && input.activeAddress === modelData ? 0.3 : 1

        Glide on x {
          enabled: !preview.resizing
        }
        Glide on y {
          enabled: !preview.resizing
        }
        Glide on width {
          enabled: !preview.resizing
        }
        Glide on height {
          enabled: !preview.resizing
        }
      }
    }

    // Workspace numbers, above the windows
    Repeater {
      model: WorkspaceOverlayConfig.showNumbers ? root.ids.length : 0

      WorkspaceNumber {
        required property int index
        readonly property var rect: WorkspaceGeometry.cellRect(index, root.cellW, root.cellH, root.gap, root.columns)

        x: rect.x + margin
        y: rect.y + margin
        z: 3
        cornerRadius: root.cellRadius
        text: WorkspaceCells.badgeText(root.ids[index], index + 1, CompositorManager.workspaces.find(ws => ws.id === root.ids[index])?.name ?? "", CompositorManager.dynamicWorkspaces)
        current: root.ids[index] === root.activeId
      }
    }

    // Special workspaces' icons and titles. Shown with the numbers off too: it is
    // all that names one.
    Repeater {
      model: root.specialCount

      WorkspaceNumber {
        id: specialBadge
        required property int index
        readonly property var rect: root.cellRectOf(root.ids.length + index)
        readonly property var special: root.specialSet.cells[index] ?? null
        readonly property var entry: SpecialWorkspaces.entryFor(WorkspacesConfig.specialWorkspaces, root.specialIds[index] ?? "")
        readonly property var shown: SpecialWorkspaces.content(entry, root.specialIds[index] ?? "", "both", false, false)

        x: rect.x + margin
        y: rect.y + margin
        z: 3
        cornerRadius: root.cellRadius
        // The unnamed one is a star with no title (kind "glyph")
        readonly property bool starOnly: shown.kind === "glyph"
        text: starOnly ? "" : shown.text
        icon: starOnly ? shown.text : shown.lead
        iconPlain: !(Utils.isSymbolName(icon) && IconManager.isKnown(icon))
        tint: WorkspaceOverlayConfig.specialWorkspaceColor
        tintText: true
        maxWidth: rect.w - 2 * margin
        current: special?.open === true && special.output === root.monitor?.name
      }
    }

    // The keyboard's cell
    Rectangle {
      readonly property var rect: root.cellRectOf(root.keyIndex)
      readonly property real outset: Appearance.borderWidth * 2
      visible: root.keyIndex >= 0 && root.keyIndex < root.cellCount
      x: rect.x - outset
      y: rect.y - outset
      width: rect.w + outset * 2
      height: rect.h + outset * 2
      z: 3
      radius: root.cellRadius + outset
      color: "transparent"
      border.width: Appearance.borderWidth * 2
      border.color: Theme.foreground

      Glide on x {}
      Glide on y {}
      Glide on width {}
      Glide on height {}
    }

    // Where a dragged tiled window will land
    Rectangle {
      id: dropBox
      readonly property var hint: input.dropHint
      // It appears in place and only animates between halves once shown;
      // otherwise it would fly in from the board's corner (0, 0)
      property bool animate: false
      onVisibleChanged: {
        dropBox.animate = false;
        if (dropBox.visible)
          Qt.callLater(() => dropBox.animate = dropBox.visible);
      }

      visible: input.mode === "drag" && hint !== null
      x: hint?.rect.x ?? 0
      y: hint?.rect.y ?? 0
      width: hint?.rect.w ?? 0
      height: hint?.rect.h ?? 0
      z: 3
      radius: root.previewRadius
      color: Qt.alpha(Theme.accent, 0.3)
      border.color: Theme.accent
      border.width: Appearance.borderWidth * 2

      Glide on x {
        enabled: dropBox.animate
      }
      Glide on y {
        enabled: dropBox.animate
      }
      Glide on width {
        enabled: dropBox.animate
      }
      Glide on height {
        enabled: dropBox.animate
      }
    }

    // The dragged window, under the pointer
    WindowPreview {
      readonly property var rect: root.itemFor(input.activeAddress)?.rect ?? {
        w: 0,
        h: 0
      }
      visible: input.mode === "drag"
      x: input.ghostX
      y: input.ghostY
      width: rect.w
      height: rect.h
      z: 4
      windowData: input.mode === "drag" ? root.byAddress[input.activeAddress] ?? null : null
      capturing: root.active && visible
      radius: root.previewRadius
      hovered: true
      opacity: 0.9
    }

    OverviewInput {
      id: input
      anchors.fill: parent
      z: 5
      overview: root
    }
  }
}
