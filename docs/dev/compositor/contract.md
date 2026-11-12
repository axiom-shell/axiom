# Backend contract

> **Files:** `qml/services/compositor/CompositorManager.qml`, `qml/services/compositor/HyprlandManager.qml`, `qml/services/compositor/SwayManager.qml`, `qml/services/compositor/NiriManager.qml`, `qml/components/methods/HyprState.qml`, `qml/components/methods/SwayState.qml`, `qml/components/methods/NiriState.qml`, `tests/tst_HyprState.qml`
> **Config:** none
> **Related:** [The compositor](README.md), [Sway backend](sway-backend.md), [niri backend](niri-backend.md)

What a compositor backend (`HyprlandManager`, `SwayManager`) gives `CompositorManager`. `CompositorManager`'s own defaults (empty lists, `""`, no-ops, `null` callbacks) are what a member the backend can't fill looks like.

### Shapes
Plain JS objects, rebuilt as the compositor reports changes. Converters sit in a pure helper with a test (`HyprState.window`, `output`, `workspace`; `tst_HyprState`).

- **Window**: `{ id, appId, initialAppId, title, workspaceId, workspaceName, output, floating, fullscreen, maximized, hidden, focusRank, x, y, w, h }`.
  - `id` is a string, stable while the window lives (Hyprland: its `"0x…"` address).
  - `output` is the output's name.
  - `workspaceId`: a named or special workspace has a negative id of its own (Hyprland's; sway's minus its con id), not -1 (unknown), so consumers tell them apart (`hasFullscreen`, a dock's `workspace` scope).
  - `fullscreen` means real fullscreen. A maximized window is `maximized`; it leaves reserved space alone.
  - `focusRank` 0 is the focused window, higher means used less recently. Undefined when unknown.
  - The geometry is global, in logical pixels.
  - Only mapped windows are listed.
  - Optional `column` and `tile` (1-based): its place in a strip where the compositor says (niri); `WorkspaceGeometry.stripOrder` orders by them over the geometry.
  - Optional `cover` (`{ x, y, w, h }`, with `windowCover`): where a window whose geometry isn't exact surely is while its workspace shows; `DockLayout.covered` uses it over the geometry.
- **Output**: `{ name, description, x, y, width, height, scale, focused, activeWorkspaceId, specialWorkspaceId, reserved: { top, right, bottom, left } }`.
  - `width`/`height` are logical.
  - `reserved` is what layer surfaces take from each edge: the compositor's own count where it gives one (Hyprland, sway), else axiom's layers' alone (niri: `LayerArrange.arrange`). The workspace overview reads it (and `Special.windows` for its scratch cells): its cells show the usable area (the output less `reserved`), so a window's global `x`/`y` must already include it (niri's tiled ones do, `NiriState.windows`).
  - `activeWorkspaceId` is -1 while unknown.
  - `specialWorkspaceId` is 0 when none is open.
  - Optional `specialWorkspaceName` (Hyprland's: `special:magic`, `""` when none is open): Hyprland 0.57 gives a special workspace no id, so `HyprState.specials` matches by name.
  - `description` is what `MonitorLayout.outputId` keys a stable identity on.
- **Workspace**: `{ id, name, output, windowCount, active, focused, urgent }`. `urgent`: a window on it asks for attention (Hyprland's and sway's workspace `urgent`, niri's `is_urgent`; a dynamic list's added empty one never is).
  - `id` is the number axiom's layout uses (`WorkspacesConfig`).
- **Special**: `{ name, id, open, output, windowCount, urgent, windows }`, a special workspace (scratchpad) for the switcher's cells (`CompositorManager.specials`; `HyprState.specials`, `SwayState.specials`).
  - `name` is the name a `toggleSpecial` bind takes (Hyprland's `special:magic` is `magic`).
  - `id` is the compositor's workspace id while it is a workspace (Hyprland's negative id, or -1 where Hyprland gives none; sway's workspace mode: minus its con id), else 0 (a sway scratchpad group). Never match on it for Hyprland: `HyprState.specials` matches workspaces, outputs and windows by name.
  - `output` is the output it is open on, or `""`; `open` is `output !== ""`.
  - `windows` are its windows in the Window shape, sway's hidden scratchpad ones included (`hidden: true`, `output: ""`); `windowCount` is their count.
  - `urgent`: the workspace's (always false for a sway scratchpad group).
- **Keyboard** (`withKeyboard(cb, registry)`): `{ layouts: ["us", "de"], index, keymap }`, or null. `layouts` are the codes of the layouts the compositor has: for one that names them in full (niri, sway), the layout `registry` gives each name (the xkb registry, `InputSourceManager.registry` from the daemon's `input.layouts`; `KeyboardLayouts.shape`), so an unsaved edit or a reorder of the config never relabels them; a name it doesn't list takes the configured code at its place (`Input.keyboard.sources`' xkb list while axiom sets the keyboard, else the compositor's own config) when there are as many, else a guess (`KeyboardLayouts.code`).
- **Layer rects** (`withLayerRects`): `{ [output]: { w, h, layers: [{ namespace, x, y, w, h }] } }`, or null. Axiom places its layers itself (`LayerManager`); where this is given, it corrects each window by how far the compositor's rect differs (what axiom doesn't arrange: other apps' layers, reserved space).

### Backend members
- **State**: `windows`, `outputs`, `workspaces`, `focusedOutput`, `activeWindowId`, `gapsOut` (`{ top, right, bottom, left }`), `blur` (`{ enabled, size, passes }`), `splitWidthMultiplier`, `surfacesReady`, `wallpaperStill` (optional, true when left out: the background layer stays put while workspaces slide; niri's only while axiom's config puts the wallpaper in its backdrop), `supports`, `travelingTo` (the workspace a multi-leg switch has reached, -1 when none is under way).
- **Optional**: `ready` (false while `supports` isn't final: sway asks whether it's SwayFX; `CompositorConfigManager` waits for it), `displayName` (a variant's name, "SwayFX"), `unsupportedHint(capability)` (what can do what this can't, for a greyed-out setting's note and the onboarding's: `CompositorManager.unsupportedHint`, `unsupportedNote`), `builtInBinds` (`{ action: key }`, as axiom writes keys: binds the compositor does itself and can't be told to, niri's Mod + drag; the Keybinds page notes a bind on that key instead of flagging it, and warns of one on another), `stockWallpapers` (a glob under a data dir for the wallpapers the compositor's package ships, Hyprland's `hypr/wall*.png`, sway's `backgrounds/sway/*.png`: the onboarding's Look page offers that folder while the wallpaper folder is missing). Left out: ready, named by `kind`, no hint, none built in, no wallpapers offered.
- **Signals**: `outputsHotplugged`, `configReloaded`, `keyboardLayoutChanged`, `windowFocused(appId)`, and optionally `layersChanged` (Hyprland's alone). The facade re-emits them.
- **Window switcher** (with `switcher`): signal `switcherKey(verb, argument)` (`step` with the step, `commit`, `cancel`), sent while the compositor holds the switcher's keys; with `switcherRelease`, `leaveSwitcher()` lets them go (a tile was clicked). `WindowSwitcherManager` listens to the backend directly.
- **Windows**: `activateWindow(id)` (focus where it is), `closeWindow(id)`, `placeWindow(…)` and `resizeWindow(…)` (the overview), `toplevelFor(id)` (a `Quickshell.Wayland` toplevel, for previews).
- **Workspaces**:
  - `travel(output, legs, mode, focusId)`: focus `output` first when it's set, go through each `{ id, axis }` leg in turn, and arrive with `mode` (`go` | `move`) or by focusing window `focusId`.
    - A backend that can't slide goes straight to the last leg.
    - The facade only asks for legs with `supports.workspaceSlide`.
  - `sendWindowToWorkspace(id)` (moveSilent)
  - `specials` (optional, `[]` when left out), `toggleSpecial(name, output)` (`output` "" is the focused one) and `moveToSpecial(name, id)` (with `namedSpecial`; `id` "" or left out is the focused window, else that window, leaving the special shown or hidden as it was)
  - `scrollStrip(direction)` (with `strips`)
  - `applyRemap(plan, outputNames)` (without `outputWorkspaces`): a layout change's remap, and after a hotplug the re-homing of an unplugged output's workspaces, which the compositor must itself have moved to an output still connected (Hyprland's and sway's do; [workspaces › Hotplugs](../hyprland/workspaces.md#hotplugs-an-unplugged-monitors-windows))
  - `returnWorkspaces(plan)` (where `applyRemap` is): puts re-homed windows back once their monitor is back (`WorkspaceGeometry.returnWindows`' `{ moves: [{ id, to, monitor }], workspaces: [{ id, monitor }], show: [{ monitor, id }] }`): each window to its workspace, each of `workspaces` onto its monitor, each monitor of `show` to that workspace, with the focus and the focused monitor's workspace left as they were ([workspaces › Hotplugs](../hyprland/workspaces.md#hotplugs-an-unplugged-monitors-windows))
  - `refresh()`
  - With `dynamicWorkspaces`: `blockSize` (ids in each output's block, more than it'll have), `focusOutput(name)` and `moveWindowToOutput(name, follow)` (left and right steps go to the next output).
- **Outputs** (the Monitors page; `monitors`): `withOutputDetails(cb)`: every output, disabled ones too, as `{ name, description, width, height, refreshRate, x, y, scale, transform (0-7, Wayland's), disabled, mirrorOf ("none", a name, or Hyprland's id of the mirrored output), vrr, availableModes: ["WxH@RHz"] }` plus optional `currentFormat`, `colorManagementPreset`, `sdrBrightness`, `sdrSaturation` (Hyprland's monitors JSON; `MonitorLayout` reads them), or null; `applyOutputs(rules, details, revert)`: set the outputs as the `MonitorRule`s say, now (`details` resolve a mirror's connector): `CompositorManager` sends them to axiom (`outputs.apply`, answered by the greeter's axiom too), which sends them on in the compositor's terms (`daemon/compositorsocket.go`, from `compositor/render`; every part of a rule, its defaults too: Hyprland's `hl.monitor` and niri's Output requests change only the parts given, so a revert has to name them all (but Hyprland's vrr 0, which would override `misc:vrr`, except in a revert: `applyOutputs(rules, details, true)`, whose rules picture the outputs before an Apply, a vrr 0 sent as `misc:vrr`'s value); sway's `output` command does already), and then calls the backend's optional `outputsApplied()` (niri and sway read their outputs again, Hyprland its windows). The daemon applies the saved profile for what's connected on every compositor (`manager.Manager`, on its own output hotplugs, a config change, and a reload while no file of axiom's is loaded; [sway](sway-backend.md), [Hyprland](../hyprland/monitors.md)) and writes it into axiom's files, so a reload keeps it; a hotplug then ends a trial Apply on the Monitors page without reverting.
- **Binds** (the Keybinds page): optional `withMainBinds(cb)`: the binds in effect outside the backend's own modes, as `{ modmask, key, keycode, description, submap }` (`modmask` in X11 bits: SHIFT 1, CAPS 2, CTRL 4, ALT 8, MOD2 16, MOD3 32, SUPER 64, MOD5 128; `BindKeys`), or null (`bindMerge`; without it the facade's `withBinds` gives the daemon's, `CompositorConfigManager.withEntries`: the user's config and axiom's, as sway and niri have them); `captureKeys(on)`: while on, every key reaches axiom instead of a bind (`keyCapture`). The facade's `withBinds` / `captureKeys` check the capability.
- **Session and input**: `withKeyboard(cb, registry)`, `setKeyboardLayout(index, cb)` (every keyboard to the layout at that index; `InputSourceManager.set`), `exitSession()`, and optionally `withCursorPos(cb)` (with `cursorPos`), `warpCursorToLayer(…)` (with `cursorWarp`) and `withLayerRects(cb)` (without it, null). Turning the screens off for idle is the daemon's (`Manager.ScreenPower`, over the compositor's socket).
- **Config layer** (with `configModes`): the daemon writes axiom's layer into the compositor's config in each mode ([config modes](config-modes.md)), talking to the compositor itself. Optional members it relies on: `layerApplied()` (it changed the compositor at runtime: read back what the backend follows, Hyprland's options, sway's windows), `setLiveLook(look)` (sway: the look set a window at a time as windows open; the daemon's, `compositor.state`'s `look`), `fx` (SwayFX), and `withSetupCheck(cb)` for the onboarding's Compositor page (`CompositorManager.withSetupCheck`): calls back with `{ supported, problem, legacyNote }`, whether axiom can set the compositor up, why not ("" while unknown), and what a config of the user's in an older format means (Hyprland: a version before 0.55, a `hyprland.conf`); without it, supported with no notes.

### Capabilities
`supports` keys (absent means false):

| Key | What it gates |
|---|---|
| `configModes` | the daemon has a config writer for it: the Compositor, Input and Session settings, `CompositorConfigManager` ([config modes](config-modes.md)), the onboarding's setup page |
| `keybinds` | the Keybinds page (`x-needs`), `KeybindManager` |
| `monitors` | the Monitors page, `MonitorManager` |
| `switcher` | Alt+Tab driven by compositor keys (`WindowSwitcherManager`) |
| `switcherRelease` | the compositor reports letting go of the switcher's modifier itself (Hyprland's submap), and `leaveSwitcher()` lets the keys go. Without it the daemon holds the keyboard while the switcher is open (`switcher.hold`, [window switcher](../hyprland/window-switcher.md) › sway and niri), to see the release |
| `strips` | the strip settings, scrolling a strip |
| `stripsAlways` | every output is a strip (niri): `stripDirection` is `horizontal` everywhere, the strip list is hidden |
| `outputWorkspaces` | the compositor's workspaces belong to an output: every layout gets a block of ids per output (`CompositorManager.perMonitorBlocks`), and nothing is remapped |
| `dynamicWorkspaces` | the compositor makes and removes workspaces itself, one list per output (niri): `workspaceIds` are the ones it has, the Workspaces section's layout is greyed out (its `x-intro` says why), up and down steps go through the list and left and right to the next output (`WorkspaceGeometry.outputToward`), the bar shows its workspaces with windows and the active one, the overview a column. Needs `outputWorkspaces`. A backend may also claim it for the scrolling layout, keeping niri's workspaces itself (Hyprland: its `dynamicByLayout`, so `CompositorManager.dynamicByLayout`): the layout stays editable and its intro doesn't show ([workspace strips](../hyprland/workspace-strips.md) › The scrolling layout) |
| `verticalWorkspaces` | an output's workspaces stack top to bottom (niri): the wallpaper's workspace parallax moves up and down (`WallpaperFill.parallax`) |
| `focusGrab` | the native grab in `FocusGrab` |
| `layerOrder` | the compositor stacks and arranges axiom's layers by `LayerStack.layers` itself (layer rules). Without it `LayerManager` maps them in that order and maps again any that land out of place ([layer arrangement](layer-arrangement.md)) |
| `layerRestack` | a layer window moved to another layer lands on top of it, as if just mapped (sway: its scene tree). Without `layerOrder`, `LayerManager` then counts the move as a new map, so the windows ordered over it map again ([layer arrangement](layer-arrangement.md)). niri keeps the window's place (checked in 26.04) |
| `blur` | the compositor blurs axiom's translucent surfaces |
| `blurThreshold` | the blur leaves pixels under `Appearance.blurThreshold` out (Hyprland's `ignore_alpha`), so the blur window casts the chrome's shadows itself, under it (`Appearance.shadowAlphaMax`). Without it (SwayFX, whose `blur_ignore_transparent` leaves out only clear pixels) windows of their own that aren't blurred cast them (`axiom-shadows`, `axiom-shadows-overlay`; `qml/shell/BlurBacking.qml`) |
| `blurRegion` | the compositor blurs a window only where the window asks (ext-background-effect, Quickshell's `BackgroundEffect.blurRegion`; niri): no layer rule decides what blurs. The blur window sends its shapes as drawn (`SurfaceOutline.blurRegion`), and each surface that blurs itself its box (`reusable/BoxBlurRegion`), while `BlurManager.regionsOn` their screen; the shadows stay in the blur window, outside every region |
| `cursorPos`, `cursorWarp` | `withCursorPos`, `warpCursorToLayer` |
| `windowGeometry` | window positions and sizes are real: without it the screenshot's window mode is left out (`ScreenshotManager.kinds`; a `window` request takes a region) and no window obscures a dock (`CompositorManager.windowsCover`) unless `windowCover`. The overview still draws windows where they say they are |
| `outputCapture` | Quickshell captures an output safely (the compositor has ext-image-copy-capture): the screenshot picker's frozen frame is a `ScreencopyView`. Without it (niri, wlr-screencopy only, whose capture in Quickshell crashes the shell) grim takes it (`ScreenshotManager.grimFrames`) |
| `layerFrameSync` | changes axiom makes to its layer windows in one pass show in the same frame (Hyprland, sway). Without it (niri) another window's can show a frame or so late, so context following a sliding surface along its slide (`PillBarJoin`, a joined submenu's pill reach) leads its wall by a stroke (`EdgePlacement._slideLead`) |
| `windowCover` | without `windowGeometry`, windows carry a `cover` (niri's tiled ones), which obscures a dock (`CompositorManager.windowsCover`) |
| `workspaceSlide` | `travel` legs slide |
| `windowBorders`, `windowShape`, `windowGaps`, `windowBlur`, `windowOpacity` | the `WindowLook` parts shown and applied |
| `fullscreenOpacity` | the window look's fullscreen opacity (niri's opacity rules can't match a fullscreen window) |
| `blurContrast` | the window blur's contrast (Hyprland, SwayFX; niri's blur has none) |
| `focusOnActivate` | Windows and focus › Focus windows that ask for it (niri has no such switch: it always focuses a window that asks with a valid token) |
| `windowRounding` | the shape part's rounding (plain sway's shape is the border width alone) |
| `windowShadow`, `windowDim` | the window look's shadow and dim parts |
| `inputConfig` | axiom sets the keyboard, mouse and touchpad (the Input section's keyboard, mouse, touchpad and cursor cards; its sources and input method show without it) |
| `inputMethod` | the compositor offers `zwp_input_method_manager_v2`, which fcitx5 and ibus type through. Not the backend's: the daemon's Wayland registry says (`wayland.state`'s `inputMethod`, `WaylandManager.inputMethod`), merged into `supports` with or without a backend ([input sources](../features/input-sources.md)) |
| `keyCapture` | the Keybinds page's recorder can take keys from the compositor's binds: `captureKeys`, or the recorder window's shortcut inhibitor alone (niri) |
| `modifierTap` | a bind can be on a modifier key alone, fired when it's tapped (`KeyNames.tapModifier`: Hyprland, sway). Without it such a bind is warned about and left out (niri fires binds only on press) |
| `releaseBinds` | a bind can fire on release (its `release` flag): without it the Keybinds inspector's Fire on release is greyed out and a bind carrying the flag (axiom's own `restartShell` and `exitSession`, one merged from another compositor) is written as a press bind (niri) |
| `bindMerge` | the user's own binds can be read (the Keybinds page's List, conflicts, Merge) |
| `monitorColor` | a monitor rule's bit depth, color management and SDR fields |
| `monitorMirror` | a monitor rule can mirror another output |
| `namedSpecial` | named special workspaces (the `toggleSpecial` / `moveToSpecial` binds, the switcher's scratchpads: `CompositorManager.specials`) |
| `scratchpad` | a scratchpad (sway's), standing in for the special workspace in those binds |
| `mouseBinds` | binds on mouse buttons (`mouseDrag`, `mouseResize`) |
| `pseudoTile` | the `pseudo` bind |
| `splitToggle` | the `toggleSplit` bind (Hyprland's dwindle layout: on its scrolling layout the bind gets an info note) |
| `pin` | the `pin` bind (a floating window shown on every workspace) |
| `windowGroups` | the `toggleGroup` bind |
| `compositorSwitcher` | the compositor has a window switcher of its own its config can bind (niri's `recent-windows`): while `WindowSwitcher.compositorSwitcher` is on (shown only with it), the daemon's writer binds the switch windows keys to it instead of axiom's IPC, in the included and managed files only, managed writing them empty when no such bind is axiom's or the setting is off (`render.NiriRecentWindows`, `manager` `niriWriter.parts`) |
| `overview` | the compositor has an overview of its own, the backend's `overview(verb)` (`open`, `close`, `toggle`; `CompositorManager.compositorOverview`): while `WorkspaceOverlay.compositorOverview` is on (shown only with it), everything that opens axiom's workspace overview (its IPC, binds, `/overview`, bar buttons) opens that instead (`qml/shell/WorkspaceOverlay.qml`) |
