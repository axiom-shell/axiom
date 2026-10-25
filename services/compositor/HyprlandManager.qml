// Adapted from end-4's dots-hyprland
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.config
import qs.components.methods

/* CompositorManager's backend on Hyprland (docs/dev/compositor/contract.md):
 * Hyprland's state as the compositor-neutral shapes (HyprState), and the
 * primitives CompositorManager builds on. Also what only the Hyprland
 * features use (runLua, options, binds, outputs as Hyprland has them). The
 * only reader of Quickshell.Hyprland outside the Hyprland* services
 * (docs/dev/hyprland/ipc.md). */
Singleton {
  id: root

  // --- Backend state (docs/dev/compositor/contract.md) ---

  // The windows (HyprState.window), from j/clients
  property var windows: []
  // The monitors (HyprState.output)
  readonly property var outputs: Hyprland.monitors.values.map(m => HyprState.output(m, m === Hyprland.focusedMonitor))
  // The workspaces (HyprState.workspace). Under the scrolling layout,
  // niri's: each output's from its first id, with an empty one after the
  // last (DynamicWorkspaces.workspaces), kept so by _compaction
  readonly property var workspaces: {
    const real = Hyprland.workspaces.values.map(ws => HyprState.workspace(ws));
    return root.dynamicByLayout ? DynamicWorkspaces.workspaces(real, root._bases, root.blockSize) : real;
  }
  // The focused monitor's name, or "" while Hyprland has none
  readonly property string focusedOutput: Hyprland.focusedMonitor?.name ?? ""
  // The focused window's id (its "0x…" address), or ""
  readonly property string activeWindowId: Hyprland.activeToplevel ? "0x" + Hyprland.activeToplevel.address : ""
  // What Hyprland does (CompositorManager.supports)
  readonly property var supports: ({
      "configModes": true,
      "keybinds": true,
      "monitors": true,
      "switcher": true,
      "switcherRelease": true,
      "strips": true,
      "dynamicWorkspaces": root.dynamicByLayout,
      "focusGrab": true,
      "blurThreshold": true,
      "layerOrder": true,
      "blur": true,
      "cursorPos": true,
      "cursorWarp": true,
      "windowGeometry": true,
      "outputCapture": true,
      "layerFrameSync": true,
      "workspaceSlide": true,
      "windowBorders": true,
      "windowShape": true,
      "windowRounding": true,
      "windowGaps": true,
      "windowBlur": true,
      "windowShadow": true,
      "windowDim": true,
      "windowOpacity": true,
      "inputConfig": true,
      "keyCapture": true,
      "modifierTap": true,
      "bindMerge": true,
      "monitorColor": true,
      "monitorMirror": true,
      "namedSpecial": true,
      "mouseBinds": true,
      "pseudoTile": true,
      "splitToggle": true,
      "pin": true,
      "windowGroups": true,
      "outputProfiles": true
    })

  // Whether the workspaces are niri's, kept by axiom (the scrolling layout,
  // WorkspacesConfig.scrolling) rather than the layout's fixed ids. Never
  // in the greeter, which has no windows to keep
  readonly property bool dynamicByLayout: WorkspacesConfig.scrolling && !Paths.greeter
  // Ids in each output's block while the workspaces are dynamic
  // (CompositorManager.blockSize): more than anyone opens
  readonly property int blockSize: 100
  // Each output's first id while they're dynamic, as CompositorManager
  // numbers them (WorkspaceGeometry.blockBases)
  readonly property var _bases: WorkspaceGeometry.blockBases(root.outputs, General.primaryMonitor, root.blockSize)

  // Re-reads the monitors and the windows soon (Quickshell re-reads the
  // monitors' lastIpcObject only on monitor events)
  function refresh() {
    Hyprland.refreshMonitors();
    root._debounce.restart();
  }

  // --- Events, from Hyprland's event socket ---

  // A layer surface opened or closed (openlayer / closelayer)
  signal layersChanged
  // A monitor was added or removed
  signal outputsHotplugged
  // Hyprland reloaded its config (binds, options and runtime state reset)
  signal configReloaded
  // The keyboard layout switched (activelayout)
  signal keyboardLayoutChanged
  // A window was focused; appId is its class
  signal windowFocused(string appId)
  // A window switcher key (HyprLua.switcherEvent): verb `step` (argument
  // the step), `commit` or `cancel`
  signal switcherKey(string verb, string argument)

  // Leaves the window switcher's submap and its release listener (a tile
  // was clicked while its keys were held)
  function leaveSwitcher() {
    root.runLua(HyprLua.switcherLeaveLua);
  }

  // --- Actions ---

  // The Lua window selector for a window id (its "0x…" address).
  // Dispatchers take it as `window`; without one they act on the focused
  // window.
  function _window(id) {
    return `"address:${id}"`;
  }

  function closeWindow(id) {
    Hyprland.dispatch(`hl.dsp.window.close({ window = ${_window(id)} })`);
  }

  // Focuses a window where it is (CompositorManager.focusWindow switches
  // workspace first, sliding)
  function activateWindow(id) {
    Hyprland.dispatch(_focusWindowDispatcher(id));
  }

  function _focusWindowDispatcher(id) {
    return `hl.dsp.focus({ window = ${_window(id)} })`;
  }

  // Moves a window onto a workspace, tiling it on `side` ("left" | "right" |
  // "top" | "bottom") of `targetId`, or wherever when there's none.
  // Dwindle opens a moved window on the node nearest the cursor, and on the
  // focused window's when that's on the (active) workspace, then picks the
  // half by the cursor. So the chunk focuses the target if needed, warps the
  // cursor into the target's half and moves the window, then puts the cursor
  // back at `restore` (global). The target's box is read after the window has
  // left its workspace (`reinsert`: same workspace, moved out first), since
  // that reflows the layout. A floating window goes to `floatAt` instead.
  // On a strip the window opens as a new column after the focused target,
  // whatever the side.
  function placeWindow(id, workspaceId, targetId, side, restore, reinsert, floatAt) {
    const win = _window(id);
    const lines = [];
    if (floatAt) {
      if (!reinsert)
        lines.push(`run(function() return hl.dsp.window.move({ workspace = ${workspaceId}, follow = false, window = ${win} }) end)`);
      lines.push(`run(function() return hl.dsp.window.move({ x = ${Math.round(floatAt.x)}, y = ${Math.round(floatAt.y)}, window = ${win} }) end)`);
    } else {
      if (reinsert)
        lines.push(`run(function() return hl.dsp.window.move({ workspace = "name:axiom-drop", follow = false, window = ${win} }) end)`);
      if (targetId)
        lines.push(`aim(${_window(targetId)}, "${side}")`);
      lines.push(`run(function() return hl.dsp.window.move({ workspace = ${workspaceId}, follow = false, window = ${win} }) end)`);
      lines.push(`run(function() return hl.dsp.cursor.move({ x = ${Math.round(restore.x)}, y = ${Math.round(restore.y)} }) end)`);
    }
    _eval(_luaPrelude + lines.join("\n") + _luaEpilogue);
  }

  // Grows a window by (dw, dh) and moves it by (dx, dy). On a tiled window a
  // delta moves its nearest split by that much (dwindle smart resizing), so
  // the split follows the mouse; dx/dy only apply to floating windows.
  function resizeWindow(id, dw, dh, dx, dy) {
    const win = _window(id);
    const lines = [];
    if (dw !== 0 || dh !== 0)
      lines.push(`run(function() return hl.dsp.window.resize({ x = ${Math.round(dw)}, y = ${Math.round(dh)}, relative = true, window = ${win} }) end)`);
    if (dx !== 0 || dy !== 0)
      lines.push(`run(function() return hl.dsp.window.move({ x = ${Math.round(dx)}, y = ${Math.round(dy)}, relative = true, window = ${win} }) end)`);
    if (lines.length > 0)
      _eval(_luaPrelude + lines.join("\n") + _luaEpilogue);
  }

  // Moves the cursor to (x, y) inside one of axiom's layer surfaces: the
  // mapped one in `namespace` on `monitor` that is `width` × `height`
  // (layer-shell windows don't know where they are on screen, Hyprland
  // does). Nothing happens if none matches.
  function warpCursorToLayer(namespace, monitor, width, height, x, y) {
    _eval(`for _, l in ipairs(hl.get_layers({ namespace = ${JSON.stringify(namespace)} })) do
  if l.mapped and l.monitor and l.monitor.name == ${JSON.stringify(monitor)} and math.abs(l.w - ${Math.round(width)}) <= 1 and math.abs(l.h - ${Math.round(height)}) <= 1 then
    hl.dispatch(hl.dsp.cursor.move({ x = l.x + ${Math.round(x)}, y = l.y + ${Math.round(y)} }))
    return
  end
end`);
  }

  // Every step runs even if an earlier one fails (so the cursor always goes
  // back); the failures are raised together at the end, and logged.
  // aim(): focus the target if it's on its monitor's active workspace, then
  // warp into the middle of its `side` half. Dwindle splits side by side when
  // the box is wider than tall (split_width_multiplier), so a side along the
  // other axis falls back to first/second half on the axis dwindle will use.
  readonly property string _luaPrelude: `local errs = {}
local function run(f)
  local ok, e = pcall(function() hl.dispatch(f()) end)
  if not ok then errs[#errs + 1] = tostring(e) end
end
local function aim(sel, side)
  local t = hl.get_window(sel)
  if not t then errs[#errs + 1] = "target not found"; return end
  local x, y = t.at.x or t.at[1], t.at.y or t.at[2]
  local w, h = t.size.x or t.size[1], t.size.y or t.size[2]
  local first = side == "left" or side == "top"
  local px, py = x + w / 2, y + h / 2
  if w > h * ${splitWidthMultiplier} then
    px = first and x + w / 4 or x + w * 3 / 4
  else
    py = first and y + h / 4 or y + h * 3 / 4
  end
  if t.workspace and t.workspace.active then
    run(function() return hl.dsp.focus({ window = sel }) end)
  end
  run(function() return hl.dsp.cursor.move({ x = px, y = py }) end)
end
`
  readonly property string _luaEpilogue: `
if #errs > 0 then error(table.concat(errs, "; ")) end`

  // Lua chunks run one at a time, in order (HyprlandIpcManager.evalLua):
  // [{ lua, callback }]
  property var _evalQueue: []
  property bool _evaluating: false

  // Runs a Lua chunk in Hyprland (config functions like hl.bind or
  // hl.config, which a dispatch can't call) after the chunks queued before
  // it, then calls back with Hyprland's reply ("ok" or the error); failures
  // are logged. For the Hyprland features only.
  function runLua(lua, callback) {
    _eval(lua, callback);
  }

  // Re-reads the options axiom follows (gaps, split ratio, the workspaces
  // animation), after something changed them at runtime: once the queued
  // Lua has run, which may be what changes them
  // axiom's config layer changed Hyprland at runtime (the daemon's
  // compositor.applied): its options are read again
  function layerApplied() {
    refreshOptions();
  }

  function refreshOptions() {
    if (_evaluating || _evalQueue.length > 0) {
      _refreshAfterEval = true;
      return;
    }
    if (_readingOptions) {
      _optionsAgain = true;
      return;
    }
    _readingOptions = true;
    // Those waiting get this read's answer: it started after they asked
    const waiting = _optionsWaiting;
    _optionsWaiting = [];
    HyprlandIpcManager.jsonBatch(["getoption general:gaps_out", "getoption dwindle:split_width_multiplier", "getoption decoration:blur:enabled", "getoption decoration:blur:size", "getoption decoration:blur:passes", "getoption animations:enabled", "animations"], replies => {
      root._readingOptions = false;
      root._readOptions(replies);
      waiting.forEach(callback => callback());
      if (root._optionsAgain) {
        root._optionsAgain = false;
        root.refreshOptions();
      }
    });
  }

  property bool _readingOptions: false
  property bool _optionsAgain: false
  property var _optionsWaiting: []

  // Reads the options again (refreshOptions), then calls back with the
  // animations as read
  function withAnimations(callback) {
    _optionsWaiting.push(() => callback(root.animations));
    refreshOptions();
  }

  function _readOptions([gaps, split, blurEnabled, blurSize, blurPasses, animationsEnabled, animations]) {
    root.gapsOut = _gapSides(gaps) ?? root.gapsOut;
    const multiplier = Number(split?.float);
    if (multiplier > 0)
      root.splitWidthMultiplier = multiplier;
    const blur = {
      "enabled": blurEnabled?.int === 1 || blurEnabled?.bool === true,
      "size": Number(blurSize?.int),
      "passes": Number(blurPasses?.int)
    };
    if (blur.size > 0 && blur.passes > 0 && JSON.stringify(blur) !== JSON.stringify(root.blur))
      root.blur = blur;
    if (animationsEnabled)
      root.animationsEnabled = animationsEnabled.int !== 0 && animationsEnabled.bool !== false;
    if (Array.isArray(animations))
      root.animations = animations;
  }

  function _eval(lua, callback) {
    _evalQueue.push({
      "lua": lua,
      "callback": callback
    });
    if (!_evaluating)
      _nextEval();
  }

  property bool _refreshAfterEval: false

  function _nextEval() {
    if (_evalQueue.length === 0) {
      if (_refreshAfterEval) {
        _refreshAfterEval = false;
        refreshOptions();
      }
      root._debounce.restart();
      return;
    }
    _evaluating = true;
    const chunk = _evalQueue.shift();
    HyprlandIpcManager.evalLua(chunk.lua, reply => {
      if (reply !== "ok")
        console.warn("[HyprlandManager] Lua eval:", reply || "no reply from Hyprland");
      root._evaluating = false;
      chunk.callback?.(reply);
      root._nextEval();
    });
  }

  // --- For the other services: what they need from the compositor, in
  // shapes that don't depend on it (HyprState) ---

  // Calls back with the main keyboard's layouts ({ layouts, index, keymap },
  // HyprState.keyboard), or null
  function withKeyboard(callback) {
    HyprlandIpcManager.json("devices", devices => callback(HyprState.keyboard(devices)));
  }

  // Switches every keyboard to its "next" or "prev" layout, then calls back
  function cycleKeyboardLayout(direction, callback) {
    HyprlandIpcManager.request("switchxkblayout all " + direction, () => callback?.());
  }

  // Calls back with each monitor's layer surfaces (HyprState.layerRects),
  // or null when Hyprland didn't answer
  function withLayerRects(callback) {
    HyprlandIpcManager.jsonBatch(["monitors", "layers"], ([monitors, layers]) => callback(Array.isArray(monitors) && layers ? HyprState.layerRects(monitors, layers) : null));
  }

  // Calls back with every output, disabled ones too, or null (the output
  // details of docs/dev/compositor/contract.md, which are Hyprland's
  // monitors as JSON)
  function withOutputDetails(callback) {
    HyprlandIpcManager.json("monitors all", outputs => callback(Array.isArray(outputs) ? outputs : null));
  }

  // Sets the outputs as `rules` (MonitorRule) say now, `details` being the
  // outputs as withOutputDetails gave them (for a mirror's connector)
  function applyOutputs(rules, details) {
    const mirrorName = output => MonitorLayout.find(output, details)?.name ?? "";
    root.runLua(HyprLua.monitorCalls(rules, mirrorName).join("\n"));
  }

  // Calls back with Hyprland's version ("0.56.2"), or "" when it didn't
  // answer
  function withVersion(callback) {
    HyprlandIpcManager.json("version", version => callback(String(version?.version ?? version?.tag ?? "").replace(/^v/, "")));
  }

  // Calls back with every bind Hyprland has (its binds as JSON: modmask,
  // key, keycode, submap, description, dispatcher, arg, …), or null
  function withBinds(callback) {
    HyprlandIpcManager.json("binds", binds => callback(Array.isArray(binds) ? binds : null));
  }

  // Calls back with the binds in effect outside axiom's own submaps (the
  // key recorder's, the window switcher's), or null (CompositorManager)
  function withMainBinds(callback) {
    root.withBinds(binds => callback(binds ? binds.filter(entry => entry.submap !== root._captureSubmap && entry.submap !== HyprLua.switcherSubmap) : null));
  }

  // While on, every key reaches axiom instead of a bind (the Keybinds
  // page's recorder): an empty submap (Hyprland only registers one with a
  // bind, hence the unreachable one). A Hyprland timer leaves it even if
  // the shell dies meanwhile.
  function captureKeys(on) {
    root.runLua(on ? root._enterCaptureLua : root._leaveCaptureLua);
  }

  readonly property string _captureSubmap: "axiom_record"
  readonly property string _leaveCaptureLua: HyprLua.leaveSubmap(_captureSubmap)
  readonly property string _enterCaptureLua: `hl.define_submap("${_captureSubmap}", function() hl.bind("SUPER + CTRL + ALT + SHIFT + F24", hl.dsp.submap("reset")) end)
hl.timer(function() ${_leaveCaptureLua} end, { timeout = 30000, type = "oneshot" })
hl.dispatch(hl.dsp.submap("${_captureSubmap}"))`

  // The cursor theme and size, for this session
  function setCursor(theme, size) {
    HyprlandIpcManager.request(`setcursor ${theme} ${size}`);
  }

  // Ends the Hyprland session (the power menu's log out)
  function exitSession() {
    Hyprland.dispatch("hl.dsp.exit()");
  }

  // The shell command turning the screens off or on (hypridle's DPMS)
  function dpmsCommand(on) {
    return `hyprctl dispatch 'hl.dsp.dpms({ action = "${on ? "on" : "off"}" })'`;
  }

  // Calls back with the cursor's global position ({ x, y }), or null if
  // Hyprland can't say. Calls made while one is running share its answer.
  function withCursorPos(callback) {
    _cursorCallbacks.push(callback);
    if (_cursorCallbacks.length > 1)
      return;
    HyprlandIpcManager.json("cursorpos", pos => {
      const callbacks = root._cursorCallbacks;
      root._cursorCallbacks = [];
      callbacks.forEach(callback => callback(pos ?? null));
    });
  }

  property var _cursorCallbacks: []

  // The Wayland toplevel for a window id (its "0x…" address), for live
  // previews
  function toplevelFor(id) {
    for (const toplevel of Hyprland.toplevels.values) {
      if ("0x" + toplevel.address === id)
        return toplevel.wayland;
    }
    return null;
  }

  // --- Workspaces (the layout is CompositorManager's) ---

  // Sends the focused window to workspace `id`, staying put
  function sendWindowToWorkspace(id) {
    Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${id}, follow = false })`);
  }

  // Focuses output `name` (a dynamic workspaces' left or right step)
  function focusOutput(name) {
    Hyprland.dispatch(`hl.dsp.focus({ monitor = ${JSON.stringify(name)} })`);
  }

  // Moves the focused window to the workspace output `name` shows, going
  // along with `follow` (a dynamic workspaces' left or right step)
  function moveWindowToOutput(name, follow) {
    const id = root.outputs.find(o => o.name === name)?.activeWorkspaceId ?? -1;
    if (id >= 1)
      Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${id}, follow = ${follow === true} })`);
  }

  // Scrolls the focused workspace's strip a column on (1) or back (-1)
  function scrollStrip(direction) {
    Hyprland.dispatch(`hl.dsp.layout("move ${direction > 0 ? "+col" : "-col"}")`);
  }

  // A workspace switch (CompositorManager.goToWorkspace): `output` is
  // focused first when set; each of `legs` ([{ id, axis: "x" | "y" | "" }])
  // is gone to in turn, sliding along its axis, the last one arriving with
  // `mode` ("go" | "move") or by focusing window `focusId`. A new travel
  // replaces the rest of one still sliding.
  function travel(output, legs, mode, focusId) {
    root._slideSteps = [];
    _slideTimer.stop();
    const last = legs[legs.length - 1];
    const lead = output ? [`hl.dsp.focus({ monitor = ${JSON.stringify(output)} })`] : [];
    const arrive = focusId ? _focusWindowDispatcher(focusId) : _goDispatcher(last.id, mode);
    const anim = root._workspaceAnim;
    if (!anim || legs.some(leg => !leg.axis)) {
      lead.concat([arrive]).forEach(dispatcher => Hyprland.dispatch(dispatcher));
      root.travelingTo = -1;
      return;
    }
    // Two legs each take a fraction of the configured time, so going
    // diagonally across the grid is quicker than one plain switch
    const speed = legs.length > 1 ? Math.max(0.5, anim.speed * root._legSpeed) : anim.speed;
    root._slideSteps = legs.map((leg, i) => ({
          "id": leg.id,
          "style": leg.axis === "y" ? "slidevert" : "slide",
          "speed": speed,
          "dispatchers": (i === 0 ? lead : []).concat([i === legs.length - 1 ? arrive : _goDispatcher(leg.id, mode)])
        }));
    _nextSlide();
  }

  // The workspace a slide still under way has reached, or -1
  property int travelingTo: -1

  function _goDispatcher(id, mode) {
    return mode === "move" ? `hl.dsp.window.move({ workspace = ${id} })` : `hl.dsp.focus({ workspace = ${id} })`;
  }

  property var _slideSteps: []
  // Each leg's share of the configured speed on a two-leg slide
  readonly property real _legSpeed: 0.35

  function _nextSlide() {
    const step = root._slideSteps.shift();
    if (!step) {
      root.travelingTo = -1;
      return;
    }
    const anim = root._workspaceAnim;
    const set = (style, speed) => `hl.animation({ leaf = "workspaces", enabled = true, speed = ${speed}, bezier = "${anim.bezier}", style = "${style}" })`;
    _eval([set(step.style, step.speed)].concat(step.dispatchers.map(dispatcher => `hl.dispatch(${dispatcher})`), [set(anim.style, anim.speed)]).join("\n"));
    if (root._slideSteps.length > 0) {
      root.travelingTo = step.id;
      // Hyprland's speed is in tenths of a second
      _slideTimer.interval = Math.max(50, Math.round(step.speed * 100));
      _slideTimer.restart();
    } else {
      root.travelingTo = -1;
    }
  }

  // Lets the first slide finish before the second starts: switching again
  // mid-slide cuts it short, so the workspace would jump rather than slide
  property Timer _slideTimer: Timer {
    interval: 80
    onTriggered: root._nextSlide()
  }

  // Carries out a remap (WorkspaceGeometry.remapWorkspaces' plan) for
  // `outputs`, the monitors' names in block order. Hyprland creates a
  // workspace on the monitor it's first used from, so windows first go to a
  // named workspace each (on their own monitor, so a chain like 10 → 11,
  // 11 → 12 can't merge), every monitor leaves its old workspace for a
  // named one (so an empty old one is gone before its id is used again),
  // then the windows go to their ids and the monitors to theirs. The named
  // workspaces end up empty and go.
  function applyRemap(plan, outputs) {
    root._slideSteps = [];
    _slideTimer.stop();
    root.travelingTo = -1;
    const anim = root._workspaceAnim;
    const lines = [].concat(anim ? [_animLua(false)] : [], plan.moves.map(m => _moveLua(m.id, `"name:axiom-remap-${m.to}"`)), [].concat(...outputs.map((name, i) => _focusLua(name, `"name:axiom-remap-mon-${i}"`))), plan.moves.map(m => _moveLua(m.id, m.to)), [].concat(...plan.focus.map(f => _focusLua(f.monitor, f.id))), anim ? [_animLua(true)] : []);
    _eval(_luaPrelude + lines.join("\n") + _luaEpilogue);
  }

  // The workspaces animation on or off, as configured otherwise (Lua)
  function _animLua(enabled) {
    const anim = root._workspaceAnim;
    return `hl.animation({ leaf = "workspaces", enabled = ${enabled}, speed = ${anim.speed}, bezier = "${anim.bezier}", style = "${anim.style}" })`;
  }

  // Window `id` to `workspace` (a Lua value), staying put (Lua, in run())
  function _moveLua(id, workspace) {
    return `run(function() return hl.dsp.window.move({ workspace = ${workspace}, follow = false, window = ${_window(id)} }) end)`;
  }

  // Monitor `monitor` focused, then its `workspace` unless `stay` (Lua
  // lines, in run())
  function _focusLua(monitor, workspace, stay) {
    const lead = `run(function() return hl.dsp.focus({ monitor = ${JSON.stringify(monitor)} }) end)`;
    return stay ? [lead] : [lead, `run(function() return hl.dsp.focus({ workspace = ${workspace} }) end)`];
  }

  // --- Dynamic workspaces (dynamicByLayout) ---

  // Closes the gaps a workspace left empty in the middle leaves
  // (DynamicWorkspaces.compaction), once things have settled: after a
  // fetch, with no slide, fetch or Lua under way. The plan is worked out
  // when it's carried out, from the state then, and only ever moves windows
  // down, so a change made meanwhile (axiom's or anyone's) is simply
  // planned for next time.
  property Timer _compaction: Timer {
    interval: 300
    onTriggered: {
      if (!root.dynamicByLayout)
        return;
      if (root._fetching || root._debounce.running || root._evaluating || root._evalQueue.length > 0 || root._slideSteps.length > 0 || root.travelingTo > 0) {
        restart();
        return;
      }
      const monitors = root.outputs.map(o => ({
            "name": o.name,
            "active": o.activeWorkspaceId,
            "focused": o.focused
          }));
      const windows = root.windows.map(w => ({
            "id": w.id,
            "workspace": w.workspaceId
          }));
      const plan = DynamicWorkspaces.compaction(monitors, windows, root._bases, root.blockSize);
      if (!plan.changed)
        return;
      console.log(`[HyprlandManager] closing workspace gaps: ${plan.moves.length} windows, outputs to ${plan.focus.map(f => f.monitor + ":" + f.id).join(", ")}`);
      const anim = root._workspaceAnim;
      const lines = [].concat(anim ? [_animLua(false)] : [], plan.moves.map(m => _moveLua(m.id, m.to)), [].concat(...plan.focus.map(f => _focusLua(f.monitor, f.id, f.stay))), anim ? [_animLua(true)] : []);
      _eval(_luaPrelude + lines.join("\n") + _luaEpilogue);
    }
  }

  onDynamicByLayoutChanged: _compaction.restart()

  // Hyprland's general:gaps_out per side, which it adds after every
  // reserved zone (transparent bars subtract it, see BarPanel)
  property var gapsOut: ({
      "top": 0,
      "right": 0,
      "bottom": 0,
      "left": 0
    })
  // dwindle:split_width_multiplier: a box wider than tall times this splits
  // side by side (placeWindow, and the overview's drop preview)
  property real splitWidthMultiplier: 1
  // Hyprland's blur as in effect, { enabled, size, passes } (its defaults
  // until read): the one axiom's translucent surfaces blur with
  property var blur: ({
      "enabled": true,
      "size": 8,
      "passes": 1
    })
  // Hyprland's animations (j/animations: [leaves, curves]), read with the
  // options; [] until read
  property var animations: []
  // animations:enabled, Hyprland's switch for all of them
  property bool animationsEnabled: true
  // Hyprland's own "workspaces" animation ({ speed, bezier, style }), put
  // back after each slide (global's speed and curve when it isn't set,
  // sliding by default); null when animations are off, so there's nothing
  // to slide with
  readonly property var _workspaceAnim: {
    if (!animationsEnabled)
      return null;
    const leaves = Array.isArray(animations[0]) ? animations[0] : [];
    const leaf = name => leaves.find(a => a.name === name);
    const own = leaf("workspaces");
    const anim = own?.overridden ? own : leaf("global");
    return own?.enabled !== false && anim?.enabled && anim.bezier && anim.speed > 0 ? {
      "speed": anim.speed,
      "bezier": anim.bezier,
      "style": (own?.overridden && own.style) || "slide"
    } : null;
  }

  // The layer rules stacking axiom's surfaces (LayerStack.layers, which says
  // why each sits where it does; docs/dev/generated/layers.md). Named, so
  // re-adding one replaces it instead of piling up copies. Rules added at
  // runtime are lost when Hyprland reloads its config.
  // axiom's config layer also writes them into its Lua files, since a
  // reload Hyprland does by itself (a watched file changing) doesn't always
  // send the configreloaded event that re-adds them here.
  readonly property var _layerRulesLua: HyprLua.layerRulesLua()

  function _addLayerRules() {
    for (const rule of _layerRulesLua)
      _eval(rule);
  }

  // Whether the layer rules are in Hyprland. It reads a rule's `order` as a
  // surface maps, so a bar or border mapped before the rules (a runtime eval
  // in the detached mode, where hyprland.lua doesn't hold them) keeps its
  // mapping order: the border's strip, quicker to draw, lands outside the
  // bar, with its corners on the bar's outer side. The surfaces with an
  // `order` that start with the shell (bars, border, docks, edge menus)
  // wait for this. It stays set across QML reloads, as the rules do.
  readonly property bool surfacesReady: _layerRules.ready

  PersistentProperties {
    id: _layerRules
    reloadableId: "axiomLayerRules"
    property bool ready: false
  }

  // One eval for all of them, each in its own pcall, so one Hyprland
  // rejects doesn't drop the rest (as _addLayerRules' one eval per rule)
  function _addLayerRulesFirst() {
    HyprlandIpcManager.evalLua(root._layerRulesLua.map(rule => `pcall(function() ${rule} end)`).join("\n"), () => _layerRules.ready = true);
  }

  // Shows the shell anyway if Hyprland never answers
  property Timer _layerRulesTimeout: Timer {
    interval: 2000
    onTriggered: _layerRules.ready = true
  }

  Component.onCompleted: {
    _fetch();
    refreshOptions();
    if (_layerRules.ready) {
      _addLayerRules();
    } else {
      _addLayerRulesFirst();
      _layerRulesTimeout.start();
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      root._announce(event);
      // Layer surfaces (including our own popouts) don't affect clients,
      // and custom events are axiom's own (the window switcher's keys)
      if (event.name === "openlayer" || event.name === "closelayer" || event.name === "custom")
        return;
      if (event.name === "configreloaded") {
        root.refreshOptions();
        root._addLayerRules();
      }
      // Quickshell doesn't track special workspaces: refresh the monitors'
      // lastIpcObject, which carries them (specialWorkspaceId)
      if (event.name === "activespecial" || event.name === "activespecialv2")
        Hyprland.refreshMonitors();
      root._debounce.restart();
    }
  }

  // Emits the event's signal, if it has one (Events above). Hyprland sends
  // monitoradded/monitorremoved alongside their v2s, so only those count.
  function _announce(event) {
    switch (event.name) {
    case "openlayer":
    case "closelayer":
      root.layersChanged();
      break;
    case "monitoradded":
    case "monitorremoved":
      root.outputsHotplugged();
      break;
    case "configreloaded":
      root.configReloaded();
      break;
    case "activelayout":
      root.keyboardLayoutChanged();
      break;
    case "activewindow":
      root.windowFocused(event.data.split(",")[0]);
      break;
    case "custom":
      if (event.data.startsWith(HyprLua.switcherEvent)) {
        const [verb, argument = ""] = event.data.slice(HyprLua.switcherEvent.length).split(" ");
        root.switcherKey(verb, argument);
      }
      break;
    }
  }

  // Events arrive in bursts (a window opening fires several), so they are
  // coalesced into one fetch
  property Timer _debounce: Timer {
    interval: 50
    onTriggered: root._fetch()
  }

  // Set when a fetch is asked for while one is still running: it's run
  // again once the current one ends
  property bool _fetching: false
  property bool _pending: false

  function _fetch() {
    if (_fetching) {
      _pending = true;
      return;
    }
    _fetching = true;
    HyprlandIpcManager.json("clients", clients => {
      root._fetching = false;
      if (Array.isArray(clients)) {
        const names = Hyprland.monitors.values.reduce((map, m) => {
          map[m.id] = m.name;
          return map;
        }, {});
        root.windows = clients.map(client => HyprState.window(client, names)).filter(win => win !== null);
        if (root.dynamicByLayout)
          root._compaction.restart();
      }
      if (root._pending) {
        root._pending = false;
        root._fetch();
      }
    });
  }

  // A gaps option's sides from its getoption reply ({ top, right, bottom,
  // left }), or null: its css is "top right bottom left" (CSS shorthand)
  function _gapSides(option) {
    const css = String(option?.css ?? "").trim().split(/\s+/).map(Number);
    if (css.length === 0 || css.some(isNaN))
      return null;
    const [top, right = top, bottom = top, left = right] = css;
    return {
      "top": top,
      "right": right,
      "bottom": bottom,
      "left": left
    };
  }
}
