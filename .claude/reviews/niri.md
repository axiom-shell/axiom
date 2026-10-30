# niri
reviewed: 9c58b36 2026-10-30  (full)

Unchanged since batch 1 and still in good shape at its core (event stream, reducer, primitives, writer). Batch 1's nine findings stay open. The re-audit's wider scope adds the bind actions package: unlisted IPC calls move in as toggles, and niri's merge turns a confirming `quit` into an instant log out.

## Open findings
- Major: [The daemon picks a compositor the shell may not run under](../../docs/dev/issues.md#the-daemon-picks-a-compositor-the-shell-may-not-run-under)
- Major: [A user's blur off overrides axiom's blur on niri](../../docs/dev/issues.md#a-users-blur-off-overrides-axioms-blur-on-niri)
- Major: [niri started on a broken config reads as loaded](../../docs/dev/issues.md#niri-started-on-a-broken-config-reads-as-loaded)
- Major: [An unknown IPC function word merges as a toggle](../../docs/dev/issues.md#an-unknown-ipc-function-word-merges-as-a-toggle)
- Major: [niri's confirming quit moves in as an instant log out](../../docs/dev/issues.md#niris-confirming-quit-moves-in-as-an-instant-log-out)
- Cleanup: [Nothing reads userBindsRead or lastLoadFailed](../../docs/dev/issues.md#nothing-reads-userbindsread-or-lastloadfailed)
- Cleanup: [The niri writer's runtimeOn and unread-binds guards are dead](../../docs/dev/issues.md#the-niri-writers-runtimeon-and-unread-binds-guards-are-dead)
- Cleanup: [Three listings of niri's user files](../../docs/dev/issues.md#three-listings-of-niris-user-files)
- Cleanup: [RunningNested has its own niri socket client](../../docs/dev/issues.md#runningnested-has-its-own-niri-socket-client)
- Cleanup: [NiriManager queues actions the daemon could order](../../docs/dev/issues.md#nirimanager-queues-actions-the-daemon-could-order)
- Cleanup: [A second KDL writer in the kdl package](../../docs/dev/issues.md#a-second-kdl-writer-in-the-kdl-package)
- Outside: [The Hyprland and sway bind merges each skip half of compositor/actions](../../docs/dev/issues.md#the-hyprland-and-sway-bind-merges-each-skip-half-of-compositoractions)

### Minor (report only, not recorded)
- `docs/dev/compositor/niri-backend.md` › supports: the "Not:" list omits `layerFrameSync`.
- `userconf.startedWith`'s relative `-c`: filed by the compositor audit as [A relative -c is read from the daemon's folder](../../docs/dev/issues.md#a-relative--c-is-read-from-the-daemons-folder).
- `tests/tst_NiriState.qml`: no rows for `KeyboardLayoutSwitched` (before and after `KeyboardLayoutsChanged`), `WorkspaceUrgencyChanged`, `WindowUrgencyChanged`, or a `ConfigLoaded` with `failed: true`.
- `binds/niri.go` (`niriHarmless`): `cooldown-ms` on a non-wheel key is dropped on a move.
- `kdl.go` (`multiline`): KDL 2 `"""` strings' escapes aren't processed.

## Contract
Holds: one connection per request, actions queued in order, state requests at once; `niri.watch` per connection, a second watch keeps the stream, retried a second after a drop, `Forget` on close; the stream's first `ConfigLoaded` isn't a reload; state rebuilt by `WorkspacesChanged`/`WindowsChanged`/`KeyboardLayoutsChanged` replacing, not patching; outputs read on start, after debounced workspace changes and screen changes, hotplug by the set of names; `reserved` from LayerManager; workspace ids block base + idx − 1, -1 past the block; windows' column/tile/cover/fullscreen as documented; gaps/struts/modKey/blur from `niri info`; every primitive as niri-backend.md says; supports list matches the doc except the Minor; no compositor-name gating outside the compositor services; the writer's files, paths, validation, detached wrapper keyed by socket, included `end` placement, managed user includes in name order, hot corners off in managed; the takeover's niri kind; `compositor/actions` builds IPC patterns from `table.json` alone; the KDL parser covers quoted, raw, multi-line strings, slashdash, nested comments, continuations, KDL 2 keywords; `nested.sh niri` isolates its compositor variables, XDG folders and D-Bus; no test reads the real `NIRI_SOCKET`.

## Coverage
Read deeply (2026-10-30 full, batch 3): actions/actions.go (table.json, actions_test.go by grep), binds/niri.go, kdl/kdl.go parser, takeover/kinds.go niri kind, scripts/dev/nested.sh niri path. Batch 1 (028e7ea, unchanged since): NiriManager.qml, NiriState.qml, ipc/niri.go, ipc/niristreams.go, daemon/compositorsocket.go, manager/niri.go, userconf/niri.go, kdl writer. Outlined: CompositorManager.qml (seams), render/niri.go (serializer, blur, outputs, exitSession). Not run: nested niri.

## History
- 2026-10-30 full: 9 findings (3 Major, 6 Cleanup) plus 3 Minor; recorded in issues.md (via the row 19 batch)
- 2026-10-30 full (batch 3, scope grew to compositor/actions and nested.sh): 2 new Major plus 1 outside the system, 2 new Minor; batch 1's 9 still open; recorded via the row 19 batch 3
