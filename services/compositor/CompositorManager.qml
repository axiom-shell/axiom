pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core

/* The running compositor, for the rest of axiom: its windows, outputs and
 * workspaces in shapes that don't depend on it, what it supports, and every
 * workspace switch and window focus (docs/dev/compositor/README.md). The
 * compositor's own work is its backend's (HyprlandManager, SwayManager); with none
 * (an unknown compositor) everything here is empty and does nothing. */
Singleton {
  id: root

  // The compositor's name as people know it ("Hyprland"; the backend's own
  // when it tells a variant apart, "SwayFX"), or "the compositor" for an
  // unknown one. I18n.tr("the compositor")
  readonly property string displayName: root.backend?.displayName || (kind !== "" ? nameOf(kind) : I18n.tr("the compositor"))

  // A compositor kind's name as people know it ("Hyprland")
  function nameOf(kind) {
    return ({
        "hyprland": "Hyprland",
        "sway": "Sway",
        "niri": "niri"
      })[kind] ?? kind;
  }

  // Why a setting needing `capability` (a supports key) is greyed out:
  // that the compositor can't do it, and what can, where the backend knows
  // (its unsupportedHint). I18n.tr("{0} can't do this.")
  function unsupportedNote(capability) {
    return [I18n.tr("{0} can't do this.", root.displayName), root.unsupportedHint(capability)].filter(text => text !== "").join(" ");
  }

  // What can do what this compositor can't, for `capability` (a supports
  // key): "SwayFX can." on plain sway; "" where the backend doesn't say
  function unsupportedHint(capability) {
    return root.backend?.unsupportedHint?.(capability) ?? "";
  }

  // Whether axiom can set the compositor up, for the onboarding's Compositor
  // page: calls back with { supported, problem, legacyNote } (contract.md ›
  // Config layer). A backend that doesn't check calls back at once with
  // supported and no notes.
  function withSetupCheck(callback) {
    if (root.backend?.withSetupCheck)
      root.backend.withSetupCheck(callback);
    else
      callback({
        "supported": true,
        "problem": "",
        "legacyNote": ""
      });
  }

  // Which compositor axiom runs under: "hyprland", "sway", "niri" or ""
  // (unknown, or none), from HYPRLAND_INSTANCE_SIGNATURE / SWAYSOCK /
  // NIRI_SOCKET; with more than one set (one left over from an earlier
  // session), the one still running (CompositorKind). AXIOM_COMPOSITOR
  // overrides it, for testing ("none" for no backend at all).
  readonly property string kind: {
    const forced = Quickshell.env("AXIOM_COMPOSITOR") ?? "";
    if (forced !== "")
      return forced === "none" ? "" : forced;
    const env = CompositorKind.envNames.reduce((all, name) => {
      all[name] = Quickshell.env(name) ?? "";
      return all;
    }, {});
    const candidates = CompositorKind.candidates(env);
    const picked = CompositorKind.pick(candidates, candidate => root._running(candidate));
    if (candidates.length > 1)
      console.log(`[CompositorManager] ${candidates.map(c => c.kind).join(", ")} named in the environment; running under ${picked}`);
    return picked;
  }

  // Whether a CompositorKind candidate's process still runs
  function _running(candidate) {
    const pid = candidate.pid !== "" ? candidate.pid : CompositorKind.lockPid(candidate.lockFile !== "" ? FileManager.read(candidate.lockFile) : "");
    return pid !== "" && CompositorKind.isProcess(candidate.kind, FileManager.read(`/proc/${pid}/comm`));
  }

  // The backend for `kind`, or null (docs/dev/compositor/contract.md). Only
  // the one picked is ever created.
  readonly property var backend: kind === "hyprland" ? HyprlandManager : kind === "sway" ? SwayManager : kind === "niri" ? NiriManager : null

  // Whether `supports` is final: a backend that finds out what it can do
  // by asking (sway: SwayFX or not) isn't until it knows
  readonly property bool ready: root.backend?.ready ?? true

  // What the compositor can do, by capability (contract.md › Capabilities):
  // false for anything the backend doesn't say, and for what
  // AXIOM_COMPOSITOR_OFF ("focusGrab,blur") turns off, so the
  // fallbacks can be tried on a compositor that has them
  readonly property var supports: {
    const own = root.backend?.supports ?? {};
    const off = String(Quickshell.env("AXIOM_COMPOSITOR_OFF") ?? "").split(",").map(name => name.trim());
    return Object.keys(own).reduce((result, name) => {
      result[name] = own[name] === true && !off.includes(name);
      return result;
    }, {});
  }

  // The binds the compositor carries out itself, so it can't be told to
  // (niri's Mod + drag): { action: key, as axiom writes it }. The Keybinds
  // page says so of a bind with that action instead of flagging it
  readonly property var builtInBinds: root.backend?.builtInBinds ?? ({})

  // Appearance's surfaces are translucent only where the compositor blurs
  // behind them (Appearance.compositorBlurs: readers don't read services).
  // Never at the login screen: its compositor runs no blur rules, and the
  // greeter draws solid, unfrosted cards (a SwayFX there blurs nothing)
  property Binding _appearanceBlur: Binding {
    target: Appearance
    property: "compositorBlurs"
    value: root.supports.blur === true && !Paths.greeter
  }

  // --- State (contract.md › Shapes) ---

  // Every mapped window: [{ id, appId, initialAppId, title, workspaceId,
  // workspaceName, output, floating, fullscreen, maximized, hidden,
  // focusRank, x, y, w, h }]
  readonly property var windows: root.backend?.windows ?? []
  // Every monitor: [{ name, description, x, y, width, height, scale,
  // focused, activeWorkspaceId, specialWorkspaceId, reserved }]
  readonly property var outputs: root.backend?.outputs ?? []
  // Every workspace: [{ id, name, output, windowCount, active, focused }]
  readonly property var workspaces: root.backend?.workspaces ?? []
  // The focused monitor's name, or "" with none
  readonly property string focusedOutput: root.backend?.focusedOutput ?? ""
  // The focused window's id, or ""
  readonly property string activeWindowId: root.backend?.activeWindowId ?? ""
  // The gaps the compositor leaves at the screen edges, after reserved
  // zones ({ top, right, bottom, left })
  readonly property var gapsOut: root.backend?.gapsOut ?? ({
      "top": 0,
      "right": 0,
      "bottom": 0,
      "left": 0
    })
  // The compositor's blur as in effect ({ enabled, size, passes }). With
  // none, the strength is Hyprland's default, which the lock screen's and
  // the desktop's own frosting imitate (ScreenLayoutView.hyprBlur)
  readonly property var blur: root.backend?.blur ?? ({
      "enabled": false,
      "size": 8,
      "passes": 1
    })
  // A tiled box wider than tall times this splits side by side
  readonly property real splitWidthMultiplier: root.backend?.splitWidthMultiplier ?? 1
  // Whether surfaces with a fixed stacking order (bars, border, docks,
  // edge menus, the desktop) may map yet: the backend's stacking is in
  readonly property bool surfacesReady: root.backend?.surfacesReady ?? true

  // The output showing a screen, or null
  function outputFor(screen) {
    return screen ? root.output(screen.name) : null;
  }

  // The output named `name`, or null
  function output(name) {
    return root.outputs.find(o => o.name === name) ?? null;
  }

  // The focused output, or null
  readonly property var focused: root.output(root.focusedOutput)

  // The focused output's active workspace id (1 while unknown)
  function activeWorkspaceId() {
    const id = root.focused?.activeWorkspaceId ?? -1;
    return id > 0 ? id : 1;
  }

  // Re-reads the outputs and windows soon
  function refresh() {
    root.backend?.refresh();
  }

  // --- Events ---

  // A layer surface opened or closed
  signal layersChanged
  // A monitor was added or removed
  signal outputsHotplugged
  // The compositor reloaded its config
  signal configReloaded
  // The keyboard layout switched
  signal keyboardLayoutChanged
  // A window was focused; appId is its app id (class)
  signal windowFocused(string appId)

  Connections {
    target: root.backend
    ignoreUnknownSignals: true

    function onLayersChanged() {
      root.layersChanged();
    }
    function onOutputsHotplugged() {
      root.outputsHotplugged();
    }
    function onConfigReloaded() {
      root.configReloaded();
    }
    function onKeyboardLayoutChanged() {
      root.keyboardLayoutChanged();
    }
    function onWindowFocused(appId) {
      root.windowFocused(appId);
    }
  }

  // --- Windows ---

  // Focuses a window. One on another workspace goes through goToWorkspace,
  // to slide like any other switch.
  function focusWindow(id) {
    const win = root.windows.find(w => w.id === id);
    const out = root.output(win?.output ?? "");
    const workspaceId = win?.workspaceId ?? -1;
    if (!out || workspaceId <= 0 || workspaceId === out.activeWorkspaceId)
      root.backend?.activateWindow(id);
    else
      root.goToWorkspace(workspaceId, "go", out.name, id);
  }

  function closeWindow(id) {
    root.backend?.closeWindow(id);
  }

  // Opens, closes or toggles the compositor's own overview (`verb`: open,
  // close, toggle), with `supports.overview`: axiom's workspace overview
  // stands aside for it when WorkspaceOverlay's compositorOverview is on
  function compositorOverview(verb) {
    if (root.supports.overview)
      root.backend.overview(verb);
  }

  // The overview's drag and drop (the backend's placeWindow)
  function placeWindow(id, workspaceId, targetId, side, restore, reinsert, floatAt) {
    root.backend?.placeWindow(id, workspaceId, targetId, side, restore, reinsert, floatAt);
  }

  // The overview's resize (the backend's resizeWindow)
  function resizeWindow(id, dw, dh, dx, dy) {
    root.backend?.resizeWindow(id, dw, dh, dx, dy);
  }

  // The live Wayland toplevel of a window (for previews), or null
  function toplevelFor(id) {
    return root.backend?.toplevelFor(id) ?? null;
  }

  // Whether the named output's active workspace, or the special workspace
  // open on it, shows a fullscreen window (maximized ones don't count:
  // they leave reserved space alone)
  function hasFullscreen(name) {
    const out = root.output(name);
    const ids = [out?.activeWorkspaceId ?? -1, out?.specialWorkspaceId ?? 0].filter(id => id !== -1 && id !== 0);
    return ids.length > 0 && root.windows.some(w => ids.includes(w.workspaceId) && w.fullscreen);
  }

  // The largest window on a workspace (its icon stands for the workspace),
  // or null
  function biggestWindowForWorkspace(workspaceId) {
    const area = w => (w?.w ?? 0) * (w?.h ?? 0);
    return root.windows.filter(w => w.workspaceId === workspaceId).reduce((biggest, w) => area(w) > area(biggest) ? w : biggest, null);
  }

  // A workspace's windows in strip order (WorkspaceGeometry.stripOrder)
  function stripWindows(workspaceId, vertical) {
    return WorkspaceGeometry.stripOrder(root.windows.filter(w => w.workspaceId === workspaceId && !w.hidden), vertical);
  }

  // Of `windows`, the one focused last (focused now, if any is), or null
  function lastFocused(windows) {
    return windows.reduce((last, w) => last === null || (w.focusRank ?? Infinity) < (last.focusRank ?? Infinity) ? w : last, null);
  }

  // --- Session, input, cursor ---

  // Sets up a compositor running no config of axiom's (the greeter's) from
  // the bundle's monitor profiles and Input values (greeter.compositor):
  // axiom sends Hyprland Lua keeping the monitors in the profile for what's
  // connected and the x-greeter input, then the cursor; sway its input and
  // seat commands (its monitors: applyOutputs); niri takes input from its
  // config file alone
  function setUpGreeter(profiles, input) {
    BackendManager.call("greeter.compositor", {
      "profiles": profiles,
      "input": input
    }, error => {
      if (error)
        console.warn("[CompositorManager] setting up the greeter's compositor:", error.message);
    });
  }

  // Calls back with the main keyboard's layouts ({ layouts, index,
  // keymap }), or null
  function withKeyboard(callback) {
    if (root.backend)
      root.backend.withKeyboard(callback);
    else
      callback(null);
  }

  // Switches every keyboard to its "next" or "prev" layout, then calls back
  function cycleKeyboardLayout(direction, callback) {
    if (root.backend)
      root.backend.cycleKeyboardLayout(direction, callback);
    else
      callback?.();
  }

  // Calls back with each output's layer surfaces ({ [output]: { w, h,
  // layers: [{ namespace, x, y, w, h }] } }), or null when unknown
  function withLayerRects(callback) {
    if (root.backend)
      root.backend.withLayerRects(callback);
    else
      callback(null);
  }

  // Calls back with the cursor's global position ({ x, y }), or null when
  // the compositor can't say
  function withCursorPos(callback) {
    if (root.supports.cursorPos)
      root.backend.withCursorPos(callback);
    else
      callback(null);
  }

  // Calls back with the name of the screen under the cursor (the focused
  // one if the compositor can't say)
  function withHoveredScreen(callback) {
    root.withCursorPos(pos => callback((pos ? root._screenAt(pos.x, pos.y) : "") || root.focusedOutput || General.primaryMonitor));
  }

  function _screenAt(x, y) {
    for (const screen of General.outputs) {
      if (x >= screen.x && x < screen.x + screen.width && y >= screen.y && y < screen.y + screen.height)
        return screen.name;
    }
    return "";
  }

  // Moves the cursor to (x, y) inside one of axiom's layer surfaces (the
  // one in `namespace` on `output`, `width` × `height`), where the
  // compositor can
  function warpCursorToLayer(namespace, output, width, height, x, y) {
    if (root.supports.cursorWarp)
      root.backend.warpCursorToLayer(namespace, output, width, height, x, y);
  }

  // Ends the session (the power menu's log out)
  function exitSession() {
    root.backend?.exitSession();
  }

  // --- Outputs (the Monitors page) ---

  // Calls back with every output in detail, disabled ones too ({ name,
  // description, width, height, refreshRate, x, y, scale, transform,
  // disabled, mirrorOf, vrr, availableModes, … }, contract.md), or null.
  // Needs monitors
  function withOutputDetails(callback) {
    if (root.supports.monitors)
      root.backend.withOutputDetails(callback);
    else
      callback(null);
  }

  // Sets the outputs as `rules` (MonitorRule) say, now; `details` are the
  // outputs as withOutputDetails gave them. axiom sends them to the
  // compositor (outputs.apply); the backend reads its state again after
  // (outputsApplied). Needs monitors
  function applyOutputs(rules, details) {
    if (!root.supports.monitors)
      return;
    BackendManager.call("outputs.apply", {
      "rules": rules,
      "details": details
    }, error => {
      if (error)
        console.warn("[CompositorManager] setting the outputs:", error.message);
      root.backend.outputsApplied();
    });
  }

  // --- Binds (the Keybinds page) ---

  // Calls back with the compositor's binds in effect ({ modmask, key,
  // keycode, description, submap }, BindKeys), or null. Needs bindMerge
  function withBinds(callback) {
    if (root.supports.bindMerge)
      root.backend.withMainBinds(callback);
    else
      callback(null);
  }

  // While on, every key reaches axiom instead of the compositor's binds
  // (the key recorder). Needs keyCapture
  function captureKeys(on) {
    if (root.supports.keyCapture)
      root.backend.captureKeys(on);
  }

  // --- Workspaces (laid out by WorkspacesConfig) ---

  // Goes to workspace `id`. mode: "go" (default), "move" (taking the
  // focused window along) or "moveSilent" (sending it there, staying put).
  // In a grid or perMonitor layout only the output's own workspaces (and
  // with dynamic workspaces, those it borrows) are reachable (`output`, a
  // name, the focused one by default), and it goes
  // by column, then row, sliding along each in turn (WorkspacesConfig.
  // animate). The standard and perMonitor layouts are one row (columns =
  // count), so they only ever slide sideways. Callers on an output's
  // surface pass its name, and it's focused first. `focusId` (focusWindow)
  // arrives by focusing that window instead of the bare workspace.
  function goToWorkspace(id, mode, output, focusId) {
    if (!Number.isInteger(id) || id < 1) {
      console.warn(`[CompositorManager] Not a workspace id: ${id}`);
      return;
    }
    if (!root.backend)
      return;
    mode = mode || "go";
    output = output || root.focusedOutput;
    const base = workspaceBase(output);
    const size = root.blockSize;
    if (root.perMonitorBlocks && (id < base || id >= base + size) && workspaceIds(output).indexOf(id) < 0) {
      if (focusId)
        root.backend.activateWindow(focusId);
      else
        console.warn(`[CompositorManager] workspace ${id} is outside ${output || "the focused output"}'s workspaces (${base}-${base + size - 1})`);
      return;
    }
    const focused = output === root.focusedOutput;
    const current = focused ? _currentWorkspaceId() : (root.output(output)?.activeWorkspaceId ?? -1);
    if (id === current) {
      if (focusId)
        root.backend.activateWindow(focusId);
      return;
    }
    if (mode === "moveSilent") {
      root.backend.sendWindowToWorkspace(id);
      return;
    }
    // A new switch replaces the rest of one still sliding, and slides on
    // from wherever that one has got to
    const midway = root.backend.travelingTo ?? -1;
    const at = midway > 0 ? midway : current;
    root._lastGo = {
      "id": id,
      "time": Date.now()
    };
    // Dynamic workspaces are one column: every switch slides vertically
    const cols = root.dynamicWorkspaces ? 1 : WorkspacesConfig.columns;
    const from = at - base;
    const to = id - base;
    const legs = [];
    if (WorkspacesConfig.animate && root.supports.workspaceSlide && from >= 0 && from < size) {
      if (from % cols !== to % cols)
        legs.push({
          "id": base + Math.floor(from / cols) * cols + to % cols,
          "axis": "x"
        });
      if (Math.floor(from / cols) !== Math.floor(to / cols))
        legs.push({
          "id": id,
          "axis": "y"
        });
    }
    if (legs.length === 0)
      legs.push({
        "id": id,
        "axis": ""
      });
    // Without the output focused, a new workspace would open on the
    // focused one
    root.backend.travel(focused || !output ? "" : output, legs, mode, focusId ?? "");
  }

  // A step about to wrap round the grid's ends on `output` (its name):
  // along a row (`alongRow`, the standard layout's only kind) or a column,
  // `forward` past the last. The bar switchers' active box leaves one end
  // and comes in at the other instead of sliding back across.
  signal workspaceWrapped(string output, bool alongRow, bool forward)

  // One step left/right/up/down from the current workspace: within the
  // output's grid, or through 1..count in the standard layout (where up is
  // previous and down next). Stops at the edges unless WorkspacesConfig.wrap.
  function stepWorkspace(direction, mode) {
    if (root.dynamicWorkspaces) {
      root._stepDynamic(direction, mode);
      return;
    }
    const base = workspaceBase(root.focusedOutput);
    const size = WorkspacesConfig.size;
    const index = _currentWorkspaceId() - base;
    if (index < 0 || index >= size) {
      goToWorkspace(base, mode);
      return;
    }
    const cols = WorkspacesConfig.grid ? WorkspacesConfig.columns : size;
    const rows = WorkspacesConfig.grid ? WorkspacesConfig.rows : 1;
    if (!WorkspacesConfig.grid && (direction === "up" || direction === "down"))
      direction = direction === "up" ? "left" : "right";
    let col = index % cols + (direction === "left" ? -1 : direction === "right" ? 1 : 0);
    let row = Math.floor(index / cols) + (direction === "up" ? -1 : direction === "down" ? 1 : 0);
    if (col < 0 || col >= cols || row < 0 || row >= rows) {
      if (!WorkspacesConfig.wrap)
        return;
      root.workspaceWrapped(root.focusedOutput, col < 0 || col >= cols, direction === "right" || direction === "down");
      col = (col + cols) % cols;
      row = (row + rows) % rows;
    }
    goToWorkspace(base + row * cols + col, mode);
  }

  // A step where the compositor keeps one list of workspaces per output
  // (dynamicWorkspaces): up and down through the focused output's list
  // (wrapping round with WorkspacesConfig.wrap), left and right to the
  // output that way, taking the focused window along unless `mode` is "go"
  function _stepDynamic(direction, mode) {
    if (direction === "left" || direction === "right") {
      const to = WorkspaceGeometry.outputToward(root.outputs, root.focusedOutput, direction);
      if (to === "")
        return;
      if (mode === "move" || mode === "moveSilent")
        root.backend.moveWindowToOutput(to, mode === "move");
      else
        root.backend.focusOutput(to);
      return;
    }
    const ids = workspaceIds(root.focusedOutput);
    if (ids.length === 0)
      return;
    const at = ids.indexOf(_currentWorkspaceId());
    let next = at < 0 ? 0 : at + (direction === "up" ? -1 : 1);
    if (next < 0 || next >= ids.length) {
      if (!WorkspacesConfig.wrap)
        return;
      root.workspaceWrapped(root.focusedOutput, true, direction === "down");
      next = (next + ids.length) % ids.length;
    }
    goToWorkspace(ids[next], mode);
  }

  // The n-th workspace (1-based) of the current row in a grid or perMonitor
  // layout, or workspace n in the standard layout (number keybinds)
  function nthWorkspace(n, mode) {
    // The n-th of the output's list, its last (the empty one) past its end
    if (root.dynamicWorkspaces) {
      const ids = workspaceIds(root.focusedOutput);
      if (n >= 1 && ids.length > 0)
        goToWorkspace(ids[Math.min(n, ids.length) - 1], mode);
      return;
    }
    if (!root.perMonitorBlocks) {
      goToWorkspace(n, mode);
      return;
    }
    const cols = WorkspacesConfig.columns;
    if (n < 1 || n > cols)
      return;
    const base = workspaceBase(root.focusedOutput);
    const index = Math.min(Math.max(_currentWorkspaceId() - base, 0), WorkspacesConfig.size - 1);
    goToWorkspace(base + Math.floor(index / cols) * cols + n - 1, mode);
  }

  // "horizontal" | "vertical" on a strip monitor (its name), else "",
  // always "" where the compositor has no strips (a config from Hyprland
  // may still list them), always "horizontal" where it has nothing else
  function stripDirection(screenName) {
    // Every output is a strip where the compositor only scrolls (niri)
    if (root.supports.stripsAlways === true)
      return "horizontal";
    return root.supports.strips ? WorkspacesConfig.stripDirection(screenName) : "";
  }

  // Scrolls the strip of an output's active workspace a column on (1) or
  // back (-1). Layout messages act on the focused workspace, so only on the
  // focused output, and only with windows to scroll.
  function stepStrip(direction, output) {
    if (!root.supports.strips || !output || output !== root.focusedOutput)
      return;
    const active = root.output(output)?.activeWorkspaceId ?? -1;
    if (root.windows.some(w => w.workspaceId === active))
      root.backend.scrollStrip(direction);
  }

  // A scroll bind's step (the scrollStep action): along the focused
  // output's strip where it has one (focus follows), else to the workspace
  // that way. Right and down go forward.
  function scrollStep(direction) {
    if (root.stripDirection(root.focusedOutput) !== "")
      root.stepStrip(direction === "right" || direction === "down" ? 1 : -1, root.focusedOutput);
    else
      root.stepWorkspace(direction, "go");
  }

  // The last workspace gone to, for a moment: key presses can come faster
  // than the compositor reports the switch
  property var _lastGo: ({
      "id": -1,
      "time": 0
    })

  function _currentWorkspaceId() {
    if ((root.backend?.travelingTo ?? -1) > 0 || Date.now() - root._lastGo.time < 300)
      return root._lastGo.id;
    return activeWorkspaceId();
  }

  // First workspace id an output (its name) shows: 1 in the standard
  // layout, else its block's (grid/perMonitor: one block per monitor the
  // saved profiles name, connected or not, then per connected one they
  // don't, so a hotplug never moves a block; WorkspaceGeometry.blockBases)
  function workspaceBase(output) {
    return root.perMonitorBlocks ? (root._bases[output] ?? 1) : 1;
  }

  // Whether each output has a block of ids of its own: the grid and
  // perMonitor layouts, and every layout where the compositor's workspaces
  // belong to an output (supports.outputWorkspaces: niri's), as the
  // standard layout's shared ids can't
  readonly property bool perMonitorBlocks: WorkspacesConfig.perMonitorBlocks || root.supports.outputWorkspaces === true
  // reads: Monitors.items.*.outputs.*.output, Monitors.items.*.outputs.*.label
  readonly property var _bases: WorkspaceGeometry.blockBases(root.outputs, General.primaryMonitor, root.blockSize, MonitorsConfig.profiles)

  // Whether the compositor makes and removes workspaces itself, one list
  // per output (supports.dynamicWorkspaces: niri's). The Workspaces
  // section's layout doesn't apply: its workspaces are the ones it has
  readonly property bool dynamicWorkspaces: root.supports.dynamicWorkspaces === true
  // Whether they're axiom's, kept so by the backend for the scrolling
  // layout (Hyprland: WorkspacesConfig.scrolling), rather than the
  // compositor's own (niri), where the layout doesn't apply at all
  readonly property bool dynamicByLayout: root.dynamicWorkspaces && root.backend?.dynamicByLayout === true
  // Whether the workspaces are laid out in a grid: the grid layout, where
  // the compositor leaves the workspaces to axiom
  readonly property bool workspaceGrid: WorkspacesConfig.grid && !root.dynamicWorkspaces
  // How many ids each output's block holds: the layout's size, or the
  // backend's own where its workspaces are dynamic
  readonly property int blockSize: root.dynamicWorkspaces ? root.backend.blockSize : WorkspacesConfig.size

  // The workspace ids an output (its name) shows, in order: the layout's,
  // or the ones the compositor has where they're dynamic
  function workspaceIds(output) {
    if (root.dynamicWorkspaces)
      return root.workspaces.filter(ws => ws.output === output).map(ws => ws.id);
    const base = workspaceBase(output);
    const ids = [];
    for (let i = 0; i < WorkspacesConfig.size; i++)
      ids.push(base + i);
    return ids;
  }

  // The outputs in block order, each with its block (its index, from
  // _bases)
  function orderedOutputs() {
    return root.outputs.map(o => ({
          "name": o.name,
          "block": Math.round((root._bases[o.name] - 1) / root.blockSize),
          "active": o.activeWorkspaceId,
          "focused": o.focused
        })).sort((a, b) => a.block - b.block);
  }

  // A switch made outside goToWorkspace (a remap), as the last one gone to
  function noteSwitch(id) {
    root._lastGo = {
      "id": id,
      "time": Date.now()
    };
  }

  // Remaps the workspaces on a layout change, starts a grid at its centre
  property WorkspaceRemap _remap: WorkspaceRemap {
    manager: root
  }

  Component.onCompleted: _remap.begin()

  // `axiom ipc workspaces …`, for workspace keybinds. mode:
  // "go", "move" (take the focused window along) or "moveSilent"
  property IpcTarget _ipc: IpcTarget {
    target: "workspaces"

    function go(id: string): void {
      root.goToWorkspace(parseInt(id), "go");
    }

    function move(id: string): void {
      root.goToWorkspace(parseInt(id), "move");
    }

    function moveSilent(id: string): void {
      root.goToWorkspace(parseInt(id), "moveSilent");
    }

    // The n-th of the current row (grid), or workspace n (standard)
    function nth(n: string, mode: string): void {
      root.nthWorkspace(parseInt(n), mode);
    }

    // Moves workspaces left outside their output's ids (by a change made
    // while axiom wasn't running) back into them
    function reconcile(): void {
      root._remap.reconcile();
    }

    // direction: left, right, up or down
    function step(direction: string, mode: string): void {
      root.stepWorkspace(direction, mode);
    }

    // A column along the focused output's strip, else a workspace step
    // (scrollStep); direction: left, right, up or down
    function scroll(direction: string): void {
      root.scrollStep(direction);
    }

    function left(): void {
      root.stepWorkspace("left", "go");
    }

    function right(): void {
      root.stepWorkspace("right", "go");
    }

    function up(): void {
      root.stepWorkspace("up", "go");
    }

    function down(): void {
      root.stepWorkspace("down", "go");
    }
  }
}
