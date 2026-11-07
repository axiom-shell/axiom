# Monitors (profiles and the Monitors page)

> **Files:** `qml/services/compositor/MonitorManager.qml`, `qml/config/MonitorsConfig.qml`, `qml/components/views/Monitors/Monitors.qml`, `qml/components/views/Monitors/` (`MonitorCanvas`, `MonitorInspector`), `qml/components/methods/MonitorLayout.qml`, `backend/internal/compositor/render/hyprlua.go`, `backend/internal/compositor/manager/outputs.go`, `backend/internal/compositor/render/profiles.go`, `qml/shell/MonitorPrompt.qml`, `qml/components/surfaces/monitors/MonitorPromptWindow.qml`
> **Config:** `Monitors.items`, `Monitors.notify`, `General.primaryMonitor`
> **Related:** [Config modes](config-modes.md), [Onboarding](../features/onboarding.md) (`useWholeScale`), [Shell targeting](../core/shell-manager-targeting.md)

Monitor layouts saved per set of connected monitors, edited on the Monitors page and applied on hotplug by the daemon, on every compositor ([sway](../compositor/sway-backend.md)). The page reaches the compositor only through `CompositorManager` (`withOutputDetails`, `applyOutputs`; [contract](../compositor/contract.md)).

### Live outputs
- `outputs` is every output in detail, disabled ones included (`CompositorManager.withOutputDetails`).
- It is read at startup and on `monitoradded`/`monitorremoved`/`configreloaded`. It is never polled.

### Profiles
- `Monitors.items` (`x-settings: false`; `Hyprland.monitors.profiles` before config version 61) is a list of `{ name, outputs: [MonitorRule] }`: one layout per set of monitors.
- Each rule's `output` is `desc:<description>`, so the rule follows the monitor across ports. When two monitors share a description it is the connector name instead (`MonitorLayout.outputId`). A description matches with niri's spelling of a make it has no name for (`PNP(AOC)`) taken as the bare code Hyprland and sway give (`MonitorLayout.matches`, and the daemon's `render.MatchProfile`), so a profile saved under one compositor is picked under another. The daemon writes and applies such a rule in the running compositor's spelling (`render.SavedRules`; the Monitors page's Apply through `render.Spelled` in `Outputs.Apply`): the connected output's description, or for a monitor not connected (Hyprland's rules only) the bare code. niri and sway are told the connector instead (`connectorFor`, `render.SwayConnectorRules`).
- Each rule also holds:
  - mode, position, scale
  - transform: 0–7, quarter turns, +4 for flipped
  - `disabled`
  - `mirror` (another rule's `output`)
  - `vrr`, `bitdepth`, `cm`
  - `sdrBrightness`/`sdrSaturation`.
- The inspector shows `mirror` only with `supports.monitorMirror` or when the rule has one (a profile saved under another compositor: it can always be turned off), and the color mode and SDR fields only with `supports.monitorColor`.

### Editing
- The page edits a `ConfigDraft`.
- `MonitorCanvas` and `MonitorInspector` are streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)).
- **Detection.** Opening the page detects the current setup (`_detect`). The match is the daemon's: `compositor.state`'s `monitorProfile` (`CompositorConfigManager.monitorProfile`) names the saved profile it picked on its last read of the outputs (`render.MatchProfile`), and the page finds that name in the draft. The profile it finds or makes is `liveProfile` (the "(connected)" label, and what Apply tries live with a Keep prompt), followed through renames:
  - when it named none, a new profile is made from the live state (`_newProfile`, as **New layout** makes one: "Layout N", with an id made from that name by `Utils.newId`, which the schema requires)
  - otherwise the named profile gains any output it doesn't list.
- While the page is open, a hotplug re-detects unless the draft has other edits than detection's (`_untouched`), and so does a new name from the daemon (its read can land after the page's) unless a detect is still waiting for the page's read. A draft with the user's edits, or a closed page, only follows the new name.
- **Hotplugs said:** `MonitorManager` compares each read with the last (by connector, disabled ones included; never the first read) and says a monitor connected or removed through `NotificationManager.announce("monitor", Monitors.notify, …)`: an OSD's `monitor` card (`lastEvent`) or, with `Monitors.notify` (off by default), a notification naming it and its resolution ([OSD](../features/osd.md) › Where events go). Only with `supports.monitors`, which the reads need.
- **Snapping.** Tiles snap (`MonitorLayout.snap`): edge to edge, or aligned starts/ends/centres, within 14 screen px. Outside that range they drop anywhere, so offsets stay possible.
- The view holds still during a drag.
- `General.primaryMonitor` is set from the inspector at once, without waiting for Save.
- For `useWholeScale`, see [Onboarding](../features/onboarding.md).
- `settingsLinks: false` hides its links into Settings (the inspector's primary monitor, the page's Compositor mode): the onboarder sets it, as following one would open the overlay over it.

### Issues
- Apply is blocked by:
  - overlapping monitors
  - every monitor being off.
- Warnings:
  - islands (monitors not touching the rest)
  - scales Hyprland will round
  - in managed mode, `user/*.lua` files that call `hl.monitor` (`CompositorConfigManager.monitorConflicts`; on niri `user/*.kdl` with an `output` node, on sway `user/*` with an `output` line setting a monitor, its name bare or quoted, or an `output … {` block: each writer's `monitorPattern`). Those rules load later and win.

### Apply, Keep, Revert
1. **Apply** has axiom eval the selected profile's `hl.monitor` calls (`CompositorManager.applyOutputs` → `outputs.apply`, `render.Spelled`, `render.MonitorCalls`), after taking a snapshot of the old state: each output's rule from a `monitors all` read made then (not the page's last read, which a change made outside axiom may have left behind) (`MonitorLayout.ruleFromMonitor`; a mirror from its `mirrorOf`, which Hyprland gives as the mirrored monitor's id), the details, the draft tried and the profile's name.
   - **Every rule names every key but vrr 0** (`render.MonitorSpec`): `disabled = false`, `mirror = "none"`, `transform = 0`, `bitdepth = 8`, `cm = "auto"`, `sdrbrightness = 1`, `sdrsaturation = 1` when the rule has them so. vrr is given only when it isn't 0: a rule's vrr overrides `misc:vrr` (Compositor › Variable refresh rate) for that output (`CMonitorRule::m_vrr` is an optional), so the saved and profile rules leave vrr 0 out. A revert's rules are a picture of the monitors before Apply, so it says vrr 0 too (`applyOutputs(…, revert)`, `outputs.apply`'s `revert`, `render.RevertMonitorCalls`): a trial that turned VRR on ends with it, and the override lasts until the next config reload. An `hl.monitor()` call changes only the keys it is given: Hyprland 0.57.1 (tried on a nested one with headless outputs) kept a mirror, a rotation, the bit depth, the colour, the SDR values and `disabled` from the output's previous rule when a later call left them out, so a revert without them left the mirror on. `mirror = "none"` (or `""`, or a name no output has) ends a mirror; a mirror of an output not connected is sent as `"none"`. A disabled rule is only `{ output, disabled = true }`: the call turning it on again sends every key. A config reload drops the evaluated rules (the file's are read fresh), so the files' full rules change nothing there but keep one spelling (`TestMonitorCallsUndoEverything`, `TestRevertMonitorCallsSayVrr`).
2. It shows `qml/shell/MonitorPrompt` (`surfaces/monitors/MonitorPromptWindow`).
   - It appears on every screen, outside the overlay, because the overlay's screen may change.
   - It sits on the Overlay layer as `axiom-monitor-prompt`; its layer rule stacks it over the overlay.
   - It is registered in `SurfaceManager.modalWindows` while shown, so the overlay's focus grab lets clicks through to it.
3. `keep()` saves the draft. `revert()`, or 15 s without an answer, evals the snapshot back, and puts the profile tried back in the draft as the monitors were (`MonitorLayout.restored`): each connected monitor's rule as saved where the monitors showed the saved rule (so a `preferred` mode, vrr 2 or cm `auto`, which Hyprland reads back otherwise, stay), else as they were read, each rule keeping its own `output`, one path for both (`_runRevert`, which a `keep()` that couldn't save takes too). The draft then shows what's on the monitors, unsaved where the saved profile differs.
- **Apply shows while the draft differs from the saved config or from the monitors as they are** (`MonitorManager.differsFromLive`, `MonitorLayout.differsFromLive`: on or off, the mirror (only with `supports.monitorMirror`: under niri and sway a saved mirror is placed by its position, as applying it does), the position (not a mirror's), scale (one with no whole logical size matches either valid scale around it, as Hyprland rounds it), rotation, a mode that isn't `preferred`; vrr, the bit depth and the colour aren't compared, as Hyprland's read-back isn't what the rule asked), so a layout the compositor didn't take can always be applied again. Discard (back to the saved config) shows only with unsaved edits (`TitledCard.canReset`): a difference from the monitors alone leaves it nothing to drop. It isn't compared while a change settles (the re-read after Apply, a revert or a hotplug).
- The daemon's switch skips a profile it applied last for the same outputs, and `outputs.apply` (Apply, its revert) doesn't reset that: mirroring an output takes its `wl_output` away and back (a hotplug of the same outputs, at once on Hyprland), and the switch applying the saved profile again then undid the trial within a second (tried in a nested Hyprland). A reload resets it, and a kept profile is a config change with new rules, which the switch applies.
- A monitor connected or unplugged meanwhile (the connectors read differ from the last read) ends the trial without reverting: the daemon has applied the saved profile for the new set. A monitor the trial turns off or mirrors is still listed (`outputs` holds disabled ones), so Hyprland's `monitorremoved` for it doesn't end the trial.
- The trial (the snapshot and the draft tried) is a `PersistentProperties` JSON string, so a QML reload keeps the prompt and the way back; its countdown starts over. A crash or restart of qs loses it.
- A profile for monitors that aren't connected only saves.

### How profiles reach Hyprland
- The daemon switches, as on sway and niri: `manager.Manager`'s profile switch (`profileSwitch`, `manager/outputs.go`) hears each change of its outputs (`outputs.Tracker`), reads `monitors all` (`ipc.Hypr.Outputs`) at once (no settling delay, unlike sway and niri), picks with `render.MatchProfile` and evals the rules as `hl.monitor` calls (`render.MonitorCalls`; once per set of outputs and rules, again on the next change after a failed apply), in every mode.
- **One modeset where the profiles agree.** Hyprland lays a monitor plugged in out itself before the daemon's switch lands. So the rules are `render.HyprlandRules`: the matched profile's (`render.SavedRules`), plus, for each monitor a profile names that the matched profile leaves out, connected or not, the rule every profile naming it agrees on (an external monitor always set the same way). Hyprland lays such a monitor out by that rule, and the switch then changes nothing: a connected monitor the new match leaves out keeps the agreed rule rather than falling back to Hyprland's default, so a plug doesn't modeset it twice. A monitor the profiles set differently gets no rule: Hyprland's own layout, then the switch's, two modesets (the cost the decision accepts). So do an unplugged monitor named by description and the connector a profile last saw it on (its rule's `label`), named by connector in another profile, where their rules disagree: they may be one monitor, and Hyprland would apply whichever came later.
  - Writing a disabled rule for every monitor no profile names (so nothing new lights before the daemon picks) was weighed and not taken: `render.MatchProfile` counts only enabled outputs, so a monitor held dark would never pick the profile naming it, and one no profile names, alone at login, would leave Hyprland with no monitor on.
- **Included / managed:** `M.monitors()` in the module (or the managed config) holds only those calls (`buildInputs`' `monitorCalls`, which an output only turned off leaves alone), rewritten on each switch, so a Hyprland reload keeps the profile. A reload after which the file isn't loaded (the include line taken out) evaluates it as in detached mode. Until the daemon has read the outputs, the file keeps the calls it has (`render.HyprFileMonitorCalls`).
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
