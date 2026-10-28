# Backend contract

> **Files:** `services/compositor/CompositorManager.qml`, `services/compositor/HyprlandManager.qml`, `services/compositor/SwayManager.qml`, `services/compositor/NiriManager.qml`, `components/methods/HyprState.qml`, `components/methods/SwayState.qml`, `components/methods/NiriState.qml`, `components/methods/CompositorLayer.qml`, `tests/tst_HyprState.qml`, `tests/tst_CompositorLayer.qml`
> **Config:** none
> **Related:** [The compositor](README.md), [Sway backend](sway-backend.md), [niri backend](niri-backend.md)

What a compositor backend (`HyprlandManager`, `SwayManager`) gives `CompositorManager`. `CompositorManager`'s own defaults (empty lists, `""`, no-ops, `null` callbacks) are what a member the backend can't fill looks like.

### Shapes
Plain JS objects, rebuilt as the compositor reports changes. Converters sit in a pure helper with a test (`HyprState.window`, `output`, `workspace`; `tst_HyprState`).

- **Window**: `{ id, appId, initialAppId, title, workspaceId, workspaceName, output, floating, fullscreen, maximized, hidden, focusRank, x, y, w, h }`.
  - `id` is a string, stable while the window lives (Hyprland: its `"0x…"` address).
  - `output` is the output's name.
  - `fullscreen` means real fullscreen. A maximized window is `maximized`; it leaves reserved space alone.
  - `focusRank` 0 is the focused window, higher means used less recently. Undefined when unknown.
  - The geometry is global, in logical pixels.
  - Only mapped windows are listed.
  - Optional `column` and `tile` (1-based): its place in a strip where the compositor says (niri); `WorkspaceGeometry.stripOrder` orders by them over the geometry.
  - Optional `cover` (`{ x, y, w, h }`, with `windowCover`): where a window whose geometry isn't exact surely is while its workspace shows; `DockLayout.covered` uses it over the geometry.
- **Output**: `{ name, description, x, y, width, height, scale, focused, activeWorkspaceId, specialWorkspaceId, reserved: { top, right, bottom, left } }`.
  - `width`/`height` are logical.
  - `activeWorkspaceId` is -1 while unknown.
  - `specialWorkspaceId` is 0 when none is open.
  - `description` is what `MonitorLayout.outputId` keys a stable identity on.
- **Workspace**: `{ id, name, output, windowCount, active, focused }`.
  - `id` is the number axiom's layout uses (`WorkspacesConfig`).
- **Keyboard** (`withKeyboard`): `{ layouts: ["us", "de"], index, keymap }`, or null.
- **Layer rects** (`withLayerRects`): `{ [output]: { w, h, layers: [{ namespace, x, y, w, h }] } }`, or null. Axiom places its layers itself (`LayerManager`); where this is given, it corrects each window by how far the compositor's rect differs (what axiom doesn't arrange: other apps' layers, reserved space).

### Backend members
- **State**: `windows`, `outputs`, `workspaces`, `focusedOutput`, `activeWindowId`, `gapsOut` (`{ top, right, bottom, left }`), `blur` (`{ enabled, size, passes }`), `splitWidthMultiplier`, `surfacesReady`, `supports`, `travelingTo` (the workspace a multi-leg switch has reached, -1 when none is under way).
- **Optional**: `ready` (false while `supports` isn't final: sway asks whether it's SwayFX; `CompositorConfigManager` waits for it), `displayName` (a variant's name, "SwayFX"), `unsupportedHint(capability)` (what can do what this can't, for a greyed-out setting's note and the onboarding's: `CompositorManager.unsupportedHint`, `unsupportedNote`), `builtInBinds` (`{ action: key }`, as axiom writes keys: binds the compositor does itself and can't be told to, niri's Mod + drag; the Keybinds page notes a bind on that key instead of flagging it, and warns of one on another). Left out: ready, named by `kind`, no hint, none built in.
- **Signals**: `layersChanged`, `outputsHotplugged`, `configReloaded`, `keyboardLayoutChanged`, `windowFocused(appId)`. The facade re-emits them.
- **Window switcher** (with `switcher`): signal `switcherKey(verb, argument)` (`step` with the step, `commit`, `cancel`), sent while the compositor holds the switcher's keys; `leaveSwitcher()` lets them go (a tile was clicked). `WindowSwitcherManager` listens to the backend directly.
- **Windows**: `activateWindow(id)` (focus where it is), `closeWindow(id)`, `placeWindow(…)` and `resizeWindow(…)` (the overview), `toplevelFor(id)` (a `Quickshell.Wayland` toplevel, for previews).
- **Workspaces**:
  - `travel(output, legs, mode, focusId)`: focus `output` first when it's set, go through each `{ id, axis }` leg in turn, and arrive with `mode` (`go` | `move`) or by focusing window `focusId`.
    - A backend that can't slide goes straight to the last leg.
    - The facade only asks for legs with `supports.workspaceSlide`.
  - `sendWindowToWorkspace(id)` (moveSilent)
  - `scrollStrip(direction)`
  - `applyRemap(plan, outputNames)`
  - `refresh()`
  - With `dynamicWorkspaces`: `blockSize` (ids in each output's block, more than it'll have), `focusOutput(name)` and `moveWindowToOutput(name, follow)` (left and right steps go to the next output).
- **Outputs** (the Monitors page; `monitors`): `withOutputDetails(cb)`: every output, disabled ones too, as `{ name, description, width, height, refreshRate, x, y, scale, transform (0-7, Wayland's), disabled, mirrorOf ("none" or a name), vrr, availableModes: ["WxH@RHz"] }` plus optional `currentFormat`, `colorManagementPreset`, `sdrBrightness`, `sdrSaturation` (Hyprland's monitors JSON; `MonitorLayout` reads them), or null; `applyOutputs(rules, details)`: set the outputs as the `MonitorRule`s say, now (`details` resolve a mirror's connector): `CompositorManager` sends them to axiom (`outputs.apply`, answered by the greeter's axiom too), which sends them on in the compositor's terms (`daemon/compositorsocket.go`, from `compositor/render`), and then calls the backend's optional `outputsApplied()` (niri and sway read their outputs again, Hyprland its windows). With `outputProfiles` the compositor also picks the saved profile for what's connected on every hotplug (Hyprland's Lua layer); without it `MonitorManager` applies it at start, after `outputsHotplugged`, and after `configReloaded` while no file of axiom's is loaded; a writer whose compositor resets outputs on a reload writes the matching profile into its files (sway's).
- **Binds** (the Keybinds page): `withMainBinds(cb)`: the binds in effect outside the backend's own modes, as `{ modmask, key, keycode, description, submap }` (`modmask` in X11 bits: SHIFT 1, CAPS 2, CTRL 4, ALT 8, MOD2 16, MOD3 32, SUPER 64, MOD5 128; `BindKeys`), or null (`bindMerge`); `captureKeys(on)`: while on, every key reaches axiom instead of a bind (`keyCapture`). The facade's `withBinds` / `captureKeys` check the capability.
- **Session and input**: `withKeyboard(cb)`, `cycleKeyboardLayout(direction, cb)`, `withCursorPos(cb)`, `warpCursorToLayer(…)`, `withLayerRects(cb)`, `exitSession()`. Turning the screens off for idle is the daemon's (`Manager.ScreenPower`, over the compositor's socket).
- **Config layer** (with `configModes`): the daemon writes axiom's layer into the compositor's config in each mode ([config modes](config-modes.md)), talking to the compositor itself. Optional members it relies on: `layerApplied()` (it changed the compositor at runtime: read back what the backend follows, Hyprland's options, sway's windows), `setLiveLook(look)` (sway: the look set a window at a time as windows open), `fx` (SwayFX), and `withSetupCheck(cb)` for the onboarding's Compositor page (`CompositorManager.withSetupCheck`): calls back with `{ supported, problem, legacyNote }`, whether axiom can set the compositor up, why not ("" while unknown), and what a config of the user's in an older format means (Hyprland: a version before 0.55, a `hyprland.conf`); without it, supported with no notes.

### Capabilities
`supports` keys (absent means false):

| Key | What it gates |
|---|---|
| `configModes` | the daemon has a config writer for it: the Compositor, Input and Session settings, `CompositorConfigManager` ([config modes](config-modes.md)), the onboarding's setup page |
| `keybinds` | the Keybinds page (`x-needs`), `KeybindManager` |
| `monitors` | the Monitors page, `MonitorManager` |
| `switcher` | Alt+Tab driven by compositor keys (`WindowSwitcherManager`) |
| `switcherRelease` | the compositor reports letting go of the switcher's modifier itself (Hyprland's submap). Without it `SwitcherKeys` takes the keyboard while the switcher is open, to see the release |
| `strips` | the strip settings, scrolling a strip |
| `stripsAlways` | every output is a strip (niri): `stripDirection` is `horizontal` everywhere, the strip list is hidden |
| `outputWorkspaces` | the compositor's workspaces belong to an output: every layout gets a block of ids per output (`CompositorManager.perMonitorBlocks`), and nothing is remapped |
| `dynamicWorkspaces` | the compositor makes and removes workspaces itself, one list per output (niri): `workspaceIds` are the ones it has, the Workspaces section's layout is greyed out (its `x-intro` says why), up and down steps go through the list and left and right to the next output (`WorkspaceGeometry.outputToward`), the bar shows its workspaces with windows and the active one, the overview a column. Needs `outputWorkspaces`. A backend may also claim it for the scrolling layout, keeping niri's workspaces itself (Hyprland: its `dynamicByLayout`, so `CompositorManager.dynamicByLayout`): the layout stays editable and its intro doesn't show ([workspace strips](../hyprland/workspace-strips.md) › The scrolling layout) |
| `focusGrab` | the native grab in `FocusGrab` |
| `layerOrder` | the compositor stacks and arranges axiom's layers by `LayerStack.layers` itself (layer rules). Without it `LayerManager` maps them in that order and maps again any that land out of place ([layer arrangement](layer-arrangement.md)) |
| `blur` | the compositor blurs axiom's translucent surfaces |
| `blurThreshold` | the blur leaves pixels under `Appearance.blurThreshold` out (Hyprland's `ignore_alpha`), so the blur window casts the chrome's shadows itself, under it (`Appearance.shadowAlphaMax`). Without it (SwayFX, whose `blur_ignore_transparent` leaves out only clear pixels) windows of their own that aren't blurred cast them (`axiom-shadows`, `axiom-shadows-overlay`; `shell/BlurBacking.qml`) |
| `blurRegion` | the compositor blurs a window only where the window asks (ext-background-effect, Quickshell's `BackgroundEffect.blurRegion`; niri): no layer rule decides what blurs. The blur window sends its shapes as drawn (`SurfaceOutline.blurRegion`), and each surface that blurs itself its box (`reusable/BoxBlurRegion`), while `BlurManager.regions`; the shadows stay in the blur window, outside every region |
| `cursorPos`, `cursorWarp` | `withCursorPos`, `warpCursorToLayer` |
| `windowGeometry` | window positions and sizes are real: without it the screenshot's window mode is left out (`ScreenshotManager.kinds`; a `window` request takes a region) and no window obscures a dock (`DockManager.obscured`) unless `windowCover`. The overview still draws windows where they say they are |
| `outputCapture` | Quickshell captures an output safely (the compositor has ext-image-copy-capture): the screenshot picker's frozen frame is a `ScreencopyView`. Without it (niri, wlr-screencopy only, whose capture in Quickshell crashes the shell: [issues](../issues.md)) grim takes it (`ScreenshotManager.grimFrames`) |
| `layerFrameSync` | changes axiom makes to its layer windows in one pass show in the same frame (Hyprland, sway). Without it (niri) another window's can show a frame or so late, so context following a sliding surface along its slide (`PillBarJoin`, a joined submenu's pill reach) leads its wall by a stroke (`EdgePlacement._slideLead`) |
| `windowCover` | without `windowGeometry`, windows carry a `cover` (niri's tiled ones), which obscures a dock (`DockManager.obscured`) |
| `workspaceSlide` | `travel` legs slide |
| `windowBorders`, `windowShape`, `windowGaps`, `windowBlur`, `windowOpacity` | the `WindowLook` parts shown and applied |
| `windowRounding` | the shape part's rounding (plain sway's shape is the border width alone) |
| `windowShadow`, `windowDim` | the window look's shadow and dim parts |
| `inputConfig` | axiom sets the keyboard, mouse and touchpad |
| `keyCapture` | the Keybinds page's recorder can take keys from the compositor's binds: `captureKeys`, or the recorder window's shortcut inhibitor alone (niri) |
| `modifierTap` | a bind can be on a modifier key alone, fired when it's tapped (`KeyNames.tapModifier`: Hyprland, sway). Without it such a bind is warned about and left out (niri fires binds only on press) |
| `bindMerge` | the user's own binds can be read (the Keybinds page's List, conflicts, Merge) |
| `monitorColor` | a monitor rule's bit depth, color management and SDR fields |
| `monitorMirror` | a monitor rule can mirror another output |
| `outputProfiles` | the compositor applies the saved monitor profile for what's connected by itself, on every hotplug |
| `namedSpecial` | named special workspaces (the `toggleSpecial` / `moveToSpecial` binds) |
| `scratchpad` | a scratchpad (sway's), standing in for the special workspace in those binds |
| `mouseBinds` | binds on mouse buttons (`mouseDrag`, `mouseResize`) |
| `pseudoTile` | the `pseudo` bind |
| `splitToggle` | the `toggleSplit` bind (Hyprland's dwindle layout: on its scrolling layout the bind gets an info note) |
| `pin` | the `pin` bind (a floating window shown on every workspace) |
| `windowGroups` | the `toggleGroup` bind |
