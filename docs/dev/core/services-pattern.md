# Services pattern

> **Files:** `services/*/*.qml`, `scripts/quickshell-io-allowlist.json`, `services/core/ConsumerRegistry.qml`, `services/core/CommandManager.qml`, `services/system/SystemManager.qml`, `services/system/UpdatesManager.qml`, `config/Paths.qml`, `shell.qml`
> **Config:** none of its own
> **Related:** [Config manager](config-manager.md), [Config readers](config-readers.md), [Editors pattern](editors-pattern.md), [Shell manager and screen targeting](shell-manager-targeting.md)

How `services/` is built: one singleton per domain, owning state and side effects, and the shared acquire/release pattern for anything polled. Read this before adding or changing a service.

### Shape
- Every service is `pragma Singleton QtObject`: one global instance per name, imported by its group's module: `qs.services.core`, `.compositor`, `.session`, `.system`, `.ui` or `.apps` (the folders, `services/AGENTS.md`). The non-singleton parts beside them (`ConfigDraft`, `ConsumerRegistry`, `IpcTarget`, …) are listed in `services/AGENTS.md` › Folders.
- (Rule: AGENTS.md › Services, for naming, `_services` and singleton shadowing.)
- A service with an IPC target that nothing else references is created from `shell.qml`'s `_services` (e.g. BatteryManager, CompositorConfigManager).

### Polled data: acquire / release
(Rule: AGENTS.md › Services, "Anything polled".)
- **SystemManager**: CPU/memory/temp/GPU/disk stats, sampled by axiom (the `system` topic, `backend/internal/sysmon`, at the shortest interval asked; the setting's schema minimum is the only floor).
  - Reference-counted through a `ConsumerRegistry` (shared with UpdatesManager; identical re-registrations are no-ops).
  - Consumers call `acquire(owner, {interval, metrics, diskPaths})` / `release(owner)`.
  - Go reads only the union of requested metrics from /proc and /sys (no process but `nvidia-smi`, only without an AMD card); disk usage is re-read once a minute. Each push is one sample, the metrics asked for and an `at` time, so every sample is pushed.
  - Stops entirely with no consumers.
  - With `history: true` it keeps 60-sample ring buffers in QML, one entry per push (see [Writing modules](../overlay/writing-modules.md)).
- **UpdatesManager**: pending package (and, on Arch, AUR) updates shared by every Updates widget and module (same acquire/release pattern; the AUR helper is the `Updates` section's, `UpdatesConfig.activeAurHelper`).
  - Checked by axiom (the `updates` topic, `backend/internal/updates`, at the shortest interval asked): the request carries the distribution's `Packages.updates` entry (`checkupdates` on Arch, `dnf check-update` on Fedora), which Go runs and parses; on one with none, `supported` is false and nothing is subscribed (the widget hides, the card says so).
  - Every check ends in a state, a failed one too (its `error`, the last packages kept), so `checking` (set on subscribing and `refresh()`) always clears. The hub runs one check at a time: concurrent `checkupdates` runs share its temp db and fail.
  - `upgrade(command, terminal)` runs the upgrade in a terminal (`CommandManager.run`, one at a time) and checks again when it closes.
- **Other polled services:**
  - `CalendarManager`: `acquire(owner)` with no request; its interval is the Calendar section's. See [Calendar](../features/calendar.md).
  - `WeatherManager`: takes no request (its settings are global); fetched by axiom (the `weather` topic, `backend/internal/weather`: Open-Meteo, the place geocoded or from the IP in Go), the state carrying the settings it answers so a stale one isn't shown.
  - `ClaudeUsageManager`: `{ accounts, interval }`, both from the `ClaudeUsage` section; fetched by axiom (the `claudeUsage` topic, `backend/internal/claudeusage`: the token is read in Go and never reaches the shell; each account at most once per interval, across restarts, with backoff).
  - `StopwatchManager`: `acquire(owner, interval)`, `now` ticking at the shortest interval asked while the timer or stopwatch runs; the timer's end runs with no consumers.
  - `PomodoroManager`: `acquire(owner)` with no request, for its once-a-second `now`; the phase's end runs with no consumers (created from `_services`). Both keep their ticker, alarm, saved state and notification in a `DeadlineTicker` part. See [Todo and pomodoro](../features/todo-pomodoro.md).
  - `TailscaleManager`: `available`, `backendState`/`connected`, `tailnetName`, `ip`, polled by axiom (the `tailscale` topic, at `TailscaleConfig.interval`: `backend/internal/tailscale`).
  - `CommandManager`: `acquire(owner, { command, interval, mode, format })`, `outputs[command]` (and `values[command]` with `format: "json"`), shared by identical commands (e.g. a Button's label); watched by axiom (below).
- **Polled by the daemon:** a service whose side effect moved to axiom keeps the same `acquire` / `release` and its `ConsumerRegistry`, but instead of a Timer it hands the merged request to `BackendManager.acquire(topic, request)` while `_registry.active` (and `release(topic)` once it isn't), and fills its properties from `BackendManager.listen("<topic>.state", …)` ([protocol](../backend/protocol.md) › Polled topics).
- **Widget side:** hold the request in a `readonly property var …Request` built from `properties`; acquire it in `Component.onCompleted` and in `on…RequestChanged`; release in `onDestruction`.

### CommandManager: services keep no Process
- `CommandManager.runDetached(command, cwd)` runs a command nothing waits on: a shell string (a widget's click command) or an argv, in `cwd` when given (a desktop entry's `Path=`). Apps the shell starts go through it, never `DesktopEntry.execute()` or `Quickshell.execDetached`, so they aren't qs's children and keep transparent huge pages ([memory](memory.md) › Transparent huge pages).
- `run(command, callback, input)` runs a service's one-off command.
  - callback is `(exitCode, stdout, stderr)`
  - `input` goes to stdin.
  - Both run in axiom (`exec.run`, `exec.spawn`; the greeter's `axiom greeter` answers them too; [roadmap](../backend/roadmap.md) › Stage 3b), and never without it (a shell started by hand). A run that can't start or whose answer is lost calls back with -1, the reason as stderr and the error as a fourth argument (kind `unavailable` when the answer was lost); a command killed by a signal is -1 with no error.
- `acquire` watches a command in axiom (`exec.watch` / `exec.unwatch` / `exec.refresh`, `backend/internal/command/watch.go`): one watch per command with the shortest interval its consumers asked (at least 500 ms), `mode` `poll`, `once` (run once, then on `refresh`) or `stream` (when any consumer asked: the command runs for as long as it's watched and each line it prints is an output, coalesced to a few a second, capped at 64 KiB, restarted with backoff when it exits; `backend/internal/command/stream.go`), and `format` `json` when any consumer asked. Every watched command's output comes in one `exec.outputs` push (`{ outputs: { command: { text, value, error, exitCode, at } } }`, latest-wins, sent only when an output changed); the watches are sent again after every hello. A script refreshes a watched command from outside with `axiom exec refresh COMMAND` (the command string as watched; Waybar's `signal`).
### FileManager and StateManager: services keep no FileView
- `FileManager.read(url)` is a blocking read (a `FileView`), for bindings and initializers: the socket is async.
- `FileManager.write(path, text, done)` replaces a file atomically in axiom (`file.write`, `backend/internal/files`): a temp file renamed over it, its missing folders made 0700, an existing file's mode kept (a new one 0644). Writes to one path go out one at a time, in order; `done(error)` follows each.
- `FileManager.watch(path, fn)` calls `fn()` when the file changes on disk (`file.watch` / `file.unwatch`; one `file.changed` push per change, to the watching connection only, after 50 ms without events), but not for axiom's own write of it (the file is still the one it wrote). It returns the watch, which `unwatch(watch)` ends. The watches are sent again after every hello. `NotesManager`'s documents and `TodoManager` watch their files: an edit made elsewhere shows at once.
- `StateManager.createStateHandler(name)` gives `save` / `load` for `Paths.statePath/<name>.json`: load reads it at once, save writes it through `FileManager.write`. Both need axiom (the greeter's answers them too); a shell started by hand saves nothing.
- So services keep no `Process` of their own. Direct `Process`, `FileView`, `Socket`, `IpcHandler` and `Quickshell.execDetached` are frozen to the files in `scripts/quickshell-io-allowlist.json` (`check_structure`), which shrinks as those side effects move to the axiom daemon ([roadmap](../backend/roadmap.md), [protocol](../backend/protocol.md)). Funnelling through `CommandManager`, `FileManager` and `StateManager` let each switch to the daemon in one place.

### Other domain services
They follow the same pattern:
- **AudioManager**: also every write to a Pipewire node (`setNodesVolume` / `setNodesMuted`).
  - `matchStreams(apps, other, excluded)` is the OSD app bars' playback stream matching.
  - Recording streams are left out: an app's mic capture shares its name.
- **BatteryManager**: also the power profile, and `level` against the `Battery` section's thresholds (`BatteryConfig`; the Battery widget and module colour from it).
  - Sends the low battery notifications, once per drop into low and then critical, whatever bars exist.
  - Created from `shell.qml`'s `_services` so it runs without a widget.
- **KeyboardLayoutManager**, **MediaManager** (MPRIS), **CompositorManager** (the compositor, through its backend `HyprlandManager`: [compositor/](../compositor/README.md)), **StateManager**, **BarManager**, **LauncherManager**, **SettingsManager**, **SavedConfigsManager**, **AuthManager**, **LockManager**.

### One axiom per display
- **Restarting** is `axiom restart` (`Paths.restartCommand`), what every compositor's `restartShell` bind runs (the daemon's `render`; the bind merge (`compositor/actions`) reads it back as `restartShell`). The daemon restarts its quickshell child; it keeps one instance per display itself (its instance lock), so the shell no longer checks for others ([The axiom binary](../backend/README.md)).
- `qs list` / `qs kill` match the display (`WAYLAND_DISPLAY`), so a nested axiom (`scripts/dev/nested.sh`) and the live one never end each other.

Feature services each have their own doc under `docs/dev/features/`, `docs/dev/hyprland/` and `docs/dev/theming/` (see the index).
