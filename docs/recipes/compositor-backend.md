# Adding a compositor backend

A compositor backend lets axiom run under another compositor. Hyprland, sway and niri exist today. The shell's side is one QML service that turns the compositor's replies into axiom's neutral shapes, and the daemon's side is a config writer, so axiom can manage the compositor's config. At the end the bar's workspaces, the overview, the dock, the launcher's window search and the settings for the compositor all work through the neutral `CompositorManager`.

**Copy from:**
- `qml/services/compositor/SwayManager.qml` with `SwayIpcManager.qml`, and `NiriManager.qml` (a compositor reached over its own socket). `HyprlandManager.qml` has the same members; they are the contract.
- `qml/components/methods/SwayState.qml` + `tests/tst_SwayState.qml`, with fixtures captured from the real compositor in `tests/fixtures/sway/` (or `NiriState.qml`, `tst_NiriState.qml` and `tests/fixtures/niri/`): the pure code that maps replies to neutral shapes.
- The daemon's side: `backend/internal/compositor/manager/sway.go` or `niri.go`.

**Background:** [the compositor](../dev/compositor/README.md), [contract](../dev/compositor/contract.md), [config modes](../dev/compositor/config-modes.md), [sway backend](../dev/compositor/sway-backend.md), [niri backend](../dev/compositor/niri-backend.md) (files only, with its layer taken from files)

## Files
1. `qml/services/compositor/<Name>Manager.qml`: a `pragma Singleton` with every member in [contract › Backend members](../dev/compositor/contract.md#backend-members) and its `supports`. Leave out the optional members it has no use for (the facade checks for them: `withCursorPos`, `warpCursorToLayer`, `withLayerRects`, `leaveSwitcher`, `scrollStrip`, `applyRemap`, `withMainBinds`, `layersChanged`), and never write an empty stub. Only this file talks to the compositor: its socket, its Quickshell module or its CLI.
2. `qml/components/methods/<Name>State.qml` and `tests/tst_<Name>State.qml`: the compositor's replies turned into the [shapes](../dev/compositor/contract.md#shapes). The service itself holds no parsing.
3. `qml/services/compositor/CompositorManager.qml`: the `backend` line (`kind === "<kind>" ? <Name>Manager : …`), and `nameOf`'s display name. `qml/components/methods/CompositorKind.qml` gets the compositor's socket variable in `names`, which is how `kind` is found.
4. `scripts/check_structure.py`: a row in its `backends` table (the module, CLI and socket only this backend's services may use), so nothing else talks to the compositor.
5. `docs/dev/compositor/<kind>-backend.md`, saying what it supports and how it maps, and a line for it in `docs/dev/README.md`.
6. If axiom manages the compositor's config (`configModes` in `supports`), the daemon's side, described in [config modes › The writers](../dev/compositor/config-modes.md#the-writers):
   - a writer, `backend/internal/compositor/manager/<kind>.go`, implementing the `writer` interface in `writer.go` (its files, texts, runtime layer, `checkLoaded`, `reload`), and chosen in `manager.go`'s `New`;
   - the texts it writes in `backend/internal/compositor/render/<kind>.go`, with test cases;
   - an IPC client with its reload stream in `backend/internal/compositor/ipc/<kind>.go` (the socket variable also goes in `ipc/detect.go`'s `compositorVars`), with fake-socket tests;
   - a takeover `Kind` in `backend/internal/compositor/takeover/kinds.go` (its file, example config, the lines that start axiom, and the marker), with cases in `takeover_test.go`;
   - a bind merge in `backend/internal/compositor/binds/<kind>.go` (it reads and removes binds as the same JSON), with cases in `binds_test.go`.
   `CompositorConfigManager` sends the inputs the writer reads (`compositor.inputs`).

## Steps
1. Read the contract and your closest model backend, and capture the compositor's real replies as fixtures.
2. Write `<Name>State` and its test against the fixtures.
3. Write the `<Name>Manager` service from the contract's members, listing in `supports` only what the compositor really does.
4. Hook it into `CompositorManager` and `CompositorKind`, add the `check_structure` row, and try it in `scripts/dev/nested.sh <kind>`.
5. Add the daemon's writer, IPC client, takeover kind and bind merge, if config modes apply.
6. Write the backend's doc.

## Watch out for
- **No compositor objects past the backend.** Hand out snapshots. A binding on a list of live objects re-evaluates on every event, and the next backend's objects won't have the same fields.
- **A capability not listed is false.** List only what the backend really does; the facade and the settings hide the rest. Never gate anything on `kind` outside the backend; use `CompositorManager.supports.<key>`.
- **The facade keeps the layout logic.** Workspace ids, blocks, steps, wrapping and the remap plan are `CompositorManager`'s. A backend that wants to know "which workspace is next" is duplicating it.
- **Workspace ids** are axiom's numbers (`WorkspacesConfig`), not the compositor's internal ids.
- **Setting the compositor up** (binds, window look, input, monitors, the three modes) is the daemon's. The writer only turns the layer into text and runs it, and the manager drives the modes. The backend's `layerApplied()` reads back what it follows after the daemon changed the compositor at runtime.
- **Don't start the backend's processes unless `CompositorManager.kind` picked it.** The singleton is created lazily, but anything that names it creates it.
- **Never try the config modes on your real config.** Use a nested session (`scripts/dev/nested.sh <kind> --managed`) or scratch folders.

## Check it
- `scripts/run_tests.sh <Name>State`, then `scripts/dev/verify.sh`.
- For the daemon's side: `go -C backend test ./internal/compositor/...`, which includes the golden files each writer produces (`manager/golden_test.go`; `-update` only for a change meant to reach users' configs).
- `scripts/dev/nested.sh <kind>`: the bar's workspaces follow switches, the overview shows windows, the dock lists running apps, the launcher finds windows, and the log (`scripts/log.sh`) is clean.
- Back on the live shell, the log is still clean.

## Docs to update
- `docs/dev/compositor/<kind>-backend.md` (new), the Capabilities table in [contract](../dev/compositor/contract.md) if you added a capability, and `docs/dev/README.md`.
- `docs/features.md` (Your compositor) and the README's list of supported compositors.
