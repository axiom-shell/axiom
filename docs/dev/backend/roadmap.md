# Moving the service layer to the axiom binary

> **Files:** `scripts/quickshell-io-allowlist.json`, `scripts/check_structure.py`, `qml/services/core/BackendManager.qml`, `backend/internal/topics/`, `backend/internal/dbus/`, `qml/services/core/CommandManager.qml`, `qml/services/core/FileManager.qml`, `qml/services/core/StateManager.qml`, `qml/services/core/IpcTarget.qml`, `qml/services/core/ConsumerRegistry.qml`, `backend/internal/daemon/`
> **Related:** [The axiom binary](README.md), [Protocol](protocol.md), [Wayland protocols](wayland.md), [Services pattern](../core/services-pattern.md), [every method and push](../generated/rpc.md) (generated)

The plan that moved side effects out of QML and into the `axiom` daemon, stage by stage. **Every stage is done**: each is one line below, and its full record (what moved, what was learned, the maintainer's decisions) is in git history (`git log -p -- docs/dev/backend/roadmap.md`). What stays here is the end state, the scope, and the rules any further move follows. Cleanup work that waited for a stage is in the [cleanup roadmap](../roadmap.md).

### The end state
- **Quickshell** draws Wayland windows (layer shell, popups, the session lock, focus grab, screencopy) and runs the QML: readers, rendering, per-screen `Variants`, hot reload. Leaving it entirely isn't planned: that would mean a C++ host against Qt's private Wayland API.
- **The daemon** owns the side effects: processes, file watching and writes, sockets, HTTP, polling, and later its own Wayland connection.
- **The shell** gets state through pushes and asks for actions through calls ([protocol](protocol.md)).

### Scope
- **Now:** Quickshell.Io's side effects: every direct `Process`, `FileView`, `Socket`, `IpcHandler` (gone since stage 6) and `Quickshell.execDetached`. `scripts/quickshell-io-allowlist.json` lists the files still using them, and `check_structure` keeps the list from growing: it is the live record of what's left.
- **Planned, not scheduled:** services on Quickshell's D-Bus and native-library modules (notifications, tray, UPower, Mpris, Polkit, networking; Pipewire and PAM, which would need cgo, against `CGO_ENABLED=0`). Don't start these without the maintainer. The daemon has its own D-Bus client since stage 2 (`internal/dbus`, [dbus.md](dbus.md)): the D-Bus ones build on it.
- **Stays in QML:** the UI-state managers (bars, popouts, overlay, docks, editors).

### Rules for every move
- **Go takes the side effect; QML keeps the reader and the rendering.** The service's public API stays the same where it can, so widgets don't change.
- **The QML version goes in the same change.** No parallel paths "for now": drop the file's allowlist entry (or the kind) as it moves.
- **A service a move empties is folded or deleted in that move**, not before: the IPC managers into their backends (stage 6), `WeatherSource` into `WeatherManager` (stage 5, done); `HypridleManager` and `IdleInhibitManager` became `IdleManager` (stage 2). The services' folders: `qml/services/AGENTS.md` › Folders.
- **Pick by user value:** a dependency removed, a process no longer started on a timer, a secret kept out of QML. Something no user would notice can stay on the allowlist.
- **Keep pushes small and specific** (a topic carries what its service shows), never at frame rate. The shell's JS runs on the thread that draws frames.
- New methods and pushes follow [protocol](protocol.md) › Changing the protocol; `rpc.md` regenerates itself.

### Stages
One line each: `- **Stage <n>: <name>** (<status>): <outcome>`, the status **done**, **next**, **ready** or **later**.

- **Stage 0: foundations** (done): Go-polled topics (`BackendManager.acquire` / `release` / `refresh`, [protocol](protocol.md) › Polled topics), latest-wins pushes, the daemon's own Wayland connection, the generated `rpc.md` and the Quickshell.Io allowlist.
- **Stage 1: pilot** (done): `TailscaleManager`, `DependencyManager` and `TimeZoneManager` moved to the daemon (`tailscale` topic, `deps.check`, `tz.*`), the first polled topic end to end.
- **Stage 1b: on stage 0's pieces** (done): updates, system stats (`sysmon`), album art, `net.addresses` and Claude usage moved ahead of their stages; `PolkitManager`'s `pgrep`, `CalculatorManager`'s `qalc` and the wallpaper folder count judged not worth it.
- **Stage 2: Wayland** (done): idle (`internal/idle`, with logind and `org.freedesktop.ScreenSaver` on the daemon's own D-Bus client), the clipboard, typing and night light on the daemon's Wayland clients; hypridle, cliphist, wl-clipboard, wtype and hyprsunset left the dependencies.
- **Stage 3: system data** (done): brightness (`brightness.*`, backlights through logind), so brightnessctl left the dependencies.
- **Stage 3b: exec** (done): `CommandManager`'s one-off runs, polled and streamed subscriptions and JSON parsing in the daemon (`exec.run`, `exec.spawn`, `exec.watch`, `axiom exec refresh`), the greeter served by its own `axiom greeter`.
- **Stage 4: scripts** (done): CalDAV, theme generation and integrations, the integration hookup, self-update, the cursor theme, community downloads and the greeter installer ported to Go; python-icalendar, numpy, Pillow and jq left the dependencies.
- **Stage 5: HTTP** (done): weather and the chat (requests and keys) in Go; `WeatherSource` folded into `WeatherManager`, `ChatRequest` and `ChatProtocol` gone.
- **Stage 6: the funnels** (done): every direct `Process` / `execDetached` through `CommandManager`, secrets (`secrets.*`), file writes and watches (`file.*`), the compositor sockets (`hypr.request`, `niri.*`) and IPC (`axiom ipc` only) in the daemon; `BackendManager`'s socket and `FileManager`'s blocking read stay on the allowlist for good.
- **Stage 7: the config path** (done): saves as `config.set` path ops, `takeover` per save, previews through `ConfigManager.setPreview`, writes applied in order, the takeovers kept by the store, one validator, a thin `compositor.inputs` with the `KeybindManager` split, and the QML compositor renderers replaced by daemon methods.
- **Stage 8: the last scripts** (done): `pick_path.py` → `filepicker.pick` and `bug_info.sh` → `axiom bug-info`; nothing at runtime runs python3. The wallpaper script isn't ported: axiom's own wallpaper drawing replaced it.
- **Bluetooth** (done; the maintainer's go-ahead, 2026-11-06): `BluetoothManager` reads the daemon's `bluetooth` topic (`internal/bluez`, BlueZ on the daemon's own D-Bus client) instead of Quickshell.Bluetooth, which nothing imports now ([networking and Bluetooth](../features/networking-bluetooth.md)).
