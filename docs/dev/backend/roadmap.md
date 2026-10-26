# Moving the service layer to the axiom binary

> **Files:** `scripts/quickshell-io-allowlist.json`, `scripts/check_structure.py`, `services/core/BackendManager.qml`, `backend/internal/topics/`, `backend/internal/dbus/`, `services/core/CommandManager.qml`, `services/core/FileManager.qml`, `services/core/StateManager.qml`, `services/core/IpcTarget.qml`, `services/core/ConsumerRegistry.qml`, `backend/internal/daemon/`
> **Related:** [The axiom binary](README.md), [Protocol](protocol.md), [Wayland protocols](wayland.md), [Services pattern](../core/services-pattern.md), [every method and push](../generated/rpc.md) (generated)

The plan for moving side effects out of QML and into the `axiom` daemon, stage by stage. Read this before starting any of it, and update it in the change that does a step (its status, and anything learned that changes a later stage). Cleanup work that waits for a stage is listed in the [cleanup roadmap](../roadmap.md).

### The end state
- **Quickshell** draws Wayland windows (layer shell, popups, the session lock, focus grab, screencopy) and runs the QML: readers, rendering, per-screen `Variants`, hot reload. Leaving it entirely isn't planned: that would mean a C++ host against Qt's private Wayland API.
- **The daemon** owns the side effects: processes, file watching and writes, sockets, HTTP, polling, and later its own Wayland connection.
- **The shell** gets state through pushes and asks for actions through calls ([protocol](protocol.md)).

### Scope
- **Now:** Quickshell.Io's side effects: every direct `Process`, `FileView`, `Socket`, `IpcHandler` and `Quickshell.execDetached`. `scripts/quickshell-io-allowlist.json` lists the files still using them, and `check_structure` keeps the list from growing: it is the live record of what's left.
- **Planned, not scheduled:** services on Quickshell's D-Bus and native-library modules (notifications, tray, UPower, Mpris, Polkit, Bluetooth, networking; Pipewire and PAM, which would need cgo, against `CGO_ENABLED=0`). Don't start these without the maintainer. The daemon has its own D-Bus client since stage 2 (`internal/dbus`, [dbus.md](dbus.md)): the D-Bus ones build on it.
- **Stays in QML:** the UI-state managers (bars, popouts, overlay, docks, editors).

### Rules for every move
- **Go takes the side effect; QML keeps the reader and the rendering.** The service's public API stays the same where it can, so widgets don't change.
- **The QML version goes in the same change.** No parallel paths "for now": drop the file's allowlist entry (or the kind) as it moves.
- **A service a move empties is folded or deleted in that move**, not before: the IPC managers into their backends (stage 6), `WeatherSource` into `WeatherManager` (stage 5); `HypridleManager` and `IdleInhibitManager` became `IdleManager` (stage 2). The services' folders: `services/AGENTS.md` › Folders.
- **Pick by user value:** a dependency removed, a process no longer started on a timer, a secret kept out of QML. Something no user would notice can stay on the allowlist.
- **Keep pushes small and specific** (a topic carries what its service shows), never at frame rate. The shell's JS runs on the thread that draws frames.
- New methods and pushes follow [protocol](protocol.md) › Changing the protocol; `rpc.md` regenerates itself.

### Stages
Status: **done**, **next** (what to take up next), **ready** (needs nothing stage 0 didn't build), or **later**. An item moved ahead of its stage is listed where it's done and leaves a pointer behind.

**Stage 0: foundations** (done)
- Done: **Go-polled topics**: `BackendManager.acquire(topic, request)` / `release(topic)` / `refresh(topic)`, mapped to `<topic>.subscribe` / `unsubscribe` / `refresh`; the daemon (`backend/internal/topics`) polls at the shortest interval asked and pushes `<topic>.state`. The same contract as `ConsumerRegistry`: nothing runs without consumers ([protocol](protocol.md) › Polled topics). A polled move is a `topics.Source` in its own package, added to `daemon/topics.go`.
- Done: **latest-wins pushes**: Go keeps only the newest unsent state per method (`rpc.Conn.NotifyLatest`, [protocol](protocol.md) › The wire), rather than queueing every sample, so a stalled shell can't fill a connection's write queue (4096 messages) and get dropped. `config.state` stays queued: it follows its `config.changed` (stage 7 reshapes both).
- Done: **the daemon's Wayland connection**: `wire.Conn` and the output list on it (`wayland/outputs`, [wayland.md](wayland.md)); `share.*` no longer takes `outputs` (protocol 2). Stage 2 binds its protocols on the same connection; clipboard adds file descriptor passing.
- Done: [protocol](protocol.md), the generated and cross-checked `rpc.md`, the Quickshell.Io allowlist.

**Stage 1: pilot** (done)
- Done: `TailscaleManager`: polling `tailscale status --json` → the `tailscale` topic (`backend/internal/tailscale`), the first polled topic end to end. Its floor (5 s) is Go's; the bar widget's default interval is 10 s.
- Done: `DependencyManager`: a `sh` + `command -v` per tool → `deps.check` (`backend/internal/deps`: `exec.LookPath`, the Python modules in one python3 run).
- Done: `TimeZoneManager`: `sh` + `awk` over `tzdata.zi` and `TZ=… date +%z` per zone → `tz.zones` (a Go parser, fetched once) and `tz.offsets` (`backend/internal/tz`, the zoneinfo files read in Go). The greeter has no daemon: there it asks `axiom tz zones|offsets`, the same answers from the CLI.

**Stage 1b: on stage 0's pieces** (done: services that needed nothing new, taken ahead of their stage)
Each copies a stage 1 shape (a polled topic as `tailscale`, a one-off call as `deps.check` in `daemon/tools.go`); every service kept its API and left the allowlist.
- Done: `UpdatesManager` (from stage 3) → the `updates` topic (`backend/internal/updates`). The per-distribution table stays QML's (`Packages.updates`): the request carries `{ check: {command, found, none, format}, aurHelper }`, and Go runs the check, then the AUR helper's `-Qua` (looked up with `exec.LookPath`, never a shell), and parses both (the QML parser moved to Go with its tests). Every check ends in a state, a failed one with its `error` and the last packages, so `checking` always clears; the hub runs one check at a time (concurrent `checkupdates` share a temp db). The upgrade still opens in a terminal, through `CommandManager.run`.
- Done: `SystemManager` (from stage 3) → the `system` topic (`backend/internal/system`): one sampler over /proc and /sys for the union of the metrics asked (sensor discovery ported from the shell script, `nvidia-smi` only without an AMD card), disk usage by `statfs` on a one-minute clock, the process list from `/proc/<pid>/stat` deltas (no `top`). Each push is one sample with an `at` time, so the history (still a QML ring buffer) gets every one; a request for new metrics is fetched at once (the hub fetches any request not asked for yet), so a page just opened fills straight away. `kill` is `system.kill` (SIGTERM from Go).
- Done: `MediaManager`'s album art (from stage 5) → `media.art` (`backend/internal/media`): an http(s) URL downloaded (15 s, ≤ 32 MB) or a file:// one copied, into `path.part` and renamed, only directly in `$XDG_RUNTIME_DIR/axiom/media-art/`. No more bash + curl for it.
- Done: `NetworkingManager`'s `ip -4 -j addr` → `net.addresses` (`backend/internal/netif`, `net.InterfaceByName`); the greeter (a Network module may show there) asks `axiom net address`, as it does `axiom tz`.
- Done: `ClaudeUsageManager` (from stage 5) → the `claudeUsage` topic (`backend/internal/claudeusage`): Go's HTTP, the token read in Go so it never reaches QML, the once-per-interval rule, backoff and saved state (the same `claude-usage.json`) with it. The hub ticks every minute; `every` is the user's interval. A renewed login is noticed by the credentials' mtime at each tick, standing in for stage 6's `file.watch`. `OnRefresh` lets `refresh()` refetch every account not rate limited.
- Not worth it: `PolkitManager`'s `pgrep`, `CalculatorManager`'s `qalc` (Go would run the same program), `WallpaperManager`'s folder count (its `xdg-open` keeps it on the allowlist).

**Stage 2: Wayland** (done; on stage 0's connection, shared by its clients (`wayland/client`), with file descriptors passed on `internal/unixmsg`, which the daemon's D-Bus client uses too; protocols per compositor: [wayland.md](wayland.md))
- Done: **idle**: `HypridleManager` → `internal/idle` ([idle.md](../features/idle.md)); hypridle is no longer a dependency.
  - hypridle's listeners (`HypridleConf.listeners`) became `idle.Plan`'s typed steps, one `ext_idle_notifier_v1` notification each on the daemon's connection (now shared by its clients: `wayland/client`, the seat in `wayland/seat`).
  - Its D-Bus side went with it, on the daemon's own client (`internal/dbus`, the maintainer's decision): logind's Lock, PrepareForSleep with a delay inhibitor, idle inhibitors and Suspend (`internal/logind`), and `org.freedesktop.ScreenSaver` (`internal/screensaver`).
  - The screens are turned off over the compositor's socket (`Manager.ScreenPower`); `dpmsCommand` left the compositor contract.
  - Learned: niri holds `org.freedesktop.ScreenSaver` itself and applies it to its own idle notifications, so the daemon tells a compositor holding it from a stray hypridle (the peer pid of its Wayland socket, `wire.Conn.PeerPID`).
- Done: **clipboard**: `ClipboardManager`'s `wl-paste --watch` and cliphist → the daemon's in-memory history (`internal/clipboard`) over `ext_data_control_v1`, wlr's as the fallback (`wayland/datacontrol`), and every wl-copy / wl-paste (copying, screenshots, the chat's paste) → `clipboard.*`. cliphist and wl-clipboard are no longer dependencies, and `Launcher.providers.clipboard.source` is gone (pruned at load). History never touches disk; only pinned clips do (images are files on tmpfs, for the shell to show).
- Done: **typing**: `EmojiManager`'s `wtype` → `input.type` on `zwp_virtual_keyboard_v1` (`wayland/vkbd`: a keyboard per text, with a keymap giving each character a key, as wtype does); wtype is no longer a dependency. What the connection can do reaches the shell as `wayland.state` (`WaylandManager`), which services gate on.
- Done: **night light**: hyprsunset → `nightlight.set` on Hyprland's CTM (`wayland/ctm`), wlsunset → gamma ramps (`wayland/gamma`) on sway; hyprsunset is no longer a dependency. niri offers neither yet, so `NightLightManager` keeps its wlsunset `Process` there (its allowlist entry stays for that); the daemon picks by the globals, so a niri that offers gamma control gets it with no change.

**Stage 3: system data** (later)
- `SystemManager`, `UpdatesManager`: done in stage 1b.
- `BrightnessManager`: brightnessctl → sysfs; ddcutil stays an exec, from Go.

**Stage 4: scripts** (later; pure rendering at the core, effects at the edge, as `compositor/render` is)
- `calendar_sync.py` → a Go CalDAV client (also unblocks VTODO sync).
- `generate_theme.py` and the `theme_*.sh` integrations → a renderer plus one writer per integration's `axiom.*` file.
- `integration_hookup.py` → `compositor/edit` (atomic replacement, dated backups).
- `self_update.sh` → the daemon, which already owns the re-exec after an update.
- `cursor_theme.py`, `community_fetch.sh` → small helpers behind one call each.
- `greeter/greeter_install.sh` last: it runs as root; test only against `AXIOM_GREETER_ROOT`.

**Stage 5: HTTP** (later)
- `WeatherSource`: XHR polling → Go HTTP behind a topic. `ClaudeUsageManager` and `MediaManager`'s album art: done in stage 1b.
- `ChatRequest` with `SecretsManager`: streamed replies pushed as chunks, keys read in Go so they never pass through QML, argv or temp files.

**Stage 6: the funnels** (later; each moves every caller with it)
- `CommandManager` → `exec.run` / `exec.spawn` and an `exec` topic for polled commands; then the remaining direct `Process` / `execDetached` users switch to it.
- File watching and atomic writes (`StateManager`, notes, todos, chats, notification history) → `file.watch` (pushes on change) and `file.write`. `FileManager.read` stays: bindings need a synchronous read, and the socket is async.
- `HyprlandIpcManager`, `NiriIpcManager`: the daemon already holds each compositor's socket (`backend/internal/compositor/ipc`) and can push its events. Keep those pushes small: workspace and focus changes drive the UI.
- `IpcTarget` stops being an `IpcHandler` once binds and scripts all use `axiom ipc`; the daemon's `qs ipc --pid` fallback retires with it.
- Stay on the allowlist for good: `BackendManager`'s `Socket` (the bridge itself) and `FileManager`'s blocking read.

**Stage 7: the config path** (later)
- Saves send `config.set` path ops instead of the whole config (`config.replace`), and `config.changed` carries the change rather than the whole config.
- `takeover` belongs to the op, not the connection: only a takeover card's op carries it, every other save sends `false`, so the store's guard binds the shell too ([issue](../issues.md#shell-saves-carry-unsaved-settings-and-every-takeover)).
- Live edits show through `ConfigManager.setPreview`, never by changing the running config, so a save sends only what was saved, not another page's unsaved edits (same issue).
- Config writes apply in the order sent: `config.*` calls handled in order per connection, or a base revision the store refuses on mismatch ([issue](../issues.md#config-saves-can-land-out-of-order)).
- A config.json that doesn't load holds every takeover in one place, the store: `Replace` / `Restore` decide the unknown takeovers there (the restored file's own values, or refused), the compositor manager's own kept mode (`KeptMode`, `saveKept`) and `CommunitySetupsManager`'s `commit(config, false)` stopgap are deleted, and whether a held value is written back over an outside edit is decided ([issue](../issues.md#the-compositor-mode-is-held-twice-while-configjson-doesnt-load), [issue](../issues.md#restoring-over-a-configjson-that-doesnt-load-resets-the-other-takeovers), [issue](../issues.md#the-compositor-card-shows-the-files-mode-while-a-kept-mode-isnt-saved)).
- The contract check (cleanup Phase 4) sees only literal call sites: the runtime warning for helper-built params was not taken, so the new `config.set` ops and `compositor.inputs` get tests of their own.
- One validator: the shell stops validating before it saves (Go's answer stands anyway); `applyDefaults` stays for previews.
- A thin `compositor.inputs`: Go reads binds, profiles, strips and the look from the config it owns; the shell sends only runtime facts (`supports`, `fx`, resolved theme colours).
- Code on both sides gets an exit: `SchemaValidation` (shared fixtures), the compositor helpers `compositor/render` ported (`HyprLua`, `NiriConf`, `SwayConf`, `CompositorLayer`), and the bind tables Go reads out of `BindActions.qml` (shared data in a JSON file both read, or the QML copy deleted).
