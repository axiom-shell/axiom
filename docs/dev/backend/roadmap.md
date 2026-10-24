# Moving the service layer to the axiom binary

> **Files:** `scripts/quickshell-io-allowlist.json`, `scripts/check_structure.py`, `services/BackendManager.qml`, `backend/internal/topics/`, `services/CommandManager.qml`, `services/FileManager.qml`, `services/StateManager.qml`, `services/IpcTarget.qml`, `services/ConsumerRegistry.qml`, `backend/internal/daemon/`
> **Related:** [The axiom binary](README.md), [Protocol](protocol.md), [Wayland protocols](wayland.md), [Services pattern](../core/services-pattern.md), [every method and push](../generated/rpc.md) (generated)

The plan for moving side effects out of QML and into the `axiom` daemon, stage by stage. Read this before starting any of it, and update it in the change that does a step (its status, and anything learned that changes a later stage).

### The end state
- **Quickshell** draws Wayland windows (layer shell, popups, the session lock, focus grab, screencopy) and runs the QML: readers, rendering, per-screen `Variants`, hot reload. Leaving it entirely isn't planned: that would mean a C++ host against Qt's private Wayland API.
- **The daemon** owns the side effects: processes, file watching and writes, sockets, HTTP, polling, and later its own Wayland connection.
- **The shell** gets state through pushes and asks for actions through calls ([protocol](protocol.md)).

### Scope
- **Now:** Quickshell.Io's side effects: every direct `Process`, `FileView`, `Socket`, `IpcHandler` and `Quickshell.execDetached`. `scripts/quickshell-io-allowlist.json` lists the files still using them, and `check_structure` keeps the list from growing: it is the live record of what's left.
- **Planned, not scheduled:** services on Quickshell's D-Bus and native-library modules (notifications, tray, UPower, Mpris, Polkit, Bluetooth, networking; Pipewire and PAM, which would need cgo, against `CGO_ENABLED=0`). Don't start these without the maintainer.
- **Stays in QML:** the UI-state managers (bars, popouts, overlay, docks, editors).

### Rules for every move
- **Go takes the side effect; QML keeps the reader and the rendering.** The service's public API stays the same where it can, so widgets don't change.
- **The QML version goes in the same change.** No parallel paths "for now": drop the file's allowlist entry (or the kind) as it moves.
- **Pick by user value:** a dependency removed, a process no longer started on a timer, a secret kept out of QML. Something no user would notice can stay on the allowlist.
- **Keep pushes small and specific** (a topic carries what its service shows), never at frame rate. The shell's JS runs on the thread that draws frames.
- New methods and pushes follow [protocol](protocol.md) › Changing the protocol; `rpc.md` regenerates itself.

### Stages
Status: **done**, **next**, or **later**.

**Stage 0: foundations** (done)
- Done: **Go-polled topics**: `BackendManager.acquire(topic, request)` / `release(topic)` / `refresh(topic)`, mapped to `<topic>.subscribe` / `unsubscribe` / `refresh`; the daemon (`backend/internal/topics`) polls at the shortest interval asked and pushes `<topic>.state`. The same contract as `ConsumerRegistry`: nothing runs without consumers ([protocol](protocol.md) › Polled topics). A polled move is a `topics.Source` in its own package, added to `daemon/topics.go`.
- Done: **latest-wins pushes**: Go keeps only the newest unsent state per method (`rpc.Conn.NotifyLatest`, [protocol](protocol.md) › The wire), rather than queueing every sample, so a stalled shell can't fill a connection's write queue (4096 messages) and get dropped. `config.state` stays queued: it follows its `config.changed` (stage 7 reshapes both).
- Done: **the daemon's Wayland connection**: `wire.Conn` and the output list on it (`wayland/outputs`, [wayland.md](wayland.md)); `share.*` no longer takes `outputs` (protocol 2). Stage 2 binds its protocols on the same connection; clipboard adds file descriptor passing.
- Done: [protocol](protocol.md), the generated and cross-checked `rpc.md`, the Quickshell.Io allowlist.

**Stage 1: pilot** (done)
- Done: `TailscaleManager`: polling `tailscale status --json` → the `tailscale` topic (`backend/internal/tailscale`), the first polled topic end to end. Its floor (5 s) is Go's; the bar widget's default interval is 10 s.
- Done: `DependencyManager`: a `sh` + `command -v` per tool → `deps.check` (`backend/internal/deps`: `exec.LookPath`, the Python modules in one python3 run).
- Done: `TimeZoneManager`: `sh` + `awk` over `tzdata.zi` and `TZ=… date +%z` per zone → `tz.zones` (a Go parser, fetched once) and `tz.offsets` (`backend/internal/tz`, the zoneinfo files read in Go). The greeter has no daemon, so its clocks show the system's time ([issues](../issues.md)).

**Stage 2: Wayland** (next; needs stage 0's connection; protocols per compositor: [wayland.md](wayland.md))
- Idle: `HypridleManager` → `ext_idle_notifier_v1`; removes hypridle. `Idle` is `x-takeover`.
- Clipboard: `ClipboardManager`'s `wl-paste --watch cliphist` → an in-memory history over `ext_data_control_v1` (wlr's as the fallback); removes cliphist and wl-clipboard. History never touches disk; only pinned clips do.
- Typing: `EmojiManager`'s `wtype` → `zwp_virtual_keyboard_v1`.
- Night light: `NightLightManager`'s hyprsunset / wlsunset → `zwlr_gamma_control`; niri keeps wlsunset until a real session shows gamma control.

**Stage 3: system data** (later)
- `SystemManager`: its `/proc` and `/sys` FileViews, `top -b` and `nvidia-smi` → one sampler, a `system` topic.
- `UpdatesManager`: the package checks (the upgrade still opens in a terminal).
- `BrightnessManager`: brightnessctl → sysfs; ddcutil stays an exec, from Go.

**Stage 4: scripts** (later; pure rendering at the core, effects at the edge, as `compositor/render` is)
- `calendar_sync.py` → a Go CalDAV client (also unblocks VTODO sync).
- `generate_theme.py` and the `theme_*.sh` integrations → a renderer plus one writer per integration's `axiom.*` file.
- `integration_hookup.py` → `compositor/edit` (atomic replacement, dated backups).
- `self_update.sh` → the daemon, which already owns the re-exec after an update.
- `cursor_theme.py`, `community_fetch.sh` → small helpers behind one call each.
- `greeter/greeter_install.sh` last: it runs as root; test only against `AXIOM_GREETER_ROOT`.

**Stage 5: HTTP** (later)
- `WeatherSource`, `ClaudeUsageManager`: XHR and `curl` polling → Go HTTP behind topics.
- `MediaManager`'s album art: `bash` + `curl` → a Go download cache.
- `ChatRequest` with `SecretsManager`: streamed replies pushed as chunks, keys read in Go so they never pass through QML, argv or temp files.

**Stage 6: the funnels** (later; each moves every caller with it)
- `CommandManager` → `exec.run` / `exec.spawn` and an `exec` topic for polled commands; then the remaining direct `Process` / `execDetached` users switch to it.
- File watching and atomic writes (`StateManager`, notes, todos, chats, notification history) → `file.watch` (pushes on change) and `file.write`. `FileManager.read` stays: bindings need a synchronous read, and the socket is async.
- `HyprlandIpcManager`, `NiriIpcManager`: the daemon already holds each compositor's socket (`backend/internal/compositor/ipc`) and can push its events. Keep those pushes small: workspace and focus changes drive the UI.
- `IpcTarget` stops being an `IpcHandler` once binds and scripts all use `axiom ipc`; the daemon's `qs ipc --pid` fallback retires with it.
- Stay on the allowlist for good: `BackendManager`'s `Socket` (the bridge itself) and `FileManager`'s blocking read.

**Stage 7: the config path** (later)
- Saves send `config.set` path ops instead of the whole config (`config.replace`), and `config.changed` carries the change rather than the whole config.
- One validator: the shell stops validating before it saves (Go's answer stands anyway); `applyDefaults` stays for previews.
- A thin `compositor.inputs`: Go reads binds, profiles, strips and the look from the config it owns; the shell sends only runtime facts (`supports`, `fx`, resolved theme colours).
- Code on both sides gets an exit: `SchemaValidation` (shared fixtures), the compositor helpers `compositor/render` ported (`HyprLua`, `NiriConf`, `SwayConf`, `CompositorLayer`), and the bind tables Go reads out of `BindActions.qml` (shared data in a JSON file both read, or the QML copy deleted).
