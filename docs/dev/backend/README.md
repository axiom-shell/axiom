# The axiom binary

> **Files:** `backend/`, `services/core/BackendManager.qml`, `services/core/DevManager.qml`, `components/views/Settings/DevModeStatus.qml`, `config/json/backend.json`, `scripts/check_go.sh`, `scripts/generate.sh`, `scripts/dev/fixtures.py`
> **Related:** [Config manager](../core/config-manager.md), [Packaging](../packaging.md), [Testing](../testing.md)

`axiom` is one Go binary (source in `backend/`, rules in `backend/AGENTS.md`). It is being brought in in stages; this page says what exists now and grows with it.

### What it is for
- The **parent process** of the shell (`axiom run`) and the greeter (`axiom greeter`): it starts quickshell, restarts it when it crashes, and keeps one instance per display.
- The **owner of config.json**: loading, migrating, validating and writing, with the shell as a client over a unix socket (NDJSON JSON-RPC 2.0).
- The **command line**: `axiom config …`, named commands and `axiom ipc <target> <fn>` passthrough to the shell.
- Later, the side effects that need a Wayland connection (idle, gamma, clipboard).
- **The direction:** Quickshell ends up only drawing Wayland windows (layer shell, popups, the session lock, focus grab, screencopy) and running the QML. Next to move here are Quickshell.Io's side effects (processes, file views, sockets, IPC handlers): `scripts/quickshell-io-allowlist.json` lists the files still using them, and `check_structure` keeps the list from growing. D-Bus services (notifications, tray, UPower, Mpris, Polkit, Bluetooth, networking) and native-library ones (Pipewire, PAM, which would need cgo) are planned, not scheduled. The stages, and the rules for each move: [roadmap](roadmap.md).

### What exists now
- **`axiom run [--dev] [--tree DIR]`**: the daemon for `$WAYLAND_DISPLAY`.
  - The tree is `--tree`, else `$AXIOM_TREE`, else the nearest one up from the working directory, else the installed places (`tree.Find`: `~/.config/quickshell/axiom`, then `/etc/xdg/quickshell/axiom`): a compositor's autostart runs it from `$HOME`.
  - It takes the display's instance lock and builds the schema from the tree (`config/schema/`).
  - It opens the config, writes both for the shell into `$XDG_RUNTIME_DIR/axiom/<display>/`, serves the socket there, and supervises `qs -p <tree>`.
  - Supervision: restart with a growing delay after a crash, give up after 5 crashes in a minute, stop an orphan an earlier daemon left (its process group, matched by its exact command line; never the shell a re-exec adopts). A run that ended on its own is `OnExit`'s, a stop the supervisor asked for `OnStop`'s.
  - It holds its own Wayland connection (`wayland/outputs` on a `wire.Conn`) and stops when the compositor closes it: a daemon outliving its session would hold the display's lock, and the next session's `axiom run` would find it taken. If that connection fails otherwise (a protocol error), an idle one (`wire.Watch`) still watches.
  - The shell gets `AXIOM_SOCKET`, `AXIOM_SCHEMA`, `AXIOM_CONFIG`, `AXIOM_TREE`, `AXIOM_BIN` (the installed binary, never a dev build) and, read at each start, `AXIOM_INCOMPATIBLE` while the tree's schema isn't the binary's and dev mode is off.
  - `--dev` starts in dev mode whatever was chosen last, and logs to the terminal (and the shell's output with it).
  - SIGINT, SIGTERM and SIGHUP (its terminal closed) stop it cleanly, its shell with it (`cli.Main`); SIGHUP stays ignored when it started ignored (`nohup`).
- **The daemon's parts** (`backend/internal/daemon/tasks.go`): each piece is a `part` (`core`, `config`, `ipc`, `sharing`, `compositor`, `topics`, `tools` (one-off calls: `deps.check`, `tz.*`, `media.art`, `system.kill`, `net.addresses`), `dev mode`): the RPC methods it registers, a `run(ctx)` started on the daemon's `tasks`, and an `onConfig` told of every store event in order. A part's methods are also listed in `methodSets` (`contract.go`), from which `BuildContract` builds the registry without starting anything (`backend/internal/daemon/contract_test.go` checks the two agree; [protocol](protocol.md) › Changing the protocol). Every goroutine is started through `tasks.Go` (the locker gets it as `lockscreen.Options.Go`) and `Run` waits for all of them; work that must not overlap itself (`saved.Changed`, dev builds) is a `kicker`.
- **Store events** are queued under the change lock and delivered after it's released, one at a time in revision order: a subscriber may read and write the store (its own event is delivered after the one it was handed).
- **Pushes go by topic**: the hello's `subscribe` is `true` (every topic, what the shell asks), `false`, or a list of `config` (`config.changed`, `config.state`, `schema.changed`, `schema.error`), `saved` (`saved.state`), `daemon` (`daemon.state`, `dev.state`). A new topic or method needs no protocol bump; changing what an existing one means does. Whole-state pushes are latest-wins ([protocol](protocol.md) › The wire). Polled data is a separate opt-in: a connection subscribes to each [polled topic](protocol.md#polled-topics) (`backend/internal/topics`) by itself.
- **Writable or read-only**: a tree whose schema isn't the one the binary embeds (or any tree, from a binary built without its embedded schema) runs read-only (`compatible: false` in the hello, config writes refused) unless dev mode is on. It changes at runtime with dev mode (`daemon.state`); the shell's start-up notice (`BackendManager.incompatible`, `shell.qml`) clears once it becomes writable, but never comes back while the shell runs.
- **Dev mode** (`backend/internal/daemon/dev.go`, `axiom dev status|on|off|rebuild`, `dev.get|set|rebuild`, `DevManager`, the settings' `DevModeStatus` above axiom updates, `/dev`): switched while axiom runs and remembered in `$XDG_STATE_HOME/axiom/dev.json` (state, never config.json); `--dev` forces it on for one run, and a re-exec carries it in the handoff. While it's on:
  - the schema is rebuilt within 100 ms of a YAML edit: `schema.changed` is pushed before the `config.changed` of the config loaded through it, and the tree's `config/json/config.schema.json` is rewritten only in a git checkout;
  - a tree whose schema isn't the binary's may save; the log is at debug level (`Options.LogLevel`);
  - an edit to `backend/` (not tests, not `internal/assets/data/`) or an embedded `config/json` file builds, after 1 s of quiet, `go generate ./internal/assets` + `go build` into `$XDG_STATE_HOME/axiom/dev/axiom`, checks it runs (`version`), and re-execs into it, the shell running on. A failed build keeps the running binary, its output in `dev.state.lastBuild` and a notification. Builds need the tree's `backend/go.mod` and `go` (`available`, else `unavailable` says why);
  - a rebuilt installed binary is re-exec'd into, as before.
  - Off: the watchers stop; from a dev build it re-execs back into the installed binary. `dev.state.offReadOnly` warns when that would leave the config read-only.
- **`axiom greeter [--tree DIR] [--dir DIR] [--safe]`**: the login screen's parent (`greeter-session.sh` runs it as greetd's user). It loads the exported bundle, else the install's snapshot, else the defaults, through the same pipeline (`backend/internal/greeter`), writes it to `$XDG_RUNTIME_DIR/axiom/greeter-<display>/` and runs `qs -p <tree>/greeter.qml` on it, staying its parent until it exits (non-zero when qs failed): a socket in that folder answers the greeter's commands and lookups, and nothing else ([Greeter runtime](../features/greeter-runtime.md), [protocol](protocol.md)).
- **The config store** (`backend/internal/store`):
  - The one writer of config.json, holding `config.json.lock`.
  - Loading: format 1 through the frozen migrations and the conversion to format 2 (the file kept as `config.format1.json`), then the format-2 steps (`migrate/steps`), with defaults written on a first run. A file that doesn't load blocks saves until fixed. Edits made outside are watched; the store's own writes are recognised.
  - Writing: path ops (keys and `{id}` selectors, never positions), validation, and takeover settings refused without `takeover`. A replace or restore keeps them (making a section it lacks, so the defaults can't reset one); over a file that didn't load at the start, the values that file held, not the defaults the store runs on.
  - Outside edits are told from its own writes by the bytes last written or read, so undoing a broken edit back to them is read again.
  - An outside edit never changes a takeover setting (`holdTakeovers`): the value in effect is kept, each key ignored is logged, and the file is written back with it (normalized, like any write of the store's). Over a file that wasn't JSON at the start no value is known, so the first edit that loads sets them, though the compositor's manager keeps the mode it applied and saves it back ([config-modes.md](../compositor/config-modes.md#leaving-a-mode)). `Store.Takeovers` hands out the values in effect (the file's while the store runs on the defaults, none known over a file that wasn't JSON): the compositor's mode is read from it.
  - Writes are atomic and keep a symlinked config a symlink.
- **The shell's side:**
  - `BackendManager` (the connection, hello, reconnect; `compatible` and `dev` from the hello and its pushes).
  - `ConfigManager`: the config read from the snapshot and pushes. Writes are checked against the schema in JS, applied at once and sent to the daemon, whose answer stands.
  - `IpcTarget` (every IPC target, registered with the daemon).
  - `LockManager` reporting the lock.
  - A shell started by hand, without `AXIOM_SOCKET`, shows only a notice with the line that starts it (`NoParentNotice`).
- **IPC through the daemon:**
  - `axiom ipc <target> <fn> [args]`, `axiom ipc list`, and named commands (`axiom launcher toggle`, `axiom volume up`, …, checked against `docs/dev/generated/ipc.md`).
  - The shell's registered targets are called over its connection; their signatures come from `qs ipc show`. Others go through `qs ipc --pid <shell> call`.
- **`axiom lock`:** exits 0 only once the compositor has acknowledged the session lock (`WlSessionLock.secure`) and the shell reports a lock surface on every monitor connected (with none connected, the session lock alone). Otherwise it starts the shell locked, then fails. A shell that dies while locked is restarted at once, locking first; `axiom restart` while locked starts the next one locked too, and a stop axiom asked for never relaunches it. Nothing unlocks but PAM; `lockscreen` takes only `lock`. With `Lockscreen.mode` `none` it runs `Lockscreen.lockCommand`, never `loginctl lock-session` (which loops back to axiom).
- **The compositor's config** (`backend/internal/compositor/`, `daemon/compositor.go`): the daemon writes it in every mode ([Config modes](../compositor/config-modes.md)); the shell sends the inputs and shows the state.
  - `compositor/manager`: the modes, the takeover's approvals, the runtime layer and the live parts, one goroutine, one writer per compositor; `compositor/render` (pure): the texts, ported from the JS helpers and checked against their frozen cases; `compositor/ipc`: Hyprland's, sway's and niri's sockets and their reload events;
  - the managed mode's takeover (`compositor/takeover`, every compositor's `check`/`claim`/`release` as one flow over a `Kind`; [Managed takeover](../hyprland/managed-takeover.md)): the compositor manager runs it, and `axiom compositor check|claim|release --kind K -- DIR HEADER [FALLBACK]` from the command line;
  - the bind merge (`compositor/binds`, `extract` and `remove` with one JSON for every compositor; Hyprland's files run under gopher-lua; [Bind merge](../hyprland/bind-merge.md)): the compositor manager runs it (`compositor.merge`), `axiom compositor binds extract|remove` from the command line. What commands map onto comes from the tree's `BindActions.qml` (`compositor/actions`, pure);
  - reading the user's own config (`compositor/userconf`: niri's through `compositor/kdl`, pure; sway's with its includes put in): `axiom compositor niri main|includes|binds|info` and `axiom compositor sway-text`, which the shell runs as `Paths.toolBin`: the binary the daemon runs now (`/proc/<daemon pid>/exe`, so a dev build's re-exec counts, where `$AXIOM_BIN` stays the installed binary), and in the greeter (whose axiom sets no `AXIOM_DAEMON_PID`) `$AXIOM_BIN`, which `axiom greeter` sets to itself;
  - `compositor/luacheck` (whether an edit to a user's Lua still parses: `luac` where installed, else gopher-lua) and `compositor/edit` (atomic replacement and dated backups of a user's files).
- **The rest of the CLI:**
  - `axiom ping|restart|quit`, `axiom daemon status|reexec|logs`, `axiom dev status|on|off|rebuild`
  - `axiom config path|get|set|reset|validate|status`: online, or `--offline` against the file under the writer lock
  - `axiom exec refresh COMMAND`: runs a command the shell watches again now (a script's stand-in for Waybar's `signal`)
  - `axiom schema build|check|hash`, `axiom debug wayland-globals|wayland-outputs`, `axiom version`
- **Re-exec** (`axiom daemon reexec`, or dev mode on a rebuild): the new image takes over the instance lock, the writer lock, the socket and the shell (still its child), and the commands running as its children (`command.Children`: their output drained, reaped when they exit, a stream stopped). Its clients are told first (`daemon.closing`, [protocol](protocol.md) › A session). It trusts the handoff only when the inherited lock really is this display's held lock.
  - The descriptors lose close-on-exec only under `syscall.ForkLock`, so no child starts meanwhile and inherits a lock; an exec that fails gives them it back and thaws the store.
  - The handoff carries dev mode, the installed binary (while a dev build runs), the schema's hash and whether the session was locked: a new image whose tree builds another schema (an update, `axiom daemon reexec` after it) restarts the shell, locked first when it was.

### Wayland
The daemon holds its own Wayland connection ([wayland.md](wayland.md)): `backend/internal/wayland/wire` (the wire protocol, a `Conn` with objects and their events), shared by its clients (`wayland/client`): `wayland/outputs`, the outputs by place that `share.*` names monitors with, the seat, and idle notifications ([idle](../features/idle.md)). Gamma, clipboard and typing come next (roadmap stage 2).

### D-Bus
The daemon's own client ([dbus.md](dbus.md), `backend/internal/dbus`): logind and `org.freedesktop.ScreenSaver` for idle so far.

### Building and checking
- `cd backend && go build ./cmd/axiom` builds it (pure Go, `CGO_ENABLED=0` works).
- `scripts/check_go.sh` runs what CI's go job runs; `--fix` regenerates and formats. `scripts/dev/verify.sh` runs it when `backend/` or an embedded file changed.
- The embedded copies under `backend/internal/assets/data/` are generated and gitignored, the schema among them (built from `config/schema/` by `go generate`, since the binary can't build what it embeds before it compiles): edit `config/json/…` and the YAML. A fresh clone runs `scripts/generate.sh` once before `go build`.

### Security
Code handling sockets, locks, runtime directories, atomic writes, the child's environment or the lock screen is security-relevant: every rule it enforces has a test, and a change to it is reviewed against this list.
- The runtime directory must be a real directory owned by the user with mode 0700; `$XDG_RUNTIME_DIR` is required, never replaced by `/tmp`.
- A lock is taken before anything it guards is touched (a stale socket is removed only while holding the instance lock).
- Every socket connection's peer must be the same user (`SO_PEERCRED`), and a hello as `"shell"` must come from the pid of the shell the daemon runs (`Conn.PeerPID`): only it reports the lock and registers IPC targets.
- Writes are atomic (temp file, fsync, rename, fsync the directory) and never follow a planted symlink.
- Nothing unlocks the lock screen but PAM: no RPC, CLI or IPC path exists for it.
- Descriptors received over a socket (D-Bus, and Wayland as it gains them) are close-on-exec on arrival and closed when nothing takes them (`internal/unixmsg`), so no child inherits one.
- A command the shell asks for (`exec.run`, `exec.spawn`, a watched one through `exec.watch`; `internal/command`) gets the shell's environment and only stdio; what it reads as a secret comes on stdin, never argv or the log, a spawn starts in a session of its own, never the daemon's child, and a streamed watch runs in a process group of its own, killed whole when it stops.

### Shared fixtures
Behaviour implemented on both sides (`SchemaValidation.qml`, which the shell still validates and fills defaults with, and Go's `config` pipeline) is tested from one set of cases under `tests/fixtures/shared/`, read by both `go test` and qmltestrunner (`tests/tst_Shared.qml`), with expected output stored as exact bytes. The directory is generated and gitignored: `scripts/generate.sh --fixtures` records it when what it's made from changed (`fixtures.py ensure`, a stamp of the inputs), and CI records it before the tests.
- **A case** is `<suite>/<test>/<name>.json` (`{op, args}`) plus `<name>.expected.json`: the output as 2-space JSON in JS key order with a trailing newline (`Shared.canonical`). `index.json` lists every case (qmltestrunner can't list folders).
- **Arguments** larger than 2 KB are stored once in `blobs/<hash>.json` and referenced as `{"$blob": hash}`; the live schema is named by its path, `{"$repoFile": "config/json/config.schema.json"}`.
- **Ops** are `schema.applyDefaults`, `schema.validationErrors` and `schema.resolveRef`. `tests/Shared.qml` maps each onto `SchemaValidation`; `backend/internal/config/shared_test.go` onto the pipeline.
- **Recording:** `scripts/dev/fixtures.py record` runs tst_Config (the live schema's defaults) and tst_SchemaValidation (inline schemas) with recording on. The tests call the helpers through `Shared`, which logs every call (arguments and output bytes), so the tests' inline cases become fixtures without being copied by hand. `fixtures.py check` (CI) checks the index and the blobs.
- **The format-1 migration's cases** aren't here: they were recorded from the shell's own migrations before that copy was removed, and frozen as the binary's testdata (`backend/internal/migrate/legacy/testdata/frozen.jsonl.gz`: each input with the sha256 of the bytes V4 made of it; `testkit.Frozen`). `legacy.js` and `schema-v75.json` are hash-checked beside them. Share, pruning and the rest have Go tests of their own.
- **One known difference:** V4's `JSON.stringify` writes a lone surrogate unescaped (it predates ES2019); Go never holds one (`jsonx` decodes it as U+FFFD). No JS-owned case holds one (recording refuses it).
