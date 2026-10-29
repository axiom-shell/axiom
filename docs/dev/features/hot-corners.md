# Hot corners

> **Files:** `config/HotCornersConfig.qml`, `backend/internal/compositor/manager/niri.go` (`managedText`), `backend/internal/migrate/steps/v82.go`, `shell/HotCorners.qml`, `services/ui/ShellManager.qml` (`runAction`), `components/methods/BindActions.qml` (`ipcCall`)
> **Config:** `HotCorners.items` (reader `HotCornersConfig`)
> **Related:** [ShellManager and screen targeting](../core/shell-manager-targeting.md), [Keybinds](../hyprland/keybinds.md), [Layer arrangement](../compositor/layer-arrangement.md), [niri backend](../compositor/niri-backend.md)

axiom's own hot corners, drawn by the shell, so they work the same on every compositor. None are set by default, so nothing is mapped until one is.

### Config (`HotCorners` section, Overlay & Popouts)
- `items[]`: `id`, `corner` (`topLeft` | `topRight` | `bottomLeft` | `bottomRight`), `action` with its `argument`, `screen` (a `ScreenTarget`: every monitor, the primary one or named ones), `delay` (ms, 0 by default, as niri's corner fires at once).
- `action` is any axiom action: the keybind table's `ipcActions` (`backend/internal/compositor/actions/table.json`), or `exec` with a command (`x-scopeIf` makes that item `commands`). `tst_BindActions` checks the enum and the argument's `x-showIf` against the table.
- The generated form shows the list as one card (`x-wide`).

### Windows (`shell/HotCorners`)
- One transparent 1 px `PanelWindow` per item per screen (`General.screensFor`), anchored to its corner, `ExclusionMode.Ignore`, keyed by item id, built once `CompositorManager.surfacesReady` (the layer rules are in), as the bars and docks are.
- On `Top`, so a fullscreen window covers it and the corner is quiet in games and videos, as the bars are. Its `LayerSlot` (`axiom-hot-corner`, `LayerStack.layers`) maps it after the bars, border and docks, so a corner they sit in is still the corner's.
- Entering starts the delay; leaving stops it. The action runs once per visit, through `ShellManager.runAction`, which sends the action's IPC call (`BindActions.ipcCall`) through the daemon's `ipc.call`, landing on the target instance as a bind's would.
- The corner pixel takes the click too: a Wayland input region can't take hover and pass clicks through.

### niri
In managed mode niri's own corner is always off (`gestures.hot-corners.off`, written by the managed niri config), so a corner exists only where axiom sets one; detached and included leave niri's alone, as they leave its binds. `Compositor.niri.hotCorner` went in config v82: on in managed mode, it became a top-left corner on every monitor opening the workspace overview, which with `WorkspaceOverlay.compositorOverview` is niri's own.
