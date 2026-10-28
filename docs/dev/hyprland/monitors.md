# Monitors (profiles and the Monitors page)

> **Files:** `services/compositor/MonitorManager.qml`, `config/MonitorsConfig.qml`, `components/views/Monitors/Monitors.qml`, `components/views/Monitors/` (`MonitorCanvas`, `MonitorInspector`), `components/methods/MonitorLayout.qml`, `backend/internal/compositor/render/hyprlua.go`, `shell/MonitorPrompt.qml`, `components/surfaces/monitors/MonitorPromptWindow.qml`
> **Config:** `Monitors.items`, `General.primaryMonitor`
> **Related:** [Config modes](config-modes.md), [Onboarding](../features/onboarding.md) (`useWholeScale`), [Shell targeting](../core/shell-manager-targeting.md)

Monitor layouts saved per set of connected monitors, edited on the Monitors page and applied on hotplug: by Hyprland itself (its Lua layer, `outputProfiles`), else by the daemon on sway and niri ([sway](../compositor/sway-backend.md)). The page reaches the compositor only through `CompositorManager` (`withOutputDetails`, `applyOutputs`; [contract](../compositor/contract.md)).

### Live outputs
- `outputs` is every output in detail, disabled ones included (`CompositorManager.withOutputDetails`).
- It is read at startup and on `monitoradded`/`monitorremoved`/`configreloaded`. It is never polled.

### Profiles
- `Monitors.items` (`x-settings: false`; `Hyprland.monitors.profiles` before config version 61) is a list of `{ name, outputs: [MonitorRule] }`: one layout per set of monitors.
- Each rule's `output` is `desc:<description>`, so the rule follows the monitor across ports. When two monitors share a description it is the connector name instead (`MonitorLayout.outputId`).
- Each rule also holds:
  - mode, position, scale
  - transform: 0–7, quarter turns, +4 for flipped
  - `disabled`
  - `mirror` (another rule's `output`)
  - `vrr`, `bitdepth`, `cm`
  - `sdrBrightness`/`sdrSaturation`.
- The inspector shows `mirror` only with `supports.monitorMirror`, and the color mode and SDR fields only with `supports.monitorColor`.

### Editing
- The page edits a `ConfigDraft`.
- `MonitorCanvas` and `MonitorInspector` are streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)).
- **Detection.** Opening the page detects the current setup (`_detect`):
  - when no profile matches, a new profile is made from the live state
  - otherwise the matching profile gains any output it doesn't list.
- While the page is open, a hotplug re-detects unless the draft has been edited.
- **Snapping.** Tiles snap (`MonitorLayout.snap`): edge to edge, or aligned starts/ends/centres, within 14 screen px. Outside that range they drop anywhere, so offsets stay possible.
- The view holds still during a drag.
- `General.primaryMonitor` is set from the inspector at once, without waiting for Save.
- For `useWholeScale`, see [Onboarding](../features/onboarding.md).

### Issues
- Apply is blocked by:
  - overlapping monitors
  - every monitor being off.
- Warnings:
  - islands (monitors not touching the rest)
  - scales Hyprland will round
  - in managed mode, `user/*.lua` files that call `hl.monitor` (`CompositorConfigManager.monitorConflicts`). Those rules load later and win.

### Apply, Keep, Revert
1. **Apply** has axiom eval the selected profile's `hl.monitor` calls (`CompositorManager.applyOutputs` → `outputs.apply`, `render.MonitorCalls`), after taking a snapshot of the old state.
2. It shows `shell/MonitorPrompt` (`surfaces/monitors/MonitorPromptWindow`).
   - It appears on every screen, outside the overlay, because the overlay's screen may change.
   - It sits on the Overlay layer as `axiom-monitor-prompt`; its layer rule stacks it over the overlay.
   - It is registered in `SurfaceManager.modalWindows` while shown, so the overlay's focus grab lets clicks through to it.
3. `keep()` saves the draft. `revert()`, or 15 s without an answer, evals the snapshot back.
- A profile for monitors that aren't connected only saves.

### How profiles reach Hyprland
- `render.MonitorsLua` produces the same Lua in every mode (and for the greeter's Hyprland, `greeter.compositor`): `AXIOM_MONITOR_PROFILES` plus `axiom_apply_monitors()`.
- `axiom_apply_monitors()` picks a profile the way `MonitorLayout.matchProfile` and Go's `render.MatchProfile` (not called yet) do:
  - an exact set of monitors, where a disabled rule's output may be missing (`hl.get_monitors()` doesn't list it)
  - else the profile that turns the most monitors on
  - before any monitor is reported, the first profile.
- It resets outputs that only other profiles mention to Hyprland's defaults, and resolves `mirror` to a connector.
- It runs again on `monitor.added`/`removed`. The handlers are kept in `AXIOM_MONITOR_SUBS` and removed before re-subscribing.
- **Detached:** it is part of the runtime eval, but only when the profiles changed or a reload dropped them (the Hyprland writer's `monitorsApplied`), since re-applying can flicker a modeset.
- **Included / managed:** `M.monitors()` runs from `setup()`, so profiles follow hotplugs without qs.

### IPC and launcher
- IPC `monitors`: `open`, `keep`, `revert`, `identify`.
- Launcher: `/monitors`.

### Testing
- Never Keep a layout while testing. (Rule: AGENTS.md › Never, while testing.)
- Test the profile picker through `render`'s `TestMonitorsLuaPicks` (Go, the Lua run by gopher-lua).
- Use only harmless evals: re-applying the current settings, or moving a lone monitor's origin and back.
