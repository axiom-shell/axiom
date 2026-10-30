# niri
reviewed: 028e7ea 2026-10-30  (full)

The niri backend is in good shape: the event stream, the reducer and the primitives match the docs, the stream rebuilds state from niri's full-state events on every (re)connect, and the tests never reach a live niri. Its biggest problem is at the seam: the daemon picks its compositor by environment-variable order, not the one running as the shell does, so a stale variable sends the writer and the outputs to the wrong compositor. Two rarer bugs (the user's `blur { off }` overriding axiom's blur, a failed start reading as loaded) and six deletion-pass cleanups (about 150 lines).

## Open findings
### 1. The daemon picks the compositor by variable order, not the one running  `backend/internal/compositor/manager/manager.go:136`
(Major) `manager.New`, `OutputsFromEnv` and `applyGreeter` take the first of `HYPRLAND_INSTANCE_SIGNATURE`, `NIRI_SOCKET` and `SWAYSOCK` that's set; the shell's `CompositorKind` takes the one still running. Under niri with a stale Hyprland variable, the daemon writes Hyprland's files and applies outputs to Hyprland's gone socket.
**Fix:** a Go `CompositorKind` (candidates checked through `/proc/<pid>/comm`), used by all three. Recorded in issues.md, folded into the compositor audit's entry "The daemon picks a compositor the shell may not run under".

### 2. A user's blur off overrides axiom's blur on niri  `backend/internal/compositor/render/niri.go:462`
(Major, rare) `NiriLookNodes` writes passes/offset/noise but never `blur { on }`, so a user's `blur { off }` wins; `NiriInfo` (`userconf/niri.go:416`) ignores `on`. `niri validate` 26.04 accepts `blur { on }`.
**Fix:** write `blur.on` when axiom's blur is on; `NiriInfo` takes the last of on/off. Recorded.

### 3. niri started on a broken config reads as loaded  `backend/internal/compositor/ipc/niri.go:113`
(Major, PLAUSIBLE) `Reloads` drops the first `ConfigLoaded` with its `failed`, so `niriWriter.lastFailed` misses a failed start and managed `checkLoaded` says loaded while niri runs its defaults. Confirm in nested niri with a broken `user/*.kdl`.
**Fix:** hand the first event's `Failed` over as initial state. Recorded.

### 4. Nothing reads userBindsRead or lastLoadFailed  `services/compositor/CompositorConfigManager.qml:77`
(Cleanup) Dead QML property, Go interface method always true on all three writers; `NiriManager.lastLoadFailed` unread. ~11 lines. Recorded.

### 5. The niri writer's runtimeOn and unread-binds guards are dead  `backend/internal/compositor/manager/niri.go:34`
(Cleanup) `runtimeOn` written, never read; `userEntries == nil` guards unreachable after `newNiri`. ~12 lines. Recorded.

### 6. Three listings of niri's user files  `backend/internal/compositor/manager/niri.go:166`
(Cleanup) `userFiles`, `binds.niriFiles`, `takeover` niri `left` list `user/*.kdl` three ways and disagree on hidden and symlinked files. One `userconf` helper, ~25 lines saved. Recorded.

### 7. RunningNested has its own niri socket client  `backend/internal/compositor/userconf/niri.go:212`
(Cleanup) Use `ipc.Niri.Outputs`; 28 → ~8 lines. Recorded.

### 8. NiriManager queues actions the daemon could order  `services/compositor/NiriManager.qml:561`
(Cleanup) A `niri.command` method under `reg.InOrder` replaces the QML queue (~30 lines) and its per-action round trip. Recorded.

### 9. A second KDL writer in the kdl package  `backend/internal/compositor/kdl/kdl.go:505`
(Cleanup) `ValueText`/`PyFloat`/`NodeText`/`Str` duplicate `render`'s KDL writer with Python-port spellings; ~50 lines. Recorded.

### Minor (report only, not recorded)
- `docs/dev/compositor/niri-backend.md` › supports: the "Not:" list omits `layerFrameSync` (the code's comment and issues.md name it).
- `userconf.startedWith` (`userconf/niri.go:57`): a relative `-c` is resolved against the daemon's cwd, not niri's (`/proc/<pid>/cwd`).
- `tests/tst_NiriState.qml`: no rows for `KeyboardLayoutSwitched` (before and after `KeyboardLayoutsChanged`), `WorkspaceUrgencyChanged`, `WindowUrgencyChanged`, or a `ConfigLoaded` with `failed: true`.

## Contract
Holds: one connection per request, actions queued in order, state requests at once; `niri.watch` per connection, a second watch keeps the stream, retried a second after a drop, `Forget` on close (daemon.go, greeter.go); the stream's first `ConfigLoaded` isn't a reload (shell and daemon); state rebuilt by `WorkspacesChanged`/`WindowsChanged`/`KeyboardLayoutsChanged` replacing, not patching; outputs read on start, after debounced workspace changes and screen changes, hotplug by the set of names; `reserved` from LayerManager, replaced only on change; workspace ids block base + idx − 1, -1 past the block; windows' column/tile/cover/fullscreen as documented; keyboard short codes; gaps/struts/modKey/blur from `axiom compositor niri info --config <runningConfig>`, last read wins; every primitive (travel, focusOutput, moveWindowToOutput, placeWindow, resizeWindow, overview, exitSession, the null/no-op ones) as niri-backend.md says; supports list matches the doc except the Minor; no compositor-name gating outside the compositor services (NoParentNotice's per-kind hint and DependencyManager's tool `compositors` only); the writer's files, paths, validation (includes stripped, skipped without niri), detached wrapper keyed by socket, included `end` placement, managed user includes in name order, hot corners off in managed; the merge's action tables and kept-bind rules; the takeover's niri kind (axiom lines, relative includes made absolute); no test reads the real `NIRI_SOCKET`.

## Coverage
Read deeply: services/compositor/NiriManager.qml, components/methods/NiriState.qml, backend/internal/compositor/ipc/niri.go, ipc/niristreams.go, daemon/compositorsocket.go, manager/niri.go, binds/niri.go, userconf/niri.go (lines 37–461). Outlined: services/compositor/CompositorManager.qml (niri lines, seams), kdl/kdl.go (writer half read, parser outlined), takeover/kinds.go (niri kind read), manager/manager.go (`New`, `configReloaded`, `watchReloads`), render/niri.go (serializer, blur, outputs), tests/tst_NiriState.qml (test names, fixture event kinds). Skipped: scripts/dev/nested.sh (guardrails' and sway's; nothing needed it), the kdl parser's grammar, render's frozen cases. Not run: nested niri (finding 3 stays PLAUSIBLE); the live session is sway.

## History
- 2026-10-30 full: 9 findings (3 Major, 6 Cleanup) plus 3 Minor; recorded in issues.md (via the row 19 batch)
