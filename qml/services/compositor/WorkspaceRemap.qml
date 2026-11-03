pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core

// Keeps the compositor's workspaces laid out for the Workspaces layout:
// remaps them when it changes, and starts a grid at its centre cell when
// it's turned on or a run of the compositor starts in one
// (docs/dev/hyprland/workspaces.md › Layout changes, The grid's start).
// Not a singleton: CompositorManager holds one as `_remap` and calls
// begin() once it's built.
QtObject {
  id: root

  // CompositorManager
  property var manager: null

  // --- Layout changes ---

  // The layout the workspaces were last laid out for ({ blocks, size,
  // grid })
  property var _applied: null

  function _layout() {
    return {
      "blocks": WorkspacesConfig.perMonitorBlocks,
      "size": root.manager.blockSize,
      "grid": root.manager.workspaceGrid
    };
  }

  // A layout or count change saved together is one remap. Turning the
  // grid on (from off as last kept, so the config settling at the shell's
  // start never counts) starts every output at its block's centre
  property Timer _timer: Timer {
    interval: 200
    onTriggered: {
      const layout = root._layout();
      if (root._applied)
        root.remap(root._applied, layout, layout.grid && root._kept.grid === false);
      root._applied = layout;
      if (root._kept.grid !== undefined && root._kept.grid !== layout.grid)
        root._keep(layout.grid);
    }
  }

  property Connections _configWatch: Connections {
    target: WorkspacesConfig

    function onPerMonitorBlocksChanged() {
      root._timer.restart();
    }
  }

  property Connections _managerWatch: Connections {
    target: root.manager

    // The layout's size, or the backend's block where workspaces turn
    // dynamic (Hyprland's scrolling layout)
    function onBlockSizeChanged() {
      root._timer.restart();
    }

    // perMonitor to a grid of as many keeps blocks and size
    function onWorkspaceGridChanged() {
      root._timer.restart();
    }
  }

  // Moves every window from its workspace under the `from` layout to the
  // matching one in its output's ids under `to` (WorkspaceGeometry.
  // remapWorkspaces), and switches each output to the workspace matching
  // the one it showed (the backend's applyRemap), or with `centre` to its
  // grid block's centre (WorkspaceGeometry.centreFocus)
  function remap(from, to, centre) {
    const manager = root.manager;
    // Workspaces that belong to their output keep their place in it
    if (!manager.backend || manager.supports.outputWorkspaces === true)
      return;
    const windows = manager.windows.map(w => ({
          "id": w.id,
          "workspace": w.workspaceId,
          "output": w.output
        }));
    const outputs = manager.orderedOutputs();
    const plan = WorkspaceGeometry.remapWorkspaces(outputs, windows, from, to);
    if (centre) {
      const start = WorkspaceGeometry.centreFocus(outputs, to.size, WorkspacesConfig.columns, WorkspacesConfig.rows, false);
      plan.focus = start.focus;
      plan.changed = plan.moves.length > 0 || start.changed;
    }
    if (!plan.changed)
      return;
    manager.noteSwitch(plan.focus[plan.focus.length - 1]?.id ?? -1);
    console.log(`[CompositorManager] remapping workspaces: ${plan.moves.length} windows, outputs to ${plan.focus.map(f => f.monitor + ":" + f.id).join(", ")}`);
    manager.backend.applyRemap(plan, outputs.map(o => o.name));
  }

  // Re-homes workspaces left outside their output's ids
  function reconcile() {
    root.remap(root._layout(), root._layout(), false);
  }

  // --- The grid's start ---

  // Which run of the compositor this is (CompositorKind.sessionKey: a new
  // one each time it starts), "" when unknown
  readonly property string sessionKey: {
    const env = CompositorKind.envNames.reduce((all, name) => {
      all[name] = Quickshell.env(name) ?? "";
      return all;
    }, {});
    return CompositorKind.sessionKey(env, root.manager?.kind ?? "");
  }

  // The run of the compositor the shell last started in and whether its
  // workspaces were last laid out in a grid ({ session, grid }), kept
  // across reloads and restarts of the shell: only a new run starts the
  // grid at its centre, and only a grid turned on from off does
  readonly property var _state: StateManager.createStateHandler("workspaces")
  property var _kept: ({})
  // Set at a new run's start, until the outputs are known
  property bool _pending: false
  readonly property bool _ready: root._pending && root.manager.ready && root.manager.outputs.length > 0 && root.manager.outputs.every(o => o.activeWorkspaceId > 0)
  on_ReadyChanged: {
    if (root._ready)
      Qt.callLater(root._start);
  }

  // At the shell's start. Not in the greeter, nor without a key
  function begin() {
    root._applied = root._layout();
    if (Paths.greeter || root.sessionKey === "")
      return;
    root._kept = root._state.load({}) ?? {};
    root._pending = root._kept.session !== root.sessionKey;
  }

  function _keep(grid) {
    root._kept = {
      "session": root.sessionKey,
      "grid": grid
    };
    root._state.save(root._kept);
  }

  // Sends the outputs the compositor just started on their block's first
  // id (or outside their block) to its centre, all at once (the backend's
  // applyRemap with no moves; goToWorkspace's slides would cancel each
  // other)
  function _start() {
    if (!root._pending)
      return;
    root._pending = false;
    const manager = root.manager;
    root._keep(manager.workspaceGrid);
    if (!manager.workspaceGrid || !manager.backend || manager.supports.outputWorkspaces === true)
      return;
    const outputs = manager.orderedOutputs();
    const start = WorkspaceGeometry.centreFocus(outputs, manager.blockSize, WorkspacesConfig.columns, WorkspacesConfig.rows, true);
    if (!start.changed)
      return;
    manager.noteSwitch(start.focus[start.focus.length - 1]?.id ?? -1);
    console.log(`[CompositorManager] starting the grid at its centre: ${start.focus.map(f => f.monitor + ":" + f.id).join(", ")}`);
    manager.backend.applyRemap({
      "moves": [],
      "focus": start.focus
    }, outputs.map(o => o.name));
  }
}
