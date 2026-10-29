# The compositor (detection, the facade, gating)

> **Files:** `services/compositor/CompositorManager.qml`, `services/compositor/HyprlandManager.qml`, `services/compositor/SwayManager.qml`, `services/compositor/FocusGrab.qml`, `components/methods/HyprState.qml`, `components/methods/SchemaLayout.qml`, `services/ui/SettingsManager.qml`
> **Config:** `WindowLook.*`, `Workspaces.*`
> **Related:** [Backend contract](contract.md), [Sway backend](sway-backend.md), [Layer arrangement](layer-arrangement.md), [Hyprland IPC](../hyprland/ipc.md), [Workspaces](../hyprland/workspaces.md), [Schema annotations](../core/schema-annotations.md)

How axiom reaches the compositor it runs under. Read this before anything that reads windows, outputs or workspaces, switches workspace, focuses a window, or does something only one compositor can.

### Detection
- `CompositorManager.kind` is `"hyprland"`, `"sway"`, `"niri"` or `""` (unknown), from `HYPRLAND_INSTANCE_SIGNATURE` / `SWAYSOCK` / `NIRI_SOCKET`. With more than one set (one exported into the systemd user environment by an earlier session reaches the next compositor), the one whose process still runs wins (`methods/CompositorKind`).
- `AXIOM_COMPOSITOR` overrides it for testing (`none` gives `""`).
- `CompositorManager.backend` is that compositor's backend singleton (`HyprlandManager`, `SwayManager`, `NiriManager`), or null. Only the one picked is created.

### The facade
- **Everything outside the backends goes through `CompositorManager`**: the window, output and workspace lists, focus, workspace switching, the keyboard layout, the cursor, the gaps, the blur, logging out. `check_structure.py` refuses `HyprlandManager.` anywhere else, and `SwayManager.`, `SwayIpcManager.`, `swaymsg` and `Quickshell.I3` outside the `Sway*` services, and `NiriManager.`, `NIRI_SOCKET` and a `niri` process outside the `Niri*` services. A backend's text and state helpers (`HyprState`, `SwayState`, `NiriState`) are refused outside its own services and helpers too.
- The state comes in [neutral shapes](contract.md#shapes): plain snapshots rebuilt on events, the same from every backend. Never hand a compositor's own objects (`lastIpcObject`, `HyprlandMonitor`) past the backend.
- Logic that doesn't depend on the compositor lives in `CompositorManager`, so each backend only has primitives:
  - the workspace layout: `goToWorkspace`, `stepWorkspace`, `nthWorkspace`, `workspaceBase`, `workspaceIds`, `stepStrip`
  - the remap on a layout change (`WorkspaceGeometry.remapWorkspaces`)
  - the `workspaces` IPC target
  - `focusWindow` (switching workspace first), `hasFullscreen`, `stripWindows`, `stripDirection` ("" without `supports.strips`, whatever the config lists), `withHoveredScreen`.
- With no backend everything is empty and does nothing, so an unknown compositor still gets the bar, launcher and notifications. The facade's defaults are what "unsupported" looks like.

### Capabilities
- `CompositorManager.supports` maps each capability to true or false. The keys are listed in [contract.md › Capabilities](contract.md#capabilities). A backend lists what it does; anything it doesn't list is false.
- `AXIOM_COMPOSITOR_OFF=focusGrab,blur` turns capabilities off, so a fallback can be tried on a compositor that has the real thing.
- **Gate a compositor-specific feature on a capability, not on `kind`.** Only code that is Hyprland's by nature checks `kind === "hyprland"` (the greeter's Hyprland branch).

### Hyprland-only features
- None talks to `HyprlandManager` directly any more: the Keybinds and Monitors pages go through `CompositorManager` (`withBinds`, `captureKeys`, `withOutputDetails`, `applyOutputs`), and the greeter's Hyprland is set up by axiom (`CompositorManager.setUpGreeter` → `greeter.compositor`).
- Nothing may write Hyprland's config unless `supports.configModes` is set: under another compositor, managed mode would otherwise rewrite `~/.config/hypr/hyprland.lua`.

### Hiding what a compositor can't do
- **Settings.** An `x-showIf` key starting with `/$` reads the compositor, not the config ([schema-annotations](../core/schema-annotations.md)):
  - `"/$supports.<capability>": true`
  - `"/$compositor": "sway"`
- A section whose own `x-showIf` fails drops out of its category (`SchemaLayout.categories`): the `Hyprland` section needs `configModes`. The `WindowLook` fields each need their part (`windowBorders`, `windowShape`, `windowGaps`, `windowBlur`, `windowOpacity`).
- **Pages.** A view type's `x-needs` names the capability it needs (Keybinds: `keybinds`, Monitors: `monitors`). `OverlayPages` leaves the page out, and the launcher's `/keybinds` and `/monitors` aren't listed.
- **Onboarding.** The Hyprland and Monitors pages need `configModes`.

### Focus grab
- Surfaces that close on an outside click use `FocusGrab` (`windows`, `active`, `cleared`), never `HyprlandGrab`.
  - With `supports.focusGrab` it loads Hyprland's grab.
  - Otherwise it clears once keyboard focus (each window's content `Window.active`) has left every one of its windows for 100 ms, or a click lands outside them. While such a grab is active:
    - `FocusGrab.exclusive` is true on the newest such grab (`BackdropManager.newestCatcher`), and its surface asks for `WlrKeyboardFocus.Exclusive` instead of `OnDemand` (an on-demand layer surface gets the keyboard only once clicked, where no grab hands it over). Only the newest, and not while `SurfaceManager.modalShown` (the modal asks for it too): of two exclusive surfaces on one layer niri keeps the older, so a popout with a text field over the overlay would never get the keyboard. Grabs stay in that order while a modal is up, so the newest one gets the keyboard back after it;
    - every screen's backdrop window (`surfaces/backdrop/ScreenBackdrop`) covers its screen, transparent, under the grabbing surface, and a press on it clears the grab (`BackdropManager.catching`, `clickedOutside`). Bars and other surfaces above it take their own clicks.
  - `cleared` is also keyboard focus leaving (a prompt closing gives it back to an app), so a surface that must close only on a real click (the overlay) uses `FocusGrab.clickedOutside`, sent for a press on the backdrop just before `cleared`.

### The window look
- `WindowLook` is compositor-neutral config, edited under Settings › Compositor.
- It is part of the layer `CompositorConfigManager` hands the backend's config writer ([config modes](config-modes.md), [window-look](window-look.md)).
- A backend without config modes gets no window look.

### Adding a backend
- [Recipe: compositor backend](../../recipes/compositor-backend.md). Sway's is [sway-backend](sway-backend.md).
