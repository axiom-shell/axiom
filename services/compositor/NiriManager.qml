pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core

/* CompositorManager's backend on niri (docs/dev/compositor/contract.md,
 * docs/dev/compositor/niri-backend.md): niri's state as the
 * compositor-neutral shapes (NiriState), and the primitives CompositorManager
 * builds on. The state comes from niri's event stream, kept up event by
 * event (NiriState.reduce); the outputs, which the stream doesn't hold,
 * from an Outputs request whenever the workspaces or screens change. */
Singleton {
  id: root

  // --- Backend state (docs/dev/compositor/contract.md) ---

  // The windows (NiriState.windows)
  readonly property var windows: NiriState.windows(_state, outputs, _bases, root.blockSize, _gap)
  // The enabled outputs (NiriState.outputs)
  readonly property var outputs: NiriState.outputs(_outputsReply, _state, _bases, root.blockSize, _reserved)
  // What axiom's layers reserve on each output ({ [name]: { top, right,
  // bottom, left } }): niri doesn't say. Replaced only when it changes,
  // not on every frame a popout resizes.
  property var _reserved: ({})
  property Connections _layers: Connections {
    target: LayerManager
    function onRectsChanged() {
      const next = {};
      for (const name in LayerManager.rects)
        next[name] = LayerManager.rects[name].reserved;
      if (JSON.stringify(next) !== JSON.stringify(root._reserved))
        root._reserved = next;
    }
  }
  // The workspaces with an id of axiom's (NiriState.workspaces): each
  // output's first `blockSize`
  readonly property var workspaces: NiriState.workspaces(_state, _bases, root.blockSize)
  // The focused output's name, or ""
  readonly property string focusedOutput: NiriState.focusedOutput(_state)
  // The focused window's id, or ""
  readonly property string activeWindowId: NiriState.focusedWindowId(_state)
  // niri's gap at the screen edges: its gaps plus its struts, as the
  // config it runs sets them (axiom's module in it)
  readonly property var gapsOut: {
    const gaps = root._configGaps;
    return {
      "top": gaps.inner + gaps.struts.top,
      "right": gaps.inner + gaps.struts.right,
      "bottom": gaps.inner + gaps.struts.bottom,
      "left": gaps.inner + gaps.struts.left
    };
  }
  // niri doesn't say how far it scrolls a strip, so the overview fits it
  readonly property real splitWidthMultiplier: 1
  // niri's blur as in effect, { enabled, size, passes }: the config's
  // (`axiom compositor niri info`), its offset as the size (render.NiriLookNodes
  // writes the window look's size as the offset), niri's defaults until
  // read
  readonly property var blur: root._blur
  property var _blur: ({
      "enabled": true,
      "size": 3,
      "passes": 3
    })
  // niri doesn't stack layers by axiom's order: LayerManager maps them in
  // order itself, from the start
  readonly property bool surfacesReady: true
  // niri slides between workspaces itself
  readonly property int travelingTo: -1
  // Ids in each output's block (CompositorManager.blockSize): niri makes
  // workspaces as they fill, so more than anyone has
  readonly property int blockSize: 100
  // Whether niri's last config load failed (it keeps the config before)
  readonly property bool lastLoadFailed: _state.configFailed
  // What niri does (CompositorManager.supports). Its workspaces belong to
  // an output, and every output is a strip. A column's windows shown as
  // tabs are its window groups. No outputCapture: it has only
  // wlr-screencopy, which crashes Quickshell's own capture
  // (ScreenshotManager.grimFrames). No layerFrameSync: another layer's
  // change can show a frame or so after the one sliding. It blurs behind
  // the shell's surfaces where each window says (blurRegion: no alpha
  // threshold, a layer rule would blur the whole window), its
  // ext-background-effect.
  readonly property var supports: ({
      "configModes": true,
      "keybinds": true,
      "monitors": true,
      "switcher": true,
      "strips": true,
      "stripsAlways": true,
      "outputWorkspaces": true,
      "dynamicWorkspaces": true,
      "windowBorders": true,
      "windowShape": true,
      "windowRounding": true,
      "windowGaps": true,
      "windowBlur": true,
      "blur": true,
      "blurRegion": true,
      "windowShadow": true,
      "windowOpacity": true,
      "windowGroups": true,
      "windowCover": true,
      "inputConfig": true,
      "keyCapture": true,
      "bindMerge": true
    })

  // --- Events ---

  // Never: niri says nothing of the space layer surfaces take
  signal layersChanged
  // An output was connected or disconnected
  signal outputsHotplugged
  // niri loaded its config again
  signal configReloaded
  // The keyboard layout switched
  signal keyboardLayoutChanged
  // A window was focused; appId is its app_id
  signal windowFocused(string appId)
  // Never: niri's switcher binds call axiom's IPC (WindowSwitcherManager)
  signal switcherKey(string verb, string argument)

  // The binds niri carries out itself, by action, as axiom writes the key:
  // Mod + drag moves a window, Mod + right drag resizes it (the Keybinds
  // page's mouseDrag and mouseResize, which niri can't be told to bind)
  readonly property var builtInBinds: ({
      "mouseDrag": root._configModKey + " + mouse:272",
      "mouseResize": root._configModKey + " + mouse:273"
    })

  // Reads the outputs again (the rest comes as events)
  function refresh() {
    root._readOutputs();
  }

  // --- Windows ---

  function activateWindow(id) {
    root._action({
      "FocusWindow": {
        "id": Number(id)
      }
    });
  }

  function closeWindow(id) {
    root._action({
      "CloseWindow": {
        "id": Number(id)
      }
    });
  }

  // The overview's drop (CompositorManager.placeWindow): onto workspace
  // `workspaceId`, beside `targetId`'s column on its `side` ("left" |
  // "right"), into its column ("top" | "bottom", at the column's end), or
  // floating at `floatAt` (global). niri moves the focused column, so the
  // window is focused first; `restore` (the cursor) goes unused.
  function placeWindow(id, workspaceId, targetId, side, restore, reinsert, floatAt) {
    const win = Number(id);
    if (!reinsert)
      root._action({
        "MoveWindowToWorkspace": {
          "window_id": win,
          "reference": root._reference(workspaceId),
          "focus": false
        }
      });
    const moved = root.windows.find(w => w.id === String(id));
    if (floatAt) {
      if (moved?.floating) {
        const output = root.outputs.find(o => o.name === root._outputOf(workspaceId));
        root._action({
          "MoveFloatingWindow": {
            "id": win,
            "x": {
              "SetFixed": Math.round(floatAt.x - (output?.x ?? 0))
            },
            "y": {
              "SetFixed": Math.round(floatAt.y - (output?.y ?? 0))
            }
          }
        });
      }
      return;
    }
    const target = root.windows.find(w => w.id === String(targetId));
    if (!target?.column)
      return;
    root._action({
      "FocusWindow": {
        "id": win
      }
    });
    const into = side === "top" || side === "bottom";
    // The window's own column leaving from before the target's shifts it
    const shift = moved?.workspaceId === target.workspaceId && (moved.column ?? Infinity) < target.column ? 1 : 0;
    root._action({
      "MoveColumnToIndex": {
        "index": target.column - shift + (side === "left" ? 0 : 1)
      }
    });
    if (into)
      root._action({
        "ConsumeOrExpelWindowLeft": {
          "id": win
        }
      });
  }

  // Grows a window by (dw, dh) and, when floating, moves it by (dx, dy)
  function resizeWindow(id, dw, dh, dx, dy) {
    const win = Number(id);
    const adjust = value => ({
          "AdjustFixed": Math.round(value)
        });
    if (Math.round(dw) !== 0)
      root._action({
        "SetWindowWidth": {
          "id": win,
          "change": adjust(dw)
        }
      });
    if (Math.round(dh) !== 0)
      root._action({
        "SetWindowHeight": {
          "id": win,
          "change": adjust(dh)
        }
      });
    const floating = root.windows.find(w => w.id === String(id))?.floating === true;
    if (floating && (Math.round(dx) !== 0 || Math.round(dy) !== 0))
      root._action({
        "MoveFloatingWindow": {
          "id": win,
          "x": adjust(dx),
          "y": adjust(dy)
        }
      });
  }

  // niri can't move the cursor (supports.cursorWarp is off)
  function warpCursorToLayer(namespace, monitor, width, height, x, y) {
  }

  // The Wayland toplevel for a window id, for live previews: none on niri,
  // so the overview draws the window's icon instead
  function toplevelFor(id) {
    return null;
  }

  // --- Workspaces (the layout is CompositorManager's) ---

  // Sends the focused window to workspace `id`, staying put
  function sendWindowToWorkspace(id) {
    root._action({
      "MoveWindowToWorkspace": {
        "window_id": null,
        "reference": root._reference(id),
        "focus": false
      }
    });
  }

  // Scrolls the focused output's strip a column on (1) or back (-1)
  function scrollStrip(direction) {
    root._action(direction > 0 ? {
      "FocusColumnRight": {}
    } : {
      "FocusColumnLeft": {}
    });
  }

  // A workspace switch (CompositorManager.goToWorkspace). niri slides by
  // itself, so only the last leg counts.
  function travel(output, legs, mode, focusId) {
    const last = legs[legs.length - 1];
    if (output)
      root._action({
        "FocusMonitor": {
          "output": output
        }
      });
    if (focusId)
      root.activateWindow(focusId);
    else if (mode === "move")
      root._action({
        "MoveWindowToWorkspace": {
          "window_id": null,
          "reference": root._reference(last.id),
          "focus": true
        }
      });
    else
      root._action({
        "FocusWorkspace": {
          "reference": root._reference(last.id)
        }
      });
  }

  // Focuses output `name` (its active workspace)
  function focusOutput(name) {
    root._action({
      "FocusMonitor": {
        "output": name
      }
    });
  }

  // Moves the focused window to output `name`; focus goes along with
  // `follow`, else stays on the output it's on
  function moveWindowToOutput(name, follow) {
    const from = root.focusedOutput;
    root._action({
      "MoveWindowToMonitor": {
        "id": null,
        "output": name
      }
    });
    root.focusOutput(follow ? name : from);
  }

  // niri's workspaces belong to their output and keep their place there
  // (supports.outputWorkspaces): there's nothing to remap
  function applyRemap(plan, outputs) {
  }

  // How niri refers to axiom's workspace `id`: by its own id where it has
  // that workspace, else by its place on the output (niri goes to its last,
  // empty one for a place past it)
  function _reference(id) {
    const ws = root._niriWorkspace(id);
    if (ws)
      return {
        "Id": ws.id
      };
    const output = root._outputOf(id);
    return {
      "Index": id - (root._bases[output] ?? 1) + 1
    };
  }

  function _niriWorkspace(id) {
    for (const key in root._state.workspaces) {
      const ws = root._state.workspaces[key];
      if (NiriState.workspaceId(ws, root._bases, root.blockSize) === id)
        return ws;
    }
    return null;
  }

  // The output whose block holds workspace `id`, else the focused one
  function _outputOf(id) {
    const size = root.blockSize;
    for (const name in root._bases) {
      if (id >= root._bases[name] && id < root._bases[name] + size)
        return name;
    }
    return root.focusedOutput;
  }

  // --- The window switcher ---

  // Nothing to let go: niri's switcher binds enter no mode (SwitcherKeys
  // reads the keys while it's open)
  function leaveSwitcher() {
  }

  // --- Binds ---

  // Calls back with the binds in effect outside axiom's own (the user's,
  // read from their config, and axiom's), or null
  function withMainBinds(callback) {
    CompositorConfigManager.withEntries(callback);
  }

  // Nothing to do: the key recorder's window inhibits niri's shortcuts
  // itself (KeyRecorder's ShortcutInhibitor), niri having no empty mode
  function captureKeys(on) {
  }

  // --- Session and input ---

  // Calls back with the keyboard's layouts ({ layouts, index, keymap },
  // NiriState.keyboard), or null
  function withKeyboard(callback) {
    const input = InputConfig.input;
    callback(NiriState.keyboard(root._state, input.keyboard.enabled ? input.keyboard.layout : root._configLayouts));
  }

  // Switches to the "next" or "prev" layout, then calls back
  function cycleKeyboardLayout(direction, callback) {
    root._action({
      "SwitchLayout": {
        "layout": direction === "prev" ? "Prev" : "Next"
      }
    }, () => callback?.());
  }

  // niri can't say where the cursor is, nor where layer surfaces are
  function withCursorPos(callback) {
    callback(null);
  }

  function withLayerRects(callback) {
    callback(null);
  }

  // Ends the niri session (the power menu's log out)
  function exitSession() {
    root._action({
      "Quit": {
        "skip_confirmation": true
      }
    });
  }

  // --- Outputs (the Monitors page) ---

  // Calls back with every output in detail, disabled ones too
  // (NiriState.outputDetails), or null
  function withOutputDetails(callback) {
    root._request("Outputs", reply => callback(reply?.Outputs ? NiriState.outputDetails(reply.Outputs) : null));
  }

  // axiom set the outputs (CompositorManager.applyOutputs): read again
  function outputsApplied() {
    root._readOutputs();
  }

  // --- State behind the members above ---

  // niri's state, kept up from its event stream (NiriState.reduce)
  property var _state: NiriState.empty()
  // The last Outputs reply ({ [name]: output })
  property var _outputsReply: ({})
  // Each output's first workspace id (WorkspaceGeometry.blockBases): every
  // output has a block, in the facade's order
  readonly property var _bases: {
    const raw = [];
    for (const name in root._outputsReply) {
      if (root._outputsReply[name].logical)
        raw.push({
          "name": name,
          "description": NiriState.description(root._outputsReply[name])
        });
    }
    return WorkspaceGeometry.blockBases(raw, General.primaryMonitor, root.blockSize);
  }
  // The gap between windows, where niri lays a strip out from
  readonly property real _gap: root._configGaps.inner
  // niri's gaps and struts, as the config it runs sets them (niri's own
  // default gaps are 16)
  property var _configGaps: ({
      "inner": 16,
      "struts": {
        "top": 0,
        "right": 0,
        "bottom": 0,
        "left": 0
      }
    })
  // The layouts niri's own config sets ("us,de"), for their short names
  property string _configLayouts: ""
  // What niri's Mod stands for, as axiom names it ("SUPER")
  property string _configModKey: "SUPER"

  // The gaps, struts, layouts, mod key and blur the config niri runs sets
  // (`axiom compositor niri info`)
  function _readConfig() {
    // Reads finish in any order: only the last asked for counts (the
    // running config may have changed between them)
    const asked = ++root._configReads;
    CommandManager.run([Paths.toolBin, "compositor", "niri", "info", "--config", CompositorConfigManager.runningConfig], (code, out) => {
      if (code !== 0 || asked !== root._configReads)
        return;
      try {
        const info = JSON.parse(out);
        root._configGaps = {
          "inner": Number(info.gaps) || 0,
          "struts": info.struts
        };
        root._configLayouts = info.layouts;
        root._configModKey = info.modKey || "SUPER";
        const blur = {
          "enabled": info.blur?.enabled !== false,
          "size": Number(info.blur?.offset) || 0,
          "passes": Number(info.blur?.passes) || 0
        };
        if (JSON.stringify(blur) !== JSON.stringify(root._blur))
          root._blur = blur;
      } catch (e) {}
    });
  }
  property int _configReads: 0
  // The outputs' names when last read, to tell a hotplug
  property string _outputNames: ""
  // The stream's first ConfigLoaded after it connects is the state niri
  // starts it with, not a reload
  property bool _startLoadSeen: false

  function _readOutputs() {
    root._request("Outputs", reply => {
      if (!reply?.Outputs)
        return;
      root._outputsReply = reply.Outputs;
      const names = Object.keys(reply.Outputs).sort().join(",");
      const changed = root._outputNames !== "" && names !== root._outputNames;
      root._outputNames = names;
      if (changed)
        root.outputsHotplugged();
    });
  }

  // --- niri's socket, through axiom (niri.request, niri.watch): Quickshell
  // has no niri module ---

  // Sends `request` ("Outputs", or an object) and calls back with its Ok
  // value, or null when niri refused it (logged) or didn't answer
  function _request(request, callback) {
    BackendManager.call("niri.request", {
      "request": request
    }, (error, result) => {
      if (error)
        console.warn("[NiriManager]", JSON.stringify(request).slice(0, 160) + ":", error.message);
      callback?.(error ? null : result);
    });
  }

  // Runs an action ({ "FocusWorkspace": { … } }) after those sent before,
  // then calls back with whether niri took it
  function _action(action, callback) {
    root._command({
      "Action": action
    }, callback);
  }

  // Sends a request that changes something ({ "Output": { … } }, an
  // action) after those sent before, so a chain split over several calls
  // can't overtake itself, then calls back with whether niri took it.
  // Requests for state go at once.
  function _command(request, callback) {
    _queue.push({
      "request": request,
      "callback": callback
    });
    if (!_running)
      _next();
  }

  property var _queue: []
  property bool _running: false

  function _next() {
    const item = _queue.shift();
    if (!item) {
      _running = false;
      return;
    }
    _running = true;
    root._request(item.request, reply => {
      item.callback?.(reply !== null);
      root._next();
    });
  }

  // niri's event stream, which axiom holds: niri.started when it
  // (re)connects (niri restarting), then each event, starting with the full
  // state (which holds a ConfigLoaded of its own). Watched again after every
  // hello: a new connection to axiom has no stream yet.
  function _watch() {
    if (BackendManager.ready)
      BackendManager.call("niri.watch", {}, error => {
        if (error)
          console.warn("[NiriManager] niri's event stream:", error.message);
      });
  }

  Component.onCompleted: {
    BackendManager.listen("niri.started", () => root._streamStarted());
    BackendManager.listen("niri.event", event => root._event(event));
    root._watch();
  }

  property Connections _greeted: Connections {
    target: BackendManager
    function onGreeted() {
      root._watch();
    }
  }

  function _streamStarted() {
    root._startLoadSeen = false;
    root._readOutputs();
    root._readConfig();
  }

  function _event(event) {
    const kind = Object.keys(event)[0];
    const before = root._state;
    root._state = NiriState.reduce(before, event);
    switch (kind) {
    case "WorkspacesChanged":
      root._outputsTimer.restart();
      break;
    case "WindowFocusChanged":
      {
        const id = event[kind].id;
        if (id !== null && id !== undefined)
          root.windowFocused(root._state.windows[String(id)]?.app_id ?? "");
        break;
      }
    case "KeyboardLayoutsChanged":
    case "KeyboardLayoutSwitched":
      root.keyboardLayoutChanged();
      break;
    case "ConfigLoaded":
      if (!root._startLoadSeen)
        root._startLoadSeen = true;
      else if (!root._state.configFailed) {
        root._readConfig();
        root.configReloaded();
      }
      break;
    }
  }

  // Outputs come and go with their workspaces: read again once a burst of
  // workspace events has settled
  property Timer _outputsTimer: Timer {
    interval: 100
    onTriggered: root._readOutputs()
  }

  // The gaps come from the config niri runs, which axiom's detached mode
  // changes
  property Connections _writer: Connections {
    target: CompositorConfigManager

    function onRunningConfigChanged() {
      root._readConfig();
    }
  }

  property Connections _screens: Connections {
    target: Quickshell

    function onScreensChanged() {
      root._outputsTimer.restart();
    }
  }
}
