# Recipe: a compositor backend

> **Use when:** axiom should run under another compositor (sway, niri, …).
> **Copy from:**
> - `services/compositor/SwayManager.qml` (+ `services/compositor/SwayIpcManager.qml`): the closest model for a backend that isn't Hyprland; `HyprlandManager.qml` has the same members (the contract).
> - `components/methods/SwayState.qml` + `tests/tst_SwayState.qml` (fixtures captured from the compositor in `tests/fixtures/sway/`): the compositor's replies to neutral shapes.
> **Docs:** [The compositor](../dev/compositor/README.md), [contract](../dev/compositor/contract.md), [sway-backend](../dev/compositor/sway-backend.md), [niri-backend](../dev/compositor/niri-backend.md) (a compositor reached over its own socket, taking its layer from files only)

## Files to touch
1. `services/compositor/<Name>Manager.qml`: a `pragma Singleton` (Quickshell's `Singleton`) with every member in [contract.md › Backend members](../dev/compositor/contract.md#backend-members) and its `supports`. Only this file talks to the compositor (its socket, its Quickshell module, its CLI).
2. `components/methods/<Name>State.qml` + `tests/tst_<Name>State.qml`: the compositor's replies as the [shapes](../dev/compositor/contract.md#shapes). The service holds no parsing.
3. With config modes, in the daemon ([config-modes.md › The writers](../dev/compositor/config-modes.md#the-writers)): a writer `backend/internal/compositor/manager/<kind>.go` (copy `sway.go`: the `writer` interface, its files, texts, runtime layer, `checkLoaded` and reload), picked in `manager.go` by its socket's env var; its texts in `backend/internal/compositor/render/<kind>.go` with test cases; an IPC client with its reload stream in `backend/internal/compositor/ipc/` (fake-socket tests in `ipc_test.go`). For managed mode: a takeover `Kind` in `backend/internal/compositor/takeover/kinds.go` (copy `sway`'s: its file, example config, the lines starting axiom, the marker) with its cases in `takeover_test.go`, and a merge in `backend/internal/compositor/binds/` (copy `sway.go`: the same JSON) with its cases in `binds_test.go`. `CompositorConfigManager` sends the inputs the writer reads (`compositor.inputs`).
4. `services/compositor/CompositorManager.qml`: `kind` (its socket's env var, if not there yet) and `backend` (`kind === "<kind>" ? <Name>Manager : …`).
5. `scripts/check_structure.py`: a row in its `backends` table (what talks to the compositor: its module, CLI, socket and services), so only its own services do.
6. `docs/dev/compositor/`: a `<kind>-backend.md` with what it supports and how it maps, and a line in `docs/dev/README.md`.

## Gotchas
- **No compositor objects past the backend.** Hand out snapshots. A binding on a list of live objects re-evaluates on every event, and the next backend's objects won't have the same fields.
- **A capability not listed is false.** List only what the backend really does; the facade and the settings hide the rest. Don't gate anything on `kind` outside the backend.
- **The facade keeps the layout logic.** Workspace ids, blocks, steps, wrap and the remap plan are `CompositorManager`'s. A backend that wants to know "which workspace is next" is duplicating it.
- **Workspace ids** are axiom's numbers (`WorkspacesConfig`), not the compositor's internal ids.
- **Setting the compositor up** (binds, window look, input, monitors, the three modes) is the daemon's: a Go writer in `manager/` with its texts in `render/`, and `configModes` in the backend's `supports` ([config modes](../dev/compositor/config-modes.md) › The writers). The manager drives the modes; the writer only turns the layer into text and runs it. The backend's `layerApplied()` reads back what it follows after the daemon changed the compositor at runtime.
- Don't start the backend's processes unless `CompositorManager.kind` picked it: it's created lazily, but anything that names it creates it.

## Verify
- `scripts/run_tests.sh <Name>State`, then `scripts/dev/verify.sh`.
- `scripts/dev/nested.sh <kind>`: the bar's workspaces follow switches, the overview shows windows, the dock lists running apps, the launcher finds windows, and the log is clean.
- Back on the live (Hyprland) shell, the log is still clean: `scripts/log.sh`.
