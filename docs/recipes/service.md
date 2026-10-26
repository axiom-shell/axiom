# Recipe: a new service (`*Manager`)

> **Use when:** a feature needs state, a process, polling, file writes or Hyprland dispatches. UI never does those itself.
> **Copy from:**
> - `services/system/TailscaleManager.qml` with `backend/internal/tailscale/`: polled state through a `ConsumerRegistry`, fetched by axiom (a polled topic); its consumer is `components/bar/widgets/Tailscale/Tailscale.qml`. The preferred shape for anything polled.
> - The skeleton below: the same API polled in QML, its command through `CommandManager.run`, for what can't move to the daemon yet.
> - `services/session/IdleManager.qml`: an IPC handler, state kept across reloads in `PersistentProperties`, and a daemon push (`idle.state`).
> **Docs:** [services-pattern](../dev/core/services-pattern.md), `services/AGENTS.md`, generated API `docs/dev/generated/api/<Name>.md`

## Files to touch
1. `services/<group>/<Name>Manager.qml` (the group by `services/AGENTS.md` › Folders): a `pragma Singleton` (`QtObject`, or Quickshell's `Singleton` when it holds child objects like `PersistentProperties`).
2. Its consumers: widgets, modules, other services.
3. `shell.qml` → `_services`: only if nothing else references it (e.g. it exists only for IPC or a background job).
4. `docs/usage.md` → the IPC targets table, if it has an `IpcTarget`.

## Skeleton
```qml
pragma Singleton
import QtQuick

// One or two sentences: what this owns and who uses it.
QtObject {
  id: root

  // Public state: readonly where consumers must not write it
  property bool available: false
  property string state: ""

  // request: { interval } (ms)
  function acquire(owner, request) {
    _registry.acquire(owner, {
      "interval": request?.interval ?? 10000
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  function refresh() {
    if (root._checking)
      return;
    root._checking = true;
    CommandManager.run(["sh", "-c", "command -v foo >/dev/null || exit 127; foo status --json"], (exitCode, out) => {
      root._checking = false;
      root.available = exitCode !== 127;
      let status = null;
      try {
        status = JSON.parse(out);
      } catch (e) {}
      root.state = status?.State ?? "";
    });
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  readonly property int _interval: _registry.active ? Math.max(5000, Math.min(..._registry.requests.map(r => r.interval))) : 10000

  property Timer _timer: Timer {
    interval: root._interval
    running: root._registry.active
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  property bool _checking: false

  property IpcTarget _ipc: IpcTarget {
    target: "foo"

    function refresh(): void {
      root.refresh();
    }

    function status(): string {
      return root.state;
    }
  }
}
```
Consumer (the request comes from config only, never from live values):
```qml
  readonly property var fooRequest: ({
      "interval": root.properties.interval
    })
  onFooRequestChanged: FooManager.acquire(root, fooRequest)
  Component.onCompleted: FooManager.acquire(root, fooRequest)
  Component.onDestruction: FooManager.release(root)
```

## Steps
1. Name it `<Domain>Manager`. Never shadow a Quickshell singleton (`NetworkingManager`, not `Networking`).
2. Put the public API first (state, functions, signals) and the private parts after `// -- Private --`, prefixed `_`.
3. **Polled data:** use a private `ConsumerRegistry`.
   - **Polled by axiom** (preferred): a `topics.Source{Name, Floor, Default, Fetch}` in a package of its own under `backend/internal/`, listed in `backend/internal/daemon/topics.go`. The service sends the merged request with `BackendManager.acquire(topic, …)` while `_registry.active` (`release(topic)` once not) and fills its state from `BackendManager.listen("<topic>.state", …)`: copy `TailscaleManager.qml`. The floor lives in Go ([protocol](../dev/backend/protocol.md) › Polled topics).
   - **Polled in QML** (the skeleton): the interval is the shortest one asked for, with a floor; the timer runs only while `_registry.active`, so nothing is fetched with no consumers.
4. **IPC:** a `property IpcTarget _ipc` with typed functions (`(): void`, `(): string`, `(text: string): void`). Per-screen handlers live on the surface instead, `enabled: ShellManager.isTarget(…)`.
5. **Processes and files:** no `Process`, `FileView`, `Socket`, `IpcHandler` or `Quickshell.execDetached` of its own (`check_structure` refuses them outside `scripts/quickshell-io-allowlist.json`, a list that only shrinks as these move to the axiom daemon). Use `CommandManager.run` / `runDetached`, `FileManager.read`, `StateManager` for small state, and a daemon method for anything else (a file to watch or write, a socket).
6. **Persistence:**
   - State that must survive a QML reload goes in `PersistentProperties` (needs a `Singleton` root, see `IdleManager`).
   - Small state that must survive a restart goes in `StateManager` (`~/.local/state/axiom/ui/*.json`) or `Paths.userStatePath`, written atomically (temp file + rename).
7. **Config:** read it through readers. Write it only through `ConfigManager` / `SettingsManager`.
8. Add it to `shell.qml`'s `_services` if nothing else references it, or it never gets created.

## Gotchas
- **Greeter:** a side effect reachable from the greeter (writes, integrations, network) checks `Paths.greeter` first, as `CalendarManager` does.
- **Secrets** go through `SecretsManager` (stdin), never argv or config.json.
- **Hyprland:** only the `Hyprland*` services talk to it; anything else asks `HyprlandManager` (Lua through `runLua`, workspace and window focus through its functions). See [IPC](../dev/hyprland/ipc.md).
- **Requests:**
  - An identical re-`acquire` is a no-op, but a new object every sample churns every binding on `requests`.
  - Build requests from config only. Never key a Repeater model on live values (the 25 GB lesson).
- **`check_structure.py`** errors on a `<Name>Manager.` reference with no `services/*/<Name>Manager.qml`, and on near-miss names.
- **Hot reload:** a new singleton is picked up on reload, and its timer starts again, so make `refresh()` idempotent (the skeleton's `_checking`).
- **Showing `show`:** `show` is a qs IPC keyword (`ipc call foo show` lists functions), so don't name a function `show`.

## Verify
- `scripts/dev/verify.sh`: structure, formatting, generated API and IPC docs, and the log since the reload.
- `qs -c axiom ipc call <target> <function>` for each IPC function. `docs/dev/generated/ipc.md` lists it after `scripts/gen_docs.py`.
- `scripts/log.sh --debug` while a consumer is shown: the process runs at the expected interval and stops when the consumer goes.

## Docs to update
- `docs/dev/features/<feature>.md` (new or existing) and its line in `docs/dev/README.md`. If it's polled, add it to the polled list in `docs/dev/core/services-pattern.md`.
- `docs/usage.md` → IPC targets table, for a new IPC target.
