pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core

// Keeps the compositor's workspaces laid out for the Workspaces layout:
// remaps them when it changes, and starts a grid at its centre cell when
// it's turned on or a run of the compositor starts in one, re-homes an
// unplugged monitor's windows and returns them when it's back
// (docs/dev/hyprland/workspaces.md › Layout changes, Hotplugs, The grid's
// start).
// Not a singleton: CompositorManager holds one as `_remap` and calls
// begin() once it's built.
QtObject {
  id: root

  // CompositorManager
  property var manager: null

  // --- Layout changes ---

  // The layout the workspaces were last laid out for ({ blocks, size,
  // grid, bases })
  property var _applied: null

  function _layout() {
    return {
      "blocks": WorkspacesConfig.perMonitorBlocks,
      "size": root.manager.blockSize,
      "grid": root.manager.workspaceGrid,
      "bases": root.manager._bases
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

    function onOutputsChanged() {
      root._noteOutputs();
    }

    // A block order change with the same outputs connected (a profile
    // naming a new monitor, a new primary): remap. A hotplug doesn't remap
    // the layout: it records the bases (a pending remap's too, so it
    // doesn't move them), at the size last applied, which a pending size
    // change remaps from, re-homes the workspaces it left outside their
    // output's block (_rehome) and returns those of a monitor back
    // (_return)
    function on_BasesChanged() {
      const applied = root._applied;
      if (!applied)
        return;
      const bases = root.manager._bases;
      const names = Object.keys(bases);
      const sameOutputs = names.length === Object.keys(applied.bases).length && names.every(name => name in applied.bases);
      if (applied.blocks && sameOutputs && names.some(name => applied.bases[name] !== bases[name]))
        root._timer.restart();
      else {
        if (applied.blocks && !sameOutputs)
          root._hotplugged(applied);
        root._applied = Object.assign({}, applied, {
          "bases": names.reduce((all, name) => {
            all[name] = (bases[name] - 1) / root.manager.blockSize * applied.size + 1;
            return all;
          }, {})
        });
      }
    }
  }

  // --- Hotplugs ---

  // The layout before the hotplugs a re-home waits on ({ size, bases }),
  // and the outputs they took away
  property var _before: null
  property var _removed: []

  // Each output's last known description and the workspace it showed, by
  // name, kept once it's gone: where a re-homed window came from
  property var _known: ({})

  function _noteOutputs() {
    const known = Object.assign({}, root._known);
    root.manager.outputs.forEach(o => known[o.name] = {
        "description": o.description || (known[o.name]?.description ?? ""),
        "active": o.activeWorkspaceId > 0 ? o.activeWorkspaceId : (known[o.name]?.active ?? -1)
      });
    root._known = known;
  }

  // Outputs came or went (unplugged, turned off, made a mirror; or back):
  // once the compositor has moved their workspaces, re-home them (the
  // first hotplug's layout is the one to re-home from), and return the
  // windows of a monitor that's back
  function _hotplugged(applied) {
    if (!root._before)
      root._before = {
        "size": applied.size,
        "bases": applied.bases
      };
    const now = root.manager._bases;
    root._removed = root._removed.concat(Object.keys(applied.bases).filter(name => !(name in now) && !root._removed.includes(name)));
    root._rehomeTimer.restart();
    if (Object.keys(root._returns).length > 0)
      root._returnTimer.restart();
  }

  // Waits out a blip (a dock, an MST hub or DPMS dropping an output for
  // a moment as the machine suspends or resumes: back by then, its windows
  // stay where the compositor puts them back), then for the compositor to
  // have moved an unplugged output's workspaces and the windows to have
  // been read again
  property Timer _rehomeTimer: Timer {
    // behaviour timing: the grace period an output gets to come back
    interval: 3000
    onTriggered: root._rehome()
  }

  // An unplugged output's workspaces sit on another output at ids outside
  // its block, which no list, step or overview shows: their windows move
  // into that output's block, as do those of an output whose block the
  // hotplug moved (WorkspaceGeometry.rehomeWorkspaces). Not where the
  // compositor's workspaces belong to an output or are dynamic (each
  // output lists the ones it has)
  function _rehome() {
    const manager = root.manager;
    const before = root._before;
    // An output back within the grace period took its workspaces back
    const removed = root._removed.filter(name => !(name in manager._bases));
    root._before = null;
    root._removed = [];
    if (!before || !manager.backend || manager.supports.outputWorkspaces === true || manager.dynamicWorkspaces || !WorkspacesConfig.perMonitorBlocks)
      return;
    const windows = manager.windows.map(w => ({
          "id": w.id,
          "workspace": w.workspaceId,
          "output": w.output
        }));
    const outputs = manager.orderedOutputs();
    const plan = WorkspaceGeometry.rehomeWorkspaces(outputs, windows, {
      "size": manager.blockSize,
      "bases": manager._bases
    }, before, removed);
    if (!plan.changed)
      return;
    root._record(plan.moves);
    manager.noteSwitch(plan.focus[plan.focus.length - 1]?.id ?? -1);
    console.log(`[CompositorManager] re-homing workspaces after a hotplug (${removed.join(", ") || "none"} gone): ${plan.moves.length} windows, outputs to ${plan.focus.map(f => f.monitor + ":" + f.id).join(", ")}`);
    manager.backend.applyRemap(plan, outputs.map(o => o.name));
  }

  // --- Returns ---

  // Where each re-homed window came from, by window id ({ workspace,
  // monitor, description, shown }: the workspace it left, the monitor's
  // name and description, whether that monitor showed it), until its
  // monitor is back. Kept in the `workspaceReturns` state file for the
  // compositor's run (`{ session, windows }`), so a reload or restart of
  // the shell keeps it
  property var _returns: ({})
  readonly property var _returnsState: StateManager.createStateHandler("workspaceReturns")

  // Records the windows a re-home moved off an unplugged monitor, each
  // with the first place it left (a window re-homed twice, as a second
  // monitor goes, keeps the first)
  function _record(moves) {
    const returns = Object.assign({}, root._returns);
    moves.forEach(m => {
      if (m.origin === "" || returns[m.id])
        return;
      const known = root._known[m.origin] ?? {};
      returns[m.id] = {
        "workspace": m.from,
        "monitor": m.origin,
        "description": known.description ?? "",
        "shown": known.active === m.from
      };
    });
    root._setReturns(returns);
  }

  function _setReturns(returns) {
    root._returns = returns;
    if (root.sessionKey !== "" && !Paths.greeter)
      root._returnsState.save({
        "session": root.sessionKey,
        "windows": returns
      });
  }

  // Waits for the compositor to have set up a monitor that's back (Hyprland
  // reads its description a moment after it connects) and its
  // workspaces, and the windows to have been read again
  property Timer _returnTimer: Timer {
    interval: 1000
    onTriggered: root._return()
  }

  // Every window re-homed off a monitor that's back goes back to the
  // workspace it left, wherever it is now, and that workspace onto the
  // monitor (WorkspaceGeometry.returnWindows), through the backend's
  // returnWorkspaces: no focus moves. Records whose window is gone are
  // dropped. Only where a re-home runs
  function _return() {
    const manager = root.manager;
    if (Object.keys(root._returns).length === 0 || !manager.backend || manager.supports.outputWorkspaces === true || manager.dynamicWorkspaces || !WorkspacesConfig.perMonitorBlocks)
      return;
    if (!manager.ready) {
      root._returnTimer.restart();
      return;
    }
    const windows = manager.windows.map(w => ({
          "id": w.id,
          "workspace": w.workspaceId,
          "output": w.output
        }));
    const outputs = manager.outputs.map(o => ({
          "name": o.name,
          "description": o.description,
          "active": o.activeWorkspaceId
        }));
    const plan = WorkspaceGeometry.returnWindows(root._returns, windows, outputs, {
      "size": manager.blockSize,
      "bases": manager._bases
    });
    if (plan.done.length > 0)
      root._setReturns(Object.keys(root._returns).filter(id => !plan.done.includes(id)).reduce((all, id) => {
        all[id] = root._returns[id];
        return all;
      }, {}));
    if (!plan.changed)
      return;
    console.log(`[CompositorManager] returning windows to their monitor: ${plan.moves.map(m => m.id + ">" + m.to).join(", ")}; workspaces ${plan.workspaces.map(w => w.id + ">" + w.monitor).join(", ")}`);
    manager.backend.returnWorkspaces(plan);
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
    // The ids re-homed windows would return to were the old layout's
    const ids = layout => [layout.blocks, layout.size].concat(Object.keys(layout.bases ?? {}).sort().map(name => name + "=" + layout.bases[name])).join(" ");
    if (ids(from) !== ids(to) && Object.keys(root._returns).length > 0)
      root._setReturns({});
    if (centre) {
      const start = WorkspaceGeometry.centreFocus(outputs, to.size, WorkspacesConfig.columns, WorkspacesConfig.rows, false);
      plan.focus = start.focus;
      plan.changed = plan.moves.length > 0 || start.changed;
    }
    if (!plan.changed)
      return;
    manager.noteSwitch(plan.focus[plan.focus.length - 1]?.id ?? -1);
    console.log(`[CompositorManager] remapping workspaces from ${JSON.stringify(from)} to ${JSON.stringify(to)}: ${plan.moves.length} windows, outputs to ${plan.focus.map(f => f.monitor + ":" + f.id).join(", ")}`);
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
    root._noteOutputs();
    if (Paths.greeter || root.sessionKey === "")
      return;
    root._kept = root._state.load({}) ?? {};
    root._pending = root._kept.session !== root.sessionKey;
    // Re-homed windows still away, if the compositor's run is the same
    const returns = root._returnsState.load({}) ?? {};
    if (returns.session === root.sessionKey && Object.keys(returns.windows ?? {}).length > 0) {
      root._returns = returns.windows;
      root._returnTimer.restart();
    }
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
