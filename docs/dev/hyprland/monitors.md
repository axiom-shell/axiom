# Monitors (profiles and the Monitors page)

> **Files:** `services/compositor/MonitorManager.qml`, `config/MonitorsConfig.qml`, `components/views/Monitors/Monitors.qml`, `components/views/Monitors/` (`MonitorCanvas`, `MonitorInspector`), `components/methods/MonitorLayout.qml`, `backend/internal/compositor/render/hyprlua.go`, `backend/internal/compositor/manager/outputs.go`, `backend/internal/compositor/render/profiles.go`, `shell/MonitorPrompt.qml`, `components/surfaces/monitors/MonitorPromptWindow.qml`
> **Config:** `Monitors.items`, `General.primaryMonitor`
> **Related:** [Config modes](config-modes.md), [Onboarding](../features/onboarding.md) (`useWholeScale`), [Shell targeting](../core/shell-manager-targeting.md)

Monitor layouts saved per set of connected monitors, edited on the Monitors page and applied on hotplug by the daemon, on every compositor ([sway](../compositor/sway-backend.md)). The page reaches the compositor only through `CompositorManager` (`withOutputDetails`, `applyOutputs`; [contract](../compositor/contract.md)).

### Live outputs
- `outputs` is every output in detail, disabled ones included (`CompositorManager.withOutputDetails`).
- It is read at startup and on `monitoradded`/`monitorremoved`/`configreloaded`. It is never polled.

### Profiles
- `Monitors.items` (`x-settings: false`; `Hyprland.monitors.profiles` before config version 61) is a list of `{ name, outputs: [MonitorRule] }`: one layout per set of monitors.
- Each rule's `output` is `desc:<description>`, so the rule follows the monitor across ports. When two monitors share a description it is the connector name instead (`MonitorLayout.outputId`). A description matches with niri's spelling of a make it has no name for (`PNP(AOC)`) taken as the bare code Hyprland and sway give (`MonitorLayout.matches`, and the daemon's `render.MatchProfile`), so a profile saved under one compositor is picked under another.
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
- **Detection.** Opening the page detects the current setup (`_detect`). The match is the daemon's: `compositor.state`'s `monitorProfile` (`CompositorConfigManager.monitorProfile`) names the saved profile it picked on its last read of the outputs (`render.MatchProfile`), and the page finds that name in the draft. The profile it finds or makes is `liveProfile` (the "(connected)" label, and what Apply tries live with a Keep prompt), followed through renames:
  - when it named none, a new profile is made from the live state
  - otherwise the named profile gains any output it doesn't list.
- While the page is open, a hotplug re-detects unless the draft has other edits than detection's (`_untouched`), and so does a new name from the daemon (its read can land after the page's) unless a detect is still waiting for the page's read. A draft with the user's edits, or a closed page, only follows the new name.
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
- The daemon switches, as on sway and niri: `manager.Manager`'s profile switch (`profileSwitch`, `manager/outputs.go`) hears each change of its outputs (`outputs.Tracker`), reads `monitors all` (`ipc.Hypr.Outputs`) at once (no settling delay, unlike sway and niri), picks with `render.MatchProfile` and evals the rules as `hl.monitor` calls (`render.MonitorCalls`; once per set of outputs and rules), in every mode.
- **One modeset where the profiles agree.** Hyprland lays a monitor plugged in out itself before the daemon's switch lands. So the rules are `render.HyprlandRules`: the matched profile's (`render.SavedRules`), plus, for each monitor a profile names that the matched profile leaves out, connected or not, the rule every profile naming it agrees on (an external monitor always set the same way). Hyprland lays such a monitor out by that rule, and the switch then changes nothing: a connected monitor the new match leaves out keeps the agreed rule rather than falling back to Hyprland's default, so a plug doesn't modeset it twice. A monitor the profiles set differently gets no rule: Hyprland's own layout, then the switch's, two modesets (the cost the decision accepts). So do an unplugged monitor named by description and the connector a profile last saw it on (its rule's `label`), named by connector in another profile, where their rules disagree: they may be one monitor, and Hyprland would apply whichever came later.
  - Writing a disabled rule for every monitor no profile names (so nothing new lights before the daemon picks) was weighed and not taken: `render.MatchProfile` counts only enabled outputs, so a monitor held dark would never pick the profile naming it, and one no profile names, alone at login, would leave Hyprland with no monitor on.
- **Included / managed:** `M.monitors()` in the module (or the managed config) holds only those calls (`buildInputs`' `monitorCalls`, which an output only turned off leaves alone), rewritten on each switch, so a Hyprland reload keeps the profile. Until the daemon has read the outputs, the file keeps the calls it has (`render.HyprFileMonitorCalls`).
- **Detached:** nothing is written. The switch still runs on every hotplug, and its eval is the only copy: Hyprland keeps the evaluated rules, the agreed ones for monitors the match leaves out too, until a reload drops them, after which the switch evaluates them again. So detached mode modesets once where the profiles agree as well.
- **Included:** the user's own `hl.monitor` lines after the module win over its rules (their doing, as decided).
- Without axiom running, Hyprland keeps the layout last written and switches no more (decided: the user's doing).
- **Greeter:** the greeter's axiom runs the same watch for the greeter's lifetime (`greeterProfiles`).

### IPC and launcher
- IPC `monitors`: `open`, `keep`, `revert`, `identify`.
- Launcher: `/monitors`.

### Testing
- Never Keep a layout while testing. (Rule: AGENTS.md › Never, while testing.)
- Test the profile picker through `render`'s `TestProfiles` (and Hyprland's rules, `TestHyprlandRules`) and the switch through `manager`'s `TestHotplugsApplyTheSavedProfile`.
- Use only harmless evals: re-applying the current settings, or moving a lone monitor's origin and back.
