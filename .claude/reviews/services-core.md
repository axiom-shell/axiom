# services-core
reviewed: 4d8f880 2026-10-31  (full)

The core funnels (CommandManager, FileManager, StateManager, ConsumerRegistry, the topics hub and its Go sources) are sound and match their docs. The weak spots are at the edges: two daemon topics lose their failures on the way to the UI (an offline first update check reads "System is up to date", an offline first weather fetch reads "Loading weather…" for the whole interval), and MediaManager, which no doc covers, picks Spotify over a playing player, ticks with nothing shown and never prunes its album art.

## Open findings
- Major: "A failed update check shows as up to date" (fixed, row 20 core-ui-theming-03)
- Major: "A weather fetch that fails shows Loading forever" (fixed, row 20 core-ui-theming-03)
- Major: [SystemManager samples every second while nothing is shown](../../docs/dev/issues.md#systemmanager-samples-every-second-while-nothing-is-shown)
- Major: "The active media player is Spotify first and never follows playback" (fixed, row 20 core-ui-theming-02)
- Major: "Album art piles up in the runtime folder for the whole session" (fixed, row 20 core-ui-theming-02)
- Major: "MediaManager ticks the position with nothing showing it" (fixed, row 20 core-ui-theming-02)
- Cleanup: "runDetached warns about a lost connection" (fixed, row 20 core-ui-theming-07)
- Cleanup: "Small shrinks in the core services" (fixed, row 20 core-ui-theming-01)
Minor (unrecorded):
- `docs/dev/core/services-pattern.md` › Shape: "Every service is `pragma Singleton QtObject`", but 24 services' root is Quickshell's `Singleton` (the service recipe allows it for child objects).
- `docs/dev/core/shell-manager-targeting.md` › "all": names the focus grab `HyprlandGrab`; it is `FocusGrab` (HyprlandGrab only on Hyprland). "A use may narrow the enum (General's own has no `inherit`)": it has no `named` either.
- `services/system/KeyboardLayoutManager.qml:7` says "whenever Hyprland reports"; it is any compositor (`CompositorManager.keyboardLayoutChanged`).
- `services-pattern.md` says StateManager's load and save "Both need axiom"; load is a FileView read and works without it.
- ClaudeUsageManager dedupes accounts by dir and label, Go by dir alone; harmless.

## Contract
Holds: the acquire/release shape for every daemon topic (system, updates, weather, claudeUsage, exec.watch) and its Go hub; the CommandManager, FileManager and StateManager funnels; atomic state writes under XDG paths; ShellManager's targeting and SurfaceManager's registry as documented; the file picker as documented. Broken: "Stops entirely with no consumers" (SystemManager), the polling rule (MediaManager's ticker), updates' "every check ends in a state" reaching the UI.

## Coverage
Read deeply: services/core/ConsumerRegistry.qml, CommandManager.qml, FileManager.qml, StateManager.qml, services/ui/ShellManager.qml, SurfaceManager.qml, services/system/SystemManager.qml, UpdatesManager.qml, MediaManager.qml, BatteryManager.qml, KeyboardLayoutManager.qml, services/apps/WeatherManager.qml, ClaudeUsageManager.qml, FilePickerManager.qml, backend/internal/topics/topics.go, updates/updates.go, media/media.go, filepicker/filepicker.go, daemon/tools.go, command/watch.go (Watch to the end), the four readers, config/General.qml · Outlined: AudioManager.qml (its setters, matchStreams and mic capture read), backend/internal/sysmon/sysmon.go (sample, diskUsage, processes read), weather/weather.go (Source, fetch, resolve read), claudeusage/claudeusage.go (fetch, due, save read), files/files.go (Watch), BackendManager.qml (acquire and the drop path) · Skipped: components/forms/SchemaField.qml, SchemaTextField.qml, config/Paths.qml, shell.qml, ReservedAreaWindow.qml, SurfaceGroup.qml (other systems' cores, only their seams grepped); the Go tests (by grep only).

## History
- 2026-10-31 full: 8 findings (6 Major, 2 Cleanup) plus 5 Minor; recorded
