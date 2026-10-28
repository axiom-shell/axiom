# Profile switching runs in the shell on sway and niri

> **Issue:** [Profile switching runs in the shell on sway and niri](../issues.md#profile-switching-runs-in-the-shell-on-sway-and-niri) (folds in [The monitor profile picker exists twice](../issues.md#the-monitor-profile-picker-exists-twice))
> **Status:** proposed

Decided (maintainer, 2026-10-28), verbatim: "go owns profile switching for every compositor". The options below are only about how.

### Problem
The rule "which saved profile fits what's connected" lives in two places, and on sway and niri the shell does the switching:
- **The picker, twice.** `MonitorLayout.matchProfile` / `savedRules` (`components/methods/MonitorLayout.qml`, about 35 lines plus `tst_MonitorLayout` cases) and `applyMonitors`, the Lua `render.MonitorsLua` sends Hyprland (`backend/internal/compositor/render/hyprlua.go`, about 60 lines). Nothing keeps them in step except `TestMonitorsLuaPicks` and comments that name each other.
- **The session switches in QML.** Without `supports.outputProfiles`, `MonitorManager` waits for `outputsHotplugged`, reads the outputs again (`refresh`), then `_applySavedProfile` → `CompositorManager.applyOutputs`. Getting there takes `_applyProfilePending`, a `configReloaded` branch keyed on `CompositorConfigManager.status`, a `pending` guard and `useWholeScale`'s own pending flag. `CompositorConfigManager._outputRules` runs the same match again and sends the result to Go as the `outputRules` fact (`manager/inputs.go` `Facts.OutputRules`). The sway and niri writers write that fact as `output` lines and nodes (`swayWriter.outputLines`, `niriWriter.outputs`). Go already knows the profiles (`buildInputs` reads `Monitors.items`); the only thing it's missing is what's connected.
- **The greeter matches only once.** `GreetdManager._applyCompositor` applies `savedRules` for the outputs it sees at start. `applyGreeter`'s sway branch (`daemon/compositorsocket.go`) sends only input. A monitor plugged in while the greeter is up is never matched on sway, where Hyprland's Lua picks again on every hotplug.
- **The Monitors page** runs `matchProfile` over its draft for `liveProfile` (the "(connected)" label, `selectedIsLive`) and `_detect`.

This affects every sway and niri user who keeps more than one profile. The shell has to be running and caught up for a hotplug to switch, and every hotplug does three reads: the backend's, `MonitorManager.refresh` and the writer's.

Go already has most of the pieces. `wayland/outputs.Tracker` follows hotplugs over the daemon's own Wayland connection on every compositor (`OnChange`). It lists only enabled outputs, though, and with wl_output's descriptions rather than the shell's ("make model serial"). So the switcher still needs the compositor's own list: sway's `GET_OUTPUTS`, niri's `Outputs`. `applyOutputs` (sway commands, niri `Output` requests) is already Go. The greeter only ever runs on sway or Hyprland (`greeter-session.sh`), so the greeter only needs sway handled.

### Options
#### A. Go switches on sway and niri; Hyprland keeps its Lua, checked against Go's picker
- **Picker:** one Go picker (`MatchProfile`, `SavedRules`). The Lua `applyMonitors` stays, because Hyprland's files have to switch without axiom running (managed or included mode, a session where the daemon is down). `TestMonitorsLuaPicks` runs the Go picker's case table through the Lua, so both always give the same answer.
- **Session:** on sway and niri, the session `Manager` reacts to `Tracker.OnChange` (debounced). It reads the compositor's outputs, picks, applies them live and computes `outputRules` in `buildInputs` itself, so included and managed files follow.
- **Greeter:** on sway, the greeter's axiom does the same for as long as the greeter runs.
- **Monitors page:** reads the profile the daemon matched from `compositor.state` on every compositor.
- **Size:** QML loses about 90 lines (`_applySavedProfile` and its flags, `_outputRules`, the greeter branch, `matchProfile`/`savedRules`). Go gains about 200: the output reads, the picker, the watch.
- **Leaves:** the Lua picker as a second implementation, but one that's tested against Go rather than kept in step by hand.

#### B. Go switches on every compositor, Hyprland included
- **Lua:** shrinks to the `hl.monitor` calls of the profile matched now (`render.MonitorCalls`). `applyMonitors`, `AXIOM_MONITOR_SUBS` and the `outputProfiles` capability (with every branch on it) go.
- **Size:** deletes the most, about 60 more lines than A. Leaves no second picker at all.
- **Costs:** Hyprland's managed and included configs stop switching when axiom isn't running. Every hotplug waits for a daemon round trip, during which Hyprland lays the new monitor out its own way first, so a visible modeset and then a second one. Every hotplug also rewrites Hyprland's module, so that a reload keeps the profile.

#### C. The shell keeps the trigger; Go picks and applies
- **What changes:** a new method `outputs.applySaved`, sent on each `outputsHotplugged` by the session and the greeter alike (the greeter's qs sees hotplugs too, which closes its gap). Go reads the outputs, picks, applies, and fills `outputRules` from its last read.
- **Size:** the least Go, with no watcher.
- **Costs:** a hotplug during a qs reload or crash is missed, and each hotplug still makes two reads. The reactor stays in QML, so the switch still depends on the shell being up, which is the dependency the decision is meant to remove. A's watch is about 20 lines over a Tracker the daemon already runs, so C saves little.

### Recommendation
**A.** It removes every QML copy of the picker and the switching, makes the greeter follow hotplugs, and leaves one Go picker that the Hyprland Lua is tested against. It keeps Hyprland's ability to switch without axiom, which B gives up only to save a few dozen lines. C is smaller only until a hotplug lands while qs is reloading. If the maintainer wants Lua out of the picture entirely, B can follow A later as one item: everything A builds stays.

### Items
1. **One Go picker.** `render.MatchProfile(profiles, outputs)` and `render.SavedRules(profiles, outputs)`, the rule from `MonitorLayout.matchProfile` with its cases ported to a Go table test. `TestMonitorsLuaPicks` runs that same table through the generated Lua, and the comments name `MatchProfile` as the source. Nothing in QML changes yet.
2. **Go reads the outputs on sway and niri.** `ipc.Sway.Outputs` (`GET_OUTPUTS`) and a niri `Outputs` read, both returning the neutral `{name, description, disabled}`, with descriptions built the way `SwayState` and `NiriState` build them ("make model serial", "Unknown" parts dropped). Fixture tests from recorded replies.
3. **The session switches in Go.** On sway and niri, `manager.Manager` watches the daemon's `Tracker.OnChange` (debounced) and re-reads the outputs. It applies `SavedRules` live (move `applyOutputs` to where `Manager` can call it), and `buildInputs` fills `outputRules` from that read, so included and managed files are rewritten. In detached mode it applies again after a reload, which replaces `MonitorManager`'s `configReloaded` branch.
   - **Deletes:** `Facts.OutputRules`, `CompositorConfigManager._outputRules`, `MonitorManager._applySavedProfile`, `_applyProfilePending`, its reload branch and `useWholeScale`'s apply flag.
   - **Trial Apply:** a hotplug during a trial Apply closes the Keep prompt without reverting, because the daemon has already applied the saved profile for the new set. This is the smallest handling of a rare path.
   - Docs: `compositor/sway-backend.md`, `niri-backend.md`, `hyprland/monitors.md`.
4. **The greeter switches in Go.** On sway, `greeter.compositor` also starts a watch for the greeter's lifetime. The greeter daemon binds a `Tracker` (`client.Run`), or else subscribes to sway's `output` events. Each change applies the bundle's `SavedRules`. Deletes `GreetdManager._applyCompositor`'s `savedRules` branch. Hyprland's path is unchanged. Docs: `features/greeter-runtime.md`.
5. **The Monitors page asks the daemon** (folds in "The monitor profile picker exists twice"). `compositor.state` carries the matched saved profile's name, or `""` for none, on every compositor; on Hyprland it's read from `monitors all` on the same `Tracker.OnChange`. `MonitorManager.liveProfile` and `_detect` find that name in the draft (names are unique, and the draft equals the saved config whenever `_detect` runs).
   - **Deletes:** `MonitorLayout.matchProfile` and `savedRules` with their `tst_MonitorLayout` cases. `supports.outputProfiles` too, if nothing reads it any more.
   - Removes both issues.md entries.
