# Adding a service (`*Manager`)

A service is a singleton that owns one domain's state and every side effect that goes with it: running commands, polling, writing files, answering IPC. The UI reads a service and never does those things itself. At the end you have `qml/services/<group>/<Name>Manager.qml` and whatever uses it.

**Copy from:**
- `qml/services/apps/TailscaleManager.qml` with `backend/internal/tailscale/`: state polled by the axiom daemon through a `ConsumerRegistry`; the consumer is `qml/components/bar/widgets/Tailscale/Tailscale.qml`. This is the preferred shape for anything polled.
- `qml/services/session/IdleManager.qml`: an `IpcTarget`, state kept across reloads in `PersistentProperties`, and a daemon push (`idle.state`).
- The skeleton below: the same API polled in QML, with its command through `CommandManager.run`, for what the daemon doesn't poll.

**Background:** [services-pattern](../dev/core/services-pattern.md), generated API in `docs/dev/generated/api/<Name>.md`

## Files
1. `qml/services/<group>/<Name>Manager.qml`: a `pragma Singleton` `QtObject`, or Quickshell's `Singleton` when it holds child objects such as `PersistentProperties`. Each folder is its own QML module:
   - `core/`: what everything stands on (config, theme, the daemon bridge and its `CommandManager`, `FileManager`, `StateManager`, `IpcTarget`, `ConsumerRegistry`, secrets).
   - `compositor/`: `CompositorManager` and each backend's files.
   - `session/`: locking, auth, greeter, polkit, idle, session actions.
   - `system/`: the machine's basics (audio, network, Bluetooth, battery, media, notifications, updates).
   - `ui/`: state of the shell's own surfaces and editors.
   - `apps/`: optional features and outside integrations (calendar, weather, Tailscale).
2. Its consumers: widgets, modules, other services.
3. `qml/shell.qml` → `_services`, only if nothing else references it (it exists for IPC or a background job); otherwise it is never created.
4. `docs/usage.md` → the IPC targets table, if it has an `IpcTarget`.

## Skeleton
```qml
pragma Singleton
import QtQuick

import qs.services.core

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
    }, undefined, true);
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
The consumer builds its request from config only, never from live values:
```qml
  readonly property var fooRequest: ({
      "interval": root.properties.interval
    })
  onFooRequestChanged: FooManager.acquire(root, fooRequest)
  Component.onCompleted: FooManager.acquire(root, fooRequest)
  Component.onDestruction: FooManager.release(root)
```

## Steps
1. Name it `<Domain>Manager`, and don't shadow a Quickshell singleton (`NetworkingManager`, not `Networking`).
2. Put the public API first (state, functions, signals) and the private parts after `// -- Private --`, prefixed `_`.
3. Polled data uses a private `ConsumerRegistry`:
   - Polled by the daemon (preferred): a `topics.Source{Name, Floor, Default, Fetch}` in a package of its own under `backend/internal/`, listed in `backend/internal/daemon/topics.go`. The service sends the merged request with `BackendManager.acquire(topic, …)` while `_registry.active` (and `release(topic)` when not) and fills its state from `BackendManager.listen("<topic>.state", …)`. Copy `TailscaleManager.qml`. The floor lives in Go ([protocol](../dev/backend/protocol.md) › Polled topics).
   - Polled in QML (the skeleton): the interval is the shortest one asked for, with a floor, and the timer runs only while `_registry.active`, so nothing is fetched with no consumer.
4. IPC is a `property IpcTarget _ipc` with typed functions (`(): void`, `(): string`). Parameters are `string`, since arguments arrive as text (`check_structure` enforces it); read a number through `_int(text)`, which answers a word with `bad_request`. A handler that belongs to one screen lives on that surface instead, with `enabled: ShellManager.isTarget(…)`.
5. Processes and files go through the daemon's helpers: `CommandManager.run` / `runDetached`, `FileManager.read` / `write` / `watch`, `StateManager` for small state. A socket or anything else is a daemon method. Only the four files in `scripts/quickshell-io-allowlist.json` may use `Process`, `FileView`, `Socket` or `Quickshell.execDetached` directly, and the check fails a use anywhere else.
6. Persistence:
   - State that must survive a QML reload goes in `PersistentProperties`, as a default child of a `Singleton` root (see `IdleManager`).
   - Small state that must survive a restart goes in `StateManager` (`~/.local/state/axiom/ui/*.json`) or `Paths.userStatePath`, written atomically (temp file and rename).
7. Config is read through the readers and written only through `ConfigManager` or `SettingsManager`.
8. Add it to `_services` if nothing else references it.

## Watch out for
- **The greeter.** A side effect it can reach (writes, integrations, network) checks `Paths.greeter` first, as `CalendarManager` does. The greeter runs data, never code.
- **Secrets** go through `SecretsManager` (stdin), never argv or config.json.
- **The compositor** is reached only through `CompositorManager`, in neutral shapes: workspace and window focus through its `goToWorkspace`, `stepWorkspace`, `nthWorkspace` and `focusWindow`. Only the `Hyprland*`, `Niri*` and `Sway*` backend files talk to a compositor ([compositor/README](../dev/compositor/README.md)). Gate on `CompositorManager.supports.<key>`, never on which compositor it is.
- **Requests.** An identical re-`acquire` is a no-op, but a new object on every sample churns every binding on `requests`. Build requests from config only, and never key a Repeater model on live values: that once pushed qs past 25 GB.
- **Names are checked.** `check_structure` errors on a `<Name>Manager.` reference with no matching file and on near-miss names.
- **Reloads** pick up a new singleton and start its timer again, so make `refresh()` idempotent (the skeleton's `_checking`).
- **One-tap actions** (toggles, session actions) are rows of the action catalogue, and the UI runs them through `ActionsManager.run`. A service that adds one also adds its table row ([actions](../dev/core/actions.md)).

## Check it
- `scripts/dev/verify.sh`: structure, formatting, the generated API and IPC docs, and the log since the reload.
- `axiom ipc <target> <function>` for each IPC function; `docs/dev/generated/ipc.md` lists them after `scripts/gen_docs.py`.
- `scripts/log.sh --debug` while a consumer is shown: the process should run at the expected interval and stop when the consumer goes.

## Docs to update
- `docs/dev/features/<feature>.md` (new or existing) and its line in `docs/dev/README.md`. If it is polled, add it to the polled list in [services-pattern](../dev/core/services-pattern.md).
- `docs/usage.md` → the IPC targets table, for a new IPC target.
