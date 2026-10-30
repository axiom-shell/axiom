# compositor
reviewed: 028e7ea 2026-10-30  (full)

The facade holds: every consumer goes through CompositorManager, every backend member the facade calls exists or is gated by the documented `supports` key, layer order comes only from LayerStack, and config writing is gated on `configModes` (the shell sends facts only while `CompositorConfigManager.live`; the daemon applies nothing until facts naming its kind arrive). The biggest problem is outside the QML: the daemon detects the compositor on its own, by a fixed variable order without CompositorKind's still-running check, so a stale variable leaves the whole config layer dead. Two smaller bugs (Translucency card's blur test, cursor theme fallback) and two deletion-pass cleanups.

## Open findings
### 1. The daemon picks a compositor the shell may not run under  `backend/internal/compositor/manager/manager.go:136`
`manager.New`, `Outputs.Read/Apply` and `greeterHandlers` take the first of HYPRLAND_INSTANCE_SIGNATURE / NIRI_SOCKET / SWAYSOCK set, with no check that it still runs; the shell uses CompositorKind (still-running wins, order Hyprland, sway, niri). Under niri with a stale Hyprland signature the manager is Hyprland's, `live()` never holds (facts name niri), so no layer, status stuck on Checking, profiles/outputs.apply/ScreenPower hit a dead socket.
**Fix:** one Go `Detect(getenv)` with CompositorKind's rule used by all three; the daemon then starts qs with only the running compositor's variable, and CompositorKind.qml (68), tst_CompositorKind.qml (73), `CompositorManager._running` go. Recorded in issues.md.

### 2. The Translucency card reads the window look's blur object as a switch  `components/views/Settings/TranslucencyStatus.qml:52`
`WindowLookConfig.look.blur` is the Blur object, always truthy: the status always says "Set in Compositor → Window look.", the "Set the compositor's blur" button is never offered, and its branch would write `true` over `WindowLook.blur`.
**Fix:** read/set `blur.enabled` through a reader property; drop `WindowLookConfig.look`/`_lookJson`. Recorded.

### 3. A failed cursor theme call keeps the theme's own name all session  `services/ui/CursorThemeManager.qml:58`
On a `cursor.theme` error (logged three times across dev re-execs) `_resolve` settles on the raw theme name and never retries: the compositor gets the name without the companion.
**Fix:** `{ repeatable: true }`; on error keep the old `_resolved` and retry on `BackendManager.ready`. Recorded.

### 4. Backends keep stubs for calls the facade gates  `services/compositor/SwayManager.qml:179`
Sway's and niri's `withCursorPos`/`warpCursorToLayer` are unreachable (facade gates on cursorPos/cursorWarp, Hyprland only); their `withLayerRects` only call back null, as the facade's no-backend path does. ~22 lines.
**Fix:** delete; make `withLayerRects` optional in the facade; mark the three optional in contract.md and the recipe. Recorded.

### 5. Small shrinks in the compositor layer  `services/compositor/CompositorManager.qml:510`
`stepWorkspace` re-derives `WorkspacesConfig.columns/rows`; `copyIncludeLines`/`copyAutostartLines` wrap one ClipboardManager call each; `WindowLookConfig.shadowSoft` aliases `_shadowMatched`. ~12 lines.
**Fix:** use the readers' values; the card calls ClipboardManager; one name for the shadow match. Recorded.

### 6. (minor) Stale docs and comments
- docs/dev/compositor/README.md › Hiding: "the `Hyprland` section needs `configModes`": there is no Hyprland section any more; it's `Compositor` (and `WindowBehaviour`, `Session` also need managed mode).
- README.md and contract.md name only `HyprlandManager`, `SwayManager` as backends in their intros/Files; NiriManager missing from README's Files.
- config-modes.md › Who does what: the RPC list leaves out `compositor.layerRules` and `compositor.bindActions`.
- `CompositorStatusCard.qml:79` cites `CompositorConfigManager._leave`, which is gone (the daemon's `manager.leave`).
- `WindowLookConfig.qml:15` "so a reload that leaves it unchanged doesn't apply it again": the shell applies nothing (goes with finding 2).
- `ScreenEdgeManager.floatGaps` gates on `CompositorManager.backend` rather than a facade member (seam; harmless).
**Fix:** reword when the next change touches these files.

## Contract
Holds: detection with AXIOM_COMPOSITOR / `none`; only the picked backend is created; facade defaults stand for unsupported; `supports` drops AXIOM_COMPOSITOR_OFF keys and treats absent as false; every facade call into a backend member is either present in all three or gated (overview → niri; focusOutput/moveWindowToOutput/blockSize → dynamicWorkspaces; withOutputDetails/applyOutputs → monitors; withBinds → bindMerge; captureKeys → keyCapture; cursor → cursorPos/Warp); optional members (ready, displayName, unsupportedHint, builtInBinds, layerApplied, setLiveLook, fx, withSetupCheck) are probed with `?.`; signals re-emitted; `x-showIf` `/$supports`/`/$compositor` via SettingsManager.configValueAt and SchemaLayout.compositorAllows; Compositor/WindowBehaviour/Session sections need configModes; CompositorConfigManager sends facts only while live (enabled = configModes && !greeter), dedups by text, resends after a daemon reconnect; the daemon's `live()` needs facts naming its kind; layer order from LayerStack only (LayerManager orderOf, sequence/remap without layerOrder, layerRestack counts a layer move as a new map); FocusGrab native/fallback (100 ms focus loss, backdrop click → clickedOutside then cleared, exclusive only for the newest and not under a modal); LayerOrigin settled after 400 ms; fullscreen consumers hide or move to Overlay, none maps a Top window for it. No dead public member in CompositorManager, CompositorConfigManager, LayerManager, LayerStack, FocusGrab, LayerOrigin, CursorThemeManager (WindowBehaviourConfig is already filed).

## Coverage
Read deeply: services/compositor/CompositorManager.qml, CompositorConfigManager.qml, LayerManager.qml, FocusGrab.qml, components/methods/LayerStack.qml, config/WindowLookConfig.qml, CompositorConfig.qml, WindowBehaviourConfig.qml, components/hosts/popout/LayerOrigin.qml, services/ui/CursorThemeManager.qml, components/views/Settings/TranslucencyStatus.qml, backend/internal/daemon/compositor.go, cursor.go, manager.go (New, Run, live, SetFacts, ConfigChanged, push, status, applyProfile). · Outlined: CompositorStatusCard.qml (first 125 lines), SettingsManager.configValueAt, SchemaLayout.compositorAllows/categories, CompositorKind.pick, IntegrationHookupManager.apply, compositorsocket.go (output and greeter handlers), outputs.go, the three backends (member presence and their supports lists only). · Skipped: HyprlandManager/SwayManager/NiriManager internals, SwayState/NiriState/HyprState, LayerArrange internals (fixture-tested), the rest of manager/ (writers, takeover, runtime: the hyprland/sway/niri and compositor-parity systems), Go tests. No nested compositor was needed: every finding is settled by the code.

## History
- 2026-10-30 full: 5 findings (3 Major, 2 Cleanups) + minor docs; recorded in issues.md (via the row 19 audit batch).
