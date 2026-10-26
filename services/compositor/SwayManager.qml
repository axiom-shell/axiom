pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.I3

import qs.config
import qs.components.methods
import qs.services.core

/* CompositorManager's backend on sway (docs/dev/compositor/contract.md,
 * docs/dev/compositor/sway-backend.md): sway's state as the
 * compositor-neutral shapes (SwayState), and the primitives CompositorManager
 * builds on. Outputs and workspaces come live from Quickshell.I3; the windows
 * from sway's tree (get_tree), read again on its events. The only reader of
 * Quickshell.I3 outside the Sway* services. */
Singleton {
  id: root

  // --- Backend state (docs/dev/compositor/contract.md) ---

  // The windows (SwayState.window), most recently used ranked first
  readonly property var windows: SwayState.ranked(_info.windows, JSON.parse(_recent.idsJson), _info.order, activeWindowId)
  // The outputs (SwayState.output)
  readonly property var outputs: I3.monitors.values.map(m => SwayState.output(m, root._info, root.gapsOut))
  // The numbered workspaces (SwayState.workspace)
  readonly property var workspaces: I3.workspaces.values.map(ws => SwayState.workspace(ws, root._info.counts)).filter(ws => ws !== null)
  // The focused output's name, or ""
  readonly property string focusedOutput: I3.focusedMonitor?.name ?? ""
  // The focused window's id (its con_id), or "": from focus events as they
  // come, the tree otherwise
  readonly property string activeWindowId: _focusedId
  // Sway's gap at the screen edges, after reserved zones: its outer gap
  // plus the inner one every window keeps. Sway's IPC doesn't say: it's
  // what axiom's window look set (setLiveLook), else what sway's config
  // sets (SwayState.configInfo)
  readonly property var gapsOut: _liveGaps ? {
    "top": _liveGaps.outer + _liveGaps.inner,
    "right": _liveGaps.outer + _liveGaps.inner,
    "bottom": _liveGaps.outer + _liveGaps.inner,
    "left": _liveGaps.outer + _liveGaps.inner
  } : _gaps
  // Whether sway is SwayFX (blur, rounded corners, shadows, dimming), once
  // known: its get_version reply adds sway_original_version. Kept across a
  // reload of the shell, so it's known at once then.
  readonly property bool fx: _recent.variant === "swayfx"
  // Whether `supports` is final (the variant is known)
  readonly property bool ready: _recent.variant !== ""
  readonly property string displayName: fx ? "SwayFX" : "Sway"
  // Sway doesn't stack layers by axiom's order: LayerManager maps them in
  // order itself, from the start
  readonly property bool surfacesReady: true
  // Sway has no slides
  readonly property int travelingTo: -1
  // Sway doesn't pick a split by the window's shape
  readonly property real splitWidthMultiplier: 1
  // SwayFX's blur ({ enabled, size, passes }), as the window look set it
  // (setLiveLook), else its config's; plain sway has none
  readonly property var blur: _liveBlur ?? _configBlur
  // What sway does (CompositorManager.supports): SwayFX adds the blur,
  // rounded corners, shadows and dimming. Window opacity is set a window
  // at a time as focus moves (SwayState.windowCommands)
  readonly property var supports: Object.assign({
    "configModes": true,
    "keybinds": true,
    "monitors": true,
    "switcher": true,
    "windowGeometry": true,
    "outputCapture": true,
    "layerFrameSync": true,
    "windowBorders": true,
    "windowShape": true,
    "windowGaps": true,
    "inputConfig": true,
    "keyCapture": true,
    "modifierTap": true,
    "bindMerge": true,
    "scratchpad": true,
    "namedSpecial": true,
    "mouseBinds": true,
    "splitToggle": true,
    "pin": true,
    "windowOpacity": true
  }, fx ? _fxCapabilities.reduce((caps, cap) => {
    caps[cap] = true;
    return caps;
  }, {}) : {})

  // --- Events ---

  // Never: sway reports no layer surfaces
  signal layersChanged
  // An output was connected or disconnected
  signal outputsHotplugged
  // Sway reloaded its config (binds and runtime settings reset)
  signal configReloaded
  // The keyboard layout switched
  signal keyboardLayoutChanged
  // A window was focused; appId is its app_id (or X11 class)
  signal windowFocused(string appId)
  // A window switcher key (a `nop axiom switcher <verb> [argument]` bind):
  // verb `step` (argument the step), `commit` or `cancel`
  signal switcherKey(string verb, string argument)

  // Re-reads the outputs, workspaces and windows soon
  function refresh() {
    I3.refreshMonitors();
    I3.refreshWorkspaces();
    _debounce.restart();
  }

  // --- Windows ---

  function _con(id) {
    return `[con_id=${Number(id)}]`;
  }

  function activateWindow(id) {
    SwayIpcManager.dispatch(`${_con(id)} focus`);
  }

  function closeWindow(id) {
    SwayIpcManager.dispatch(`${_con(id)} kill`);
  }

  // The overview's drop (CompositorManager.placeWindow): onto workspace
  // `workspaceId`, next to `targetId` on its `side` ("left" | "right" |
  // "top" | "bottom") when given, or floating at `floatAt` (global). Sway
  // puts a window moved to a mark after the marked one, in a split of the
  // side's axis; before it is a swap after that. Sway can't move the cursor
  // back, so `restore` goes unused.
  function placeWindow(id, workspaceId, targetId, side, restore, reinsert, floatAt) {
    const win = _con(id);
    const lines = [];
    if (floatAt) {
      if (!reinsert)
        lines.push(`${win} move container to workspace number ${workspaceId}`);
      if (root.windows.find(w => w.id === String(id))?.floating)
        lines.push(`${win} move absolute position ${Math.round(floatAt.x)} ${Math.round(floatAt.y)}`);
    } else if (targetId) {
      const target = _con(targetId);
      const vertical = side === "top" || side === "bottom";
      lines.push(`${target} mark --add ${_dropMark}`, `${target} split ${vertical ? "v" : "h"}`, `${win} move container to mark ${_dropMark}`, `${target} unmark ${_dropMark}`);
      if (side === "left" || side === "top")
        lines.push(`${win} swap container with con_id ${Number(targetId)}`);
    } else {
      lines.push(`${win} move container to workspace number ${workspaceId}`);
    }
    SwayIpcManager.command(lines.join("; "), () => root._debounce.restart());
  }

  readonly property string _dropMark: "axiom-drop"

  // Grows a window by (dw, dh) and, when floating, moves it by (dx, dy). On
  // a tiled one sway moves the split the window shares.
  function resizeWindow(id, dw, dh, dx, dy) {
    const win = _con(id);
    const floating = root.windows.find(w => w.id === String(id))?.floating === true;
    const lines = [];
    const px = value => `${Math.abs(Math.round(value))} px`;
    if (Math.round(dw) !== 0)
      lines.push(`${win} resize ${dw > 0 ? "grow" : "shrink"} width ${px(dw)}`);
    if (Math.round(dh) !== 0)
      lines.push(`${win} resize ${dh > 0 ? "grow" : "shrink"} height ${px(dh)}`);
    if (floating && Math.round(dx) !== 0)
      lines.push(`${win} move ${dx > 0 ? "right" : "left"} ${px(dx)}`);
    if (floating && Math.round(dy) !== 0)
      lines.push(`${win} move ${dy > 0 ? "down" : "up"} ${px(dy)}`);
    if (lines.length > 0)
      SwayIpcManager.command(lines.join("; "));
  }

  // Sway can't move the cursor (supports.cursorWarp is off)
  function warpCursorToLayer(namespace, monitor, width, height, x, y) {
  }

  // The Wayland toplevel for a window id, for live previews: none on sway.
  // Quickshell can't capture a toplevel there (ScreencopyView calls it not
  // captureable), so the overview draws the window's icon instead.
  function toplevelFor(id) {
    return null;
  }

  // --- Workspaces (the layout is CompositorManager's) ---

  // Sends the focused window to workspace `id`, staying put
  function sendWindowToWorkspace(id) {
    SwayIpcManager.dispatch(`move container to workspace number ${id}`);
  }

  // Sway has no strips
  function scrollStrip(direction) {
  }

  // A workspace switch (CompositorManager.goToWorkspace). Sway doesn't
  // slide, so only the last leg counts.
  function travel(output, legs, mode, focusId) {
    const last = legs[legs.length - 1];
    const lines = output ? [`focus output ${SwayConf.quote(output)}`] : [];
    if (focusId)
      lines.push(`${_con(focusId)} focus`);
    else if (mode === "move")
      lines.push(`move container to workspace number ${last.id}`, `workspace number ${last.id}`);
    else
      lines.push(`workspace number ${last.id}`);
    SwayIpcManager.dispatch(lines.join("; "));
  }

  // Carries out a remap (WorkspaceGeometry.remapWorkspaces' plan) for
  // `outputs`, the outputs' names in block order. Sway creates a workspace
  // on the focused output, so each output is focused before its windows
  // move: first to a named workspace each (so a chain like 10 → 11, 11 → 12
  // can't merge), then every output leaves its old workspace for a named one
  // (so an empty old one is gone before its number is used again), then the
  // windows go to their numbers and the outputs to theirs. The named
  // workspaces end up empty and go.
  function applyRemap(plan, outputs) {
    const outputOf = id => root.windows.find(w => w.id === id)?.output ?? "";
    const focus = name => `focus output ${SwayConf.quote(name)}`;
    const moveAll = target => [].concat(...outputs.map(name => {
        const moves = plan.moves.filter(m => outputOf(m.id) === name);
        return moves.length > 0 ? [focus(name)].concat(moves.map(m => `${_con(m.id)} move container to workspace ${target(m)}`)) : [];
      }));
    const lines = [].concat(moveAll(m => SwayConf.quote("axiom-remap-" + m.to)), [].concat(...outputs.map((name, i) => [focus(name), `workspace axiom-remap-mon-${i}`])), moveAll(m => "number " + m.to), [].concat(...plan.focus.map(f => [focus(f.monitor), `workspace number ${f.id}`])));
    SwayIpcManager.command(lines.join("; "), () => root.refresh());
  }

  // --- Special workspaces: groups of scratchpad windows ---

  // Shows the windows of special group `name` on the focused output, or
  // hides them when any is shown there (SwayState.specialToggle)
  function toggleSpecial(name) {
    const plan = SwayState.specialToggle(root.windows, root._marks, name, root.focusedOutput);
    const shown = plan.ids.filter(id => root.windows.some(w => w.id === id));
    const lines = plan.show ? plan.ids.filter(id => !root.windows.some(w => w.id === id && w.output === root.focusedOutput)).map(id => `${_con(id)} scratchpad show`) : shown.map(id => `${_con(id)} move scratchpad`);
    if (lines.length > 0)
      SwayIpcManager.command(lines.join("; "), () => root._debounce.restart());
  }

  // Puts the focused window in special group `name` (hidden until shown),
  // out of any other: a window is on one special workspace at a time
  function moveToSpecial(name) {
    const id = root.activeWindowId;
    if (!id)
      return;
    const leave = (root._marks[id] ?? []).filter(mark => SwayState.specialGroup(mark) !== "").map(mark => `${_con(id)} unmark ${SwayConf.quote(mark)}`);
    SwayIpcManager.command(leave.concat([`${_con(id)} mark --add ${SwayConf.quote(`axiom-special-${name}-${id}`)}`, `${_con(id)} move scratchpad`]).join("; "), () => root._debounce.restart());
  }

  // --- The window switcher ---

  // Nothing to let go: sway's switcher binds enter no mode (SwitcherKeys
  // reads the keys while it's open), and `mode default` would leave one of
  // the user's own
  function leaveSwitcher() {
  }

  // --- axiom's config layer (the daemon's: CompositorConfigManager) ---

  // axiom's config layer changed sway at runtime (the daemon's
  // compositor.applied): sway sends no event for a gap change, so the
  // windows are read again
  function layerApplied() {
    refresh();
  }

  // Runs sway commands (`lines`), in order, after those sent before
  function runCommands(lines, callback) {
    SwayIpcManager.command(lines.filter(line => line !== "").join("; "), ok => callback?.(ok));
  }

  // The window look as set now (CompositorLayer.look;
  // CompositorConfigManager): gapsOut and blur follow its gaps and blur until sway
  // reloads its config, and what sway sets a window at a time (opacity;
  // SwayFX's blur, shadows, dim) is kept up as windows open and focus moves
  function setLiveLook(look) {
    const gaps = look?.gaps;
    root._liveGaps = gaps ? {
      "inner": Number(gaps.inner) || 0,
      "outer": Number(gaps.outer) || 0
    } : null;
    root._liveBlur = root.fx && look?.blur ? {
      "enabled": look.blur.windows || look.blur.surfaces,
      "size": Math.min(10, look.blur.size),
      "passes": look.blur.passes
    } : null;
    root._windowEffects = {
      "opacity": look?.opacity ?? null,
      "blur": root.fx && look?.blur ? look.blur.windows === true : null,
      "shadows": root.fx && look?.shadow ? true : null,
      "dim": root.fx && look?.dim ? look.dim.strength / 100 : null
    };
    root._lookSeen = true;
    root._applyWindowLook();
  }

  property var _liveGaps: null
  property var _liveBlur: null
  property var _configBlur: ({
      "enabled": false,
      "size": 5,
      "passes": 2
    })
  // SwayFX's default_dim_inactive in its config, what dim goes back to
  property real _configDim: 0
  // The look's parts set a window at a time (SwayState.windowCommands)
  property var _windowEffects: null
  // Until the look is first set (after a reload of the shell), the
  // windows keep what they have
  property bool _lookSeen: false

  // Each window's look as the look's parts say, for those that changed
  function _applyWindowLook() {
    if (!root._lookSeen)
      return;
    const plan = SwayState.windowCommands(root.windows, root.activeWindowId, root._windowEffects, JSON.parse(_recent.windowLookJson), root._configDim);
    _recent.windowLookJson = JSON.stringify(plan.applied);
    if (plan.lines.length > 0)
      root.runCommands(plan.lines);
  }
  onWindowsChanged: _applyWindowLook()
  onActiveWindowIdChanged: _applyWindowLook()

  // After a config reload: each window's blur and shadows are the
  // config's again, so the look sent after every reload (setLiveLook)
  // sets them anew. Not at once: the reload may be what turns them off
  function _forgetReloaded() {
    const applied = JSON.parse(_recent.windowLookJson);
    for (const id in applied) {
      delete applied[id].blur;
      delete applied[id].shadows;
    }
    _recent.windowLookJson = JSON.stringify(applied);
  }

  // Calls back with the binds in effect outside axiom's own modes (the
  // user's, read from their config, and axiom's), or null
  function withMainBinds(callback) {
    CompositorConfigManager.withEntries(callback);
  }

  // While on, every key reaches axiom instead of a bind (the Keybinds
  // page's recorder): an empty mode, left by an unreachable key. A sleeping
  // swaymsg leaves it after 30 s even if the shell dies meanwhile. Each
  // capture names its mode anew, so an earlier capture's sleeper can't end
  // a later one.
  function captureKeys(on) {
    if (on) {
      const mode = `axiom_record_${Date.now() % 1000000000}`;
      runCommands([`mode "${mode}" bindsym --no-warn Mod4+Ctrl+Mod1+Shift+F24 mode default`, `mode "${mode}"`, `exec sleep 30 && swaymsg -t get_binding_state | grep -qw ${mode} && swaymsg mode default`]);
    } else {
      SwayIpcManager.dispatch("mode default");
    }
  }

  // --- Session and input ---

  // Calls back with the main keyboard's layouts ({ layouts, index, keymap },
  // SwayState.keyboard), or null
  function withKeyboard(callback) {
    const input = InputConfig.input;
    const codes = input.keyboard.enabled ? input.keyboard.layout : root._configLayouts;
    SwayIpcManager.json("get_inputs", inputs => callback(Array.isArray(inputs) ? SwayState.keyboard(inputs, codes) : null));
  }

  // Switches every keyboard to its "next" or "prev" layout, then calls back
  function cycleKeyboardLayout(direction, callback) {
    SwayIpcManager.command(`input type:keyboard xkb_switch_layout ${direction === "prev" ? "prev" : "next"}`, () => callback?.());
  }

  // Sets the input options and cursor now (`input`: CompositorLayer.input's,
  // `inputSchema`: Input's), as their parts say: the greeter's sway, which
  // loads no config of axiom's
  function applyInput(input, inputSchema) {
    root.runCommands(SwayConf.inputLines(input, inputSchema, true));
  }

  // Sway can't say where the cursor is, nor list layer surfaces
  function withCursorPos(callback) {
    callback(null);
  }

  function withLayerRects(callback) {
    callback(null);
  }

  // What can do what plain sway can't (CompositorManager.unsupportedNote).
  // I18n.tr("SwayFX can.")
  function unsupportedHint(capability) {
    return !root.fx && root._fxCapabilities.includes(capability) ? I18n.tr("SwayFX can.") : "";
  }

  readonly property var _fxCapabilities: ["windowRounding", "windowBlur", "blur", "windowShadow", "windowDim"]

  // Ends the sway session (the power menu's log out)
  function exitSession() {
    SwayIpcManager.dispatch("exit");
  }

  // --- Outputs (the Monitors page) ---

  // Calls back with every output in detail, disabled ones too
  // (SwayState.outputDetails), or null
  function withOutputDetails(callback) {
    SwayIpcManager.json("get_outputs", outputs => callback(Array.isArray(outputs) ? SwayState.outputDetails(outputs) : null));
  }

  // Sets the outputs as `rules` (MonitorRule) say, now. Sway has no
  // mirroring, so `details` aren't needed.
  function applyOutputs(rules, details) {
    SwayIpcManager.command(SwayConf.outputCommands(rules), () => root.refresh());
  }

  // --- State behind the members above ---

  // The last tree read (SwayState.tree)
  property var _info: SwayState.tree(null)
  // Every window's marks ({ [id]: [marks] }), for the special groups
  property var _marks: ({})
  property string _focusedId: ""
  // Focus events so far, to tell a tree read before the last one (_fetch)
  property int _focusEvents: 0
  property var _gaps: ({
      "top": 0,
      "right": 0,
      "bottom": 0,
      "left": 0
    })
  // The layouts sway's own config sets ("us,de"), for their short names
  property string _configLayouts: ""
  // The outputs' names when last read, to tell a hotplug from another
  // output change
  property string _outputNames: ""
  // Whether they were read yet (a start with no output reads "" too)
  property bool _outputsRead: false

  // Windows focused since axiom started, most recent first, as JSON
  // (survives a reload of the shell, as sway's own focus stacks don't say
  // it all)
  PersistentProperties {
    id: _recent
    reloadableId: "axiomSwayRecent"
    property string idsJson: "[]"
    // "sway" or "swayfx" once read (_readVersion), else ""
    property string variant: ""
    // Each window's look as last set ({ id: { opacity, blur, shadows, dim
    // } }, JSON)
    property string windowLookJson: "{}"
  }

  function _readVersion() {
    SwayIpcManager.json("get_version", reply => {
      if (reply)
        _recent.variant = reply.sway_original_version !== undefined ? "swayfx" : "sway";
      else
        _versionRetry.restart();
    });
  }

  // Until it's known, `ready` holds back axiom's layer. A sway that doesn't
  // answer is asked again less and less often (2 s, doubling up to a
  // minute), so it doesn't fill the log
  property Timer _versionRetry: Timer {
    interval: 2000
    onTriggered: {
      interval = Math.min(interval * 2, 60000);
      root._readVersion();
    }
  }

  // SwayFX's blur and dim in the config are read only once it's known
  onFxChanged: _readConfig()

  I3IpcListener {
    subscriptions: ["window", "workspace", "output", "input", "binding"]
    onIpcEvent: event => root._onEvent(event)
  }

  function _onEvent(event) {
    let data = {};
    try {
      data = JSON.parse(event.data);
    } catch (e) {
      return;
    }
    switch (event.type) {
    case "window":
      if (data.change === "focus" && data.container) {
        const id = String(data.container.id);
        root._focusedId = id;
        root._focusEvents++;
        _recent.idsJson = JSON.stringify(SwayState.touch(JSON.parse(_recent.idsJson), id));
        root.windowFocused(data.container.app_id ?? data.container.window_properties?.["class"] ?? "");
      }
      _debounce.restart();
      break;
    case "workspace":
      if (data.change === "reload") {
        // A reload takes back what axiom's look set at runtime, each
        // window's blur and shadows too (not its opacity or dim, which
        // stay)
        root._liveGaps = null;
        root._liveBlur = null;
        // Until the look is sent again: re-sending the old one when the
        // tree is read next would turn back on what the reload turned off
        if (root._windowEffects)
          root._windowEffects = Object.assign({}, root._windowEffects, {
            "blur": null,
            "shadows": null
          });
        root._forgetReloaded();
        root._readConfig();
        root.configReloaded();
      }
      _debounce.restart();
      break;
    case "output":
      root._checkOutputs();
      _debounce.restart();
      break;
    case "input":
      if (data.change === "xkb_layout" || data.change === "xkb_keymap")
        root.keyboardLayoutChanged();
      break;
    case "binding":
      root._onBinding(String(data.binding?.command ?? ""));
      break;
    }
  }

  // axiom's own binds: `nop axiom <what> <verb> [argument]`
  function _onBinding(command) {
    const segment = command.split(/[;,]/).map(part => part.trim()).find(part => part.startsWith("nop axiom ")) ?? "";
    const words = segment.split(/\s+/);
    if (words[0] !== "nop" || words[1] !== "axiom")
      return;
    const [what, verb = "", argument = ""] = words.slice(2);
    if (what === "switcher")
      root.switcherKey(verb, argument);
    else if (what === "special" && verb === "toggle")
      root.toggleSpecial(argument);
    else if (what === "special" && verb === "move")
      root.moveToSpecial(argument);
  }

  function _checkOutputs() {
    SwayIpcManager.json("get_outputs", outputs => {
      if (!Array.isArray(outputs))
        return;
      const names = outputs.map(o => o.name).sort().join(",");
      const changed = root._outputsRead && names !== root._outputNames;
      root._outputNames = names;
      root._outputsRead = true;
      if (changed)
        root.outputsHotplugged();
    });
  }

  // The gaps and layouts sway's config sets (SwayState.configInfo), its
  // includes put in (get_config holds only the main file, so gaps set in
  // an included one, as managed mode's user/ files are, went unseen)
  function _readConfig() {
    CommandManager.run([Paths.toolBin, "compositor", "sway-text"], (code, out) => {
      if (code !== 0)
        return;
      const info = SwayState.configInfo(out);
      root._gaps = info.gaps;
      root._configLayouts = info.layouts;
      root._configDim = root.fx ? info.dim : 0;
      root._configBlur = root.fx ? info.blur : {
        "enabled": false,
        "size": 5,
        "passes": 2
      };
    });
  }

  // Events arrive in bursts (a window opening sends several), so they are
  // coalesced into one read
  property Timer _debounce: Timer {
    interval: 50
    onTriggered: root._fetch()
  }

  property bool _fetching: false
  property bool _pending: false

  function _fetch() {
    if (_fetching) {
      _pending = true;
      return;
    }
    _fetching = true;
    const focusEvents = root._focusEvents;
    SwayIpcManager.json("get_tree", tree => {
      root._fetching = false;
      if (tree) {
        root._info = SwayState.tree(tree);
        root._marks = SwayState.marks(tree);
        // A focus event that came while it was read is newer
        if (focusEvents === root._focusEvents)
          root._focusedId = root._info.focusedId;
      }
      if (root._pending) {
        root._pending = false;
        root._fetch();
      }
    });
  }

  // Sway reports no change to the space layer surfaces reserve, so the
  // windows' geometry is read once more after axiom's own bars have mapped
  // (the overview and the dock refresh() when they open)
  property Timer _settle: Timer {
    interval: 1500
    onTriggered: root._fetch()
  }

  Component.onCompleted: {
    _readVersion();
    _fetch();
    _settle.start();
    _readConfig();
    _checkOutputs();
  }
}
