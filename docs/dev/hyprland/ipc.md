# Talking to Hyprland (IPC)

> **Files:** `services/compositor/HyprlandIpcManager.qml`, `components/methods/HyprReply.qml`, `services/compositor/HyprlandManager.qml`, `components/methods/HyprState.qml`, `services/compositor/HyprlandGrab.qml`
> **Config:** none
> **Related:** [The compositor](../compositor/README.md), [Config modes](config-modes.md), [Workspaces](workspaces.md), [Monitors](monitors.md)

How the shell reads from and acts on Hyprland, without running `hyprctl`.

### Two routes
- **Quickshell's `Quickshell.Hyprland`** covers monitors, workspaces, toplevels, the event stream (`rawEvent`) and `Hyprland.dispatch()`. Use it whenever it has what's needed, from the `Hyprland*` services only (Rules).
  - `dispatch()` gives no reply, and sends the string as is: it must be Lua (`hl.dsp.*`).
  - A monitor's or toplevel's `lastIpcObject` only updates after a `refresh*()`; `refreshToplevels()` never removes a closed window.
- **`HyprlandIpcManager`** sends what Quickshell doesn't cover to Hyprland's request socket, as hyprctl does, without a process each: `request(command, cb)`, `json("clients", cb)`, `jsonBatch(["getoption …", "animations"], cb)`, `evalLua(lua, cb)` (`"ok"` or the error).

### Rules
- **`HyprlandManager` is `CompositorManager`'s backend on Hyprland** ([The compositor](../compositor/README.md)). The rest of the shell asks `CompositorManager`, which hands out [neutral shapes](../compositor/contract.md#shapes) (`HyprState` converts Hyprland's replies). Only the Hyprland-only features use `HyprlandManager` directly (its version reaches the onboarding through `CompositorManager.withSetupCheck`): `runLua`, `withOutputs`, `withBinds`, `setCursor`, `refreshOptions`, `animations`, `switcherKey`.
- **Only the `Hyprland*` services send anything to Hyprland** (`HyprlandIpcManager`, `Hyprland.dispatch()`) **or import `Quickshell.Hyprland`.** `check_structure` enforces both the import and who may name `HyprlandManager`.
- Events become signals, never `rawEvent` names (`_announce` maps them): `layersChanged`, `outputsHotplugged`, `configReloaded`, `keyboardLayoutChanged`, `windowFocused(appId)`, `switcherKey(verb, argument)`.
- Hyprland's focus grab is `HyprlandGrab`, which only `FocusGrab` creates.
- `runLua(lua, callback)` queues chunks and runs them one at a time, in order, calling back with Hyprland's reply (`"ok"` or the error). Something that must run after Lua already queued (the runtime layer's unbind) goes through it rather than `evalLua`. Once the queue drains, it refetches the window list and, if asked meanwhile, the options (`refreshOptions`).
- The options axiom follows (gaps, split multiplier, blur, the animations) are read in one batch: at startup, on `configreloaded`, and after axiom changes them.
- Commands that Hyprland runs, and shell scripts, still call `hyprctl` (the exit bind): they run outside the shell. DPMS for idle is the daemon's, over the socket (`Manager.ScreenPower`).

### The socket
- Hyprland answers one request per connection, then closes it. Each request gets its own `Socket`, closed by us once `HyprReply.complete` says the reply is all there (JSON once it parses, anything else once there's text): Quickshell warns `PeerClosedError` when Hyprland closes first.
- The parser's `splitMarker` is `""`: with a marker the last piece would be held back until the next marker, which never comes.
- A batch (`[[BATCH]]a;b`) gets its replies joined by `"\n\n\n"`. Don't batch `eval`s: their Lua may hold `;`.
- No reply within 5 s calls back with null (logged).
