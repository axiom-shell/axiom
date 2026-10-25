pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.services.core
import qs.services.compositor
import qs.config
import qs.components.methods
import qs.components.reusable

// One monitor's workspace board (laid out by WorkspacesConfig): wallpaper
// cells with their windows as live previews. Input is all OverviewInput's; this lays out, and turns its
// drops and resizes into CompositorManager actions.
Rectangle {
  id: root

  required property var screen
  // Open: previews capture only then
  property bool active: true
  property real availableWidth: 1920 // fixed px: a placeholder, set from the screen
  property real availableHeight: 1080 // fixed px: a placeholder, set from the screen

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
  readonly property real pad: Widget.spacing * 2
  readonly property real miniScale: WorkspaceGeometry.fitScale(availableWidth - pad * 2, availableHeight - pad * 2, monitorW, monitorH, gap, columns, rows)
  readonly property real cellW: Math.floor(monitorW * miniScale)
  readonly property real cellH: Math.floor(monitorH * miniScale)
  readonly property real cellRadius: Math.max(2, Widget.radius * 0.75)
  // A window preview's (and the drop box's), inside its cell's
  readonly property real previewRadius: Math.max(2, root.cellRadius * 0.6)

  // The windows on the board's workspaces: this monitor's in a grid or
  // perMonitor layout; in the standard layout workspaces are shared, so
  // any monitor's
  readonly property var windows: CompositorManager.windows.filter(w => (!CompositorManager.perMonitorBlocks || w.output === root.monitor?.name) && root.ids.includes(w.workspaceId) && !w.hidden)
  readonly property var byAddress: root.windows.reduce((map, w) => {
    map[w.id] = w;
    return map;
  }, {})
  // Hit-testing and layout: [{ id, floating, cell, rect (board coords) }]
  readonly property var items: {
    const rects = {};
    for (const w of root.windows) {
      const at = root.originOf(w.output);
      rects[w.id] = WorkspaceGeometry.windowRect(w, at.x, at.y, root.miniScale, root.cellW, root.cellH);
    }
    // A strip's tiled windows squeezed to fit, columns off the monitor too
    for (const id of root.ids) {
      const direction = root.stripOn(id);
      const tiled = direction === "" ? [] : root.windows.filter(w => w.workspaceId === id && !w.floating);
      if (tiled.length === 0)
        continue;
      const at = root.originOf(tiled[0].output);
      WorkspaceGeometry.stripRects(tiled, at.x, at.y, root.miniScale, root.cellW, root.cellH, direction === "vertical").forEach((r, i) => rects[tiled[i].id] = r);
    }
    return root.windows.map(w => {
      const cell = root.ids.indexOf(w.workspaceId);
      const origin = WorkspaceGeometry.cellRect(cell, root.cellW, root.cellH, root.gap, root.columns);
      const r = rects[w.id];
      return {
        id: w.id,
        floating: w.floating,
        cell: cell,
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

  // An output's global layout origin, by name (this one's if unknown)
  function originOf(output) {
    const m = CompositorManager.output(output);
    return m ? {
      x: m.x,
      y: m.y
    } : {
      x: root.monitorX,
      y: root.monitorY
    };
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

  function itemFor(address) {
    return root.items.find(item => item.id === address) ?? null;
  }

  // Set on each action: a drop can move keyboard focus, which clears the
  // focus grab, and that shouldn't close the overview
  property real _lastAction: 0
  function recentAction() {
    return Date.now() - root._lastAction < 1000;
  }

  // Esc: stop a drag or resize. False when there was none.
  function cancelInteraction() {
    return input.cancel();
  }

  function goTo(cell) {
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
    const workspaceId = root.ids[cell];
    const same = win.workspaceId === workspaceId;
    root._lastAction = Date.now();
    if (win.floating) {
      const origin = WorkspaceGeometry.cellRect(cell, root.cellW, root.cellH, root.gap, root.columns);
      const at = root.workspaceOrigin(workspaceId);
      const size = root.itemFor(address)?.rect ?? {
        w: 0,
        h: 0
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
    const others = root.items.filter(item => item.cell === cell && !item.floating && item.id !== address);
    const direction = root.stripOn(root.ids[cell]);
    if (direction !== "")
      return WorkspaceGeometry.stripDropTarget(others, point.x, point.y, direction === "vertical");
    return WorkspaceGeometry.dropTarget(others, point.x, point.y, CompositorManager.splitWidthMultiplier);
  }

  // A resize step, in board pixels
  function resizeWindow(address, dw, dh, dx, dy) {
    root._lastAction = Date.now();
    const s = root.miniScale;
    CompositorManager.resizeWindow(address, dw / s, dh / s, dx / s, dy / s);
  }

  implicitWidth: board.width + root.pad * 2
  implicitHeight: board.height + root.pad * 2
  radius: Appearance.borderRadius
  color: Appearance.fill(Theme.background)
  border.color: Theme.foreground
  border.width: Appearance.borderWidth

  // Clicks on the panel's margin don't reach the backdrop (which closes)
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
  }

  Item {
    id: board
    x: root.pad
    y: root.pad
    width: root.cellW * root.columns + root.gap * (root.columns - 1)
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
        number: index + 1
        current: root.ids[index] === root.activeId
      }
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
