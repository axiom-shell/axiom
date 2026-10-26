# The shell ↔ daemon protocol

> **Files:** `services/core/BackendManager.qml`, `components/methods/JsonRpc.qml`, `services/core/IpcTarget.qml`, `backend/internal/rpc/`, `backend/internal/daemon/methods.go`, `backend/internal/daemon/daemon.go`, `backend/internal/topics/`, `backend/internal/daemon/topics.go`, `backend/internal/ipcroute/`, `backend/internal/lock/`, `config/json/backend.json`, `config/Paths.qml`
> **Related:** [The axiom binary](README.md), [Config manager](../core/config-manager.md), [Config modes](../compositor/config-modes.md), [every method and push](../generated/rpc.md) (generated)

Where the QML shell and the axiom binary meet. This page says how the connection works. The methods, pushes and the files that use them are listed in [rpc.md](../generated/rpc.md), which `scripts/gen_docs.py` builds from the code and checks: a call or listener in the shell that the daemon doesn't define fails it.

### The channels
The shell (`qs -p <tree>`) is a child of the daemon (`axiom run`). Six channels connect them:
- **A. The environment** the daemon starts the shell with (`daemon.go`, `shellEnv` / `shellEnvNow`):
  - `AXIOM_SOCKET`: the socket (`BackendManager.socketPath`; unset means a shell started by hand, `BackendManager.active` false).
  - `AXIOM_SCHEMA` and `AXIOM_CONFIG`: the runtime files below.
  - `AXIOM_TREE`, `AXIOM_BIN` (the installed binary, `Paths.axiomBin`) and `AXIOM_DAEMON_PID` (`Paths.toolBin` runs `/proc/<pid>/exe`, the binary running now).
  - `AXIOM_INCOMPATIBLE`: set only while the tree's schema isn't the binary's and dev mode is off (`BackendManager.incompatible`).
  - `AXIOM_LOCK_ON_START=1`: a relaunch after a crash while locked (`shell/Lockscreen.qml`).
- **B. Runtime files** in `$XDG_RUNTIME_DIR/axiom/<display>/` (0700, written atomically):
  - `config.json`: the config, loaded, migrated and filled, read once at start (`ConfigManager`'s snapshot); pushes keep it current after that.
  - `config.schema.json`: the schema built from the tree (`ConfigManager`; `BackendManager` sends its md5 in the hello).
  - `compositor.json`: the daemon's own state, kept across re-execs; the shell never reads it.
- **C. Calls, shell → daemon**: JSON-RPC requests on the socket (`BackendManager.call(method, params, done)`).
- **D. Pushes, daemon → shell**: notifications by topic (`BackendManager.listen(method, fn)`).
- **E. Calls, daemon → shell**: `ipc.call`, how `axiom ipc <target> <fn>` and `axiom lock` reach an `IpcTarget` without a process per call (`BackendManager.handle`; answered by `_callTarget`).
- **F. The binary as a command**: the shell runs `Paths.toolBin` for things that need no daemon (`compositor niri info`, `compositor sway-text`), and `Paths.axiomBin daemon reexec` after an update (`SelfUpdateManager`). The compositor configs the daemon writes call `axiom ipc …` for binds. The greeter has no daemon and runs `$AXIOM_BIN`, which is the greeter's own binary.

The daemon also talks to the compositor over its own sockets (`backend/internal/compositor/ipc`). That is a separate connection, not part of this protocol.

### The wire
JSON-RPC 2.0, one message per line (NDJSON), over a unix socket in both directions (`backend/internal/rpc`; on the shell side `JsonRpc` builds and parses each line). Every message on a connection leaves through one queue, so a push caused by a request arrives before that request's reply: `config.changed` comes before the answer to the `config.replace` that caused it.

The whole-state pushes (`daemon.state`, `dev.state`, `saved.state`, `compositor.state`, `idle.state`, and every [polled topic](#polled-topics)'s `<topic>.state`) are **latest-wins** (`Conn.NotifyLatest`, `Server.BroadcastLatest`): each holds one place in the queue, taken where its first unsent state was sent, and what is written there is the newest state. A shell that stalls gets fewer states, never a full queue (4096 messages, after which the daemon drops it). Events (`config.changed`, `schema.*`, `compositor.applied` / `notify` / `bindsMerged`) and `config.state`, which follows its `config.changed`, stay one message each. A message may be up to 16 MiB and nested 64 deep, with at most 256 requests in flight per connection.

### A session
1. The shell connects and sends `daemon.hello` with `protocol` (from `config/json/backend.json`), `client: "shell"`, `schemaHash` (md5 of the schema file it read), `subscribe: true` (every topic) and `pid`. Calls made earlier wait in `BackendManager`'s queue.
2. The daemon refuses a different protocol, a schema other than the one it built, and a `"shell"` hello from any pid except the shell it runs. A refusal fails every call with that error until a later hello is answered.
3. The answer describes the daemon: version, commit, pid, display, tree, `dirs`, the config `state` (`firstRun`, `blocked`, `issues`, `revision`), `compatible` / `reason` and `dev`. It's available as `BackendManager.hello`.
4. The queue is sent, the shell registers its IPC targets (`ipc.register`, names only; the daemon reads their signatures from `qs ipc show`), and `greeted` fires. `ConfigManager` applies the state, acknowledges a first run (`config.ackFirstRun`) and reads the config again (`config.get`) in case it missed a push while disconnected.
5. When the connection drops (a re-exec or a restart), calls in flight fail with `unavailable`, queued notifications wait for the next connection, and the shell reconnects after 200 ms × 2ⁿ (at most 5 s), saying hello again.

### Topics
A hello's `subscribe` is `true`, `false` or a list of topics:
- `config`: `config.changed`, `config.state`, `schema.changed`, `schema.error`
- `saved`: `saved.state`
- `daemon`: `daemon.state`, `dev.state`
- `compositor`: `compositor.state`, `compositor.applied`, `compositor.notify`, `compositor.bindsMerged`
- `idle`: `idle.state` (latest-wins)

The CLI subscribes to nothing.

### Polled topics
Data the daemon polls for the shell (`backend/internal/topics`) is not a hello topic: `subscribe: true` doesn't include it. A connection asks for it:
- `<topic>.subscribe` with `{ interval }` (ms) plus whatever the topic's own request carries; called again, it replaces that connection's request. `<topic>.unsubscribe` drops it, and closing the connection drops all of them.
- The daemon fetches once for every subscriber, at the shortest interval asked (never below the topic's floor), and not at all with none. A topic whose last subscriber left forgets its state.
- It pushes `<topic>.state` to the subscribers when the state changes (latest-wins, below), and to a new subscriber at once when it has one. `<topic>.refresh` fetches now.
- The shell: `BackendManager.acquire(topic, request)` / `release(topic)` / `refresh(topic)`, subscribed again after every hello (a reconnect or re-exec forgets them). The service owning the topic merges its consumers (`ConsumerRegistry`) into one request and listens to `<topic>.state`.
- A topic is a `topics.Source{Name: "…", Floor, Default, Fetch}` in the package owning its side effect, listed in `daemon/topics.go` (`sources`); `rpc.md` reads the name from that literal.
  - A request asking for something no subscriber asked for yet (anything but its `interval` differs) is fetched at once, not at the next interval: `system`'s page just opened fills straight away, `claudeUsage`'s new account and `updates`' new AUR helper are checked now. The same request at another interval only moves the next fetch.
  - `OnRefresh` tells the source of a `<topic>.refresh` before the fetch, for a Fetch that does more when asked (`claudeUsage` refetches every account not rate limited).
  - A state that must reach the shell after every fetch (a failure, a sample for a history) carries its time (`at`), since an unchanged state isn't pushed (`updates`, `system`).

### Guards and errors
- Every connection's peer must be the same user (`SO_PEERCRED`, `rpc.SamePeerUser`).
- **Shell only**: `ipc.register`, `lock.state` and every compositor method that changes something answer only the connection whose hello was the shell's.
- **Writable**: config writes (`config.replace`, `config.restore`, `config.set`, the `share.*` applies, `saved.restore`) are refused with `incompatible` while the tree's schema isn't the binary's and dev mode is off. `daemon.state` pushes the change.
- The lock screen takes only `lock`: no method unlocks it (`ipc.call` to `lockscreen` is anything but `lock` → `refused`).
- Errors are `{ kind, message, issues }`. `kind` comes from `axerr.Kind` (`invalid_config`, `bad_request`, `conflict`, `takeover_refused`, `incompatible`, `unavailable`, `running`, `not_found`, `refused`, `internal`); messages stay English, and the shell translates by kind.

### Changing the protocol
- **A new method, push or topic** needs no protocol bump: an older peer never calls or hears it. Add the handler (`rpc.Handle` in the daemon part it belongs to), call it through `BackendManager`, and let `scripts/dev/verify.sh` regenerate [rpc.md](../generated/rpc.md). A method the shell picks at runtime goes in a `// rpc: a, b` comment, so the generator sees it.
- **Changing what an existing method or push means** (its params, its result, when it's sent) bumps `protocol` in `config/json/backend.json`. The binary embeds that file, so a mismatched shell and binary refuse each other at the hello and don't misread each other.
