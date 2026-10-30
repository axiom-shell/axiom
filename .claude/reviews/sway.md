# sway
reviewed: b85084b 2026-10-30  (full)

Sound in its core: state, events, SwayFX gating, quoting and the runtime layer's order hold. One bug users hit: after a sway reload nothing hands SwayManager the look again, so `gapsOut` and SwayFX's per-window blur and shadows fall back. Stage 7's Go side adds rare-path bugs in the bind merge, in spaced include paths, in `desc:` output rules and in the managed monitor-conflict check. The deletion pass found about 80 lines to remove.

## Open findings
- Blocker: [After a sway reload, gapsOut and SwayFX's per-window blur and shadows stay off until the look changes](../../docs/dev/issues.md#after-a-sway-reload-gapsout-and-swayfxs-per-window-blur-and-shadows-stay-off-until-the-look-changes)
- Major: [A sway title-bar mouse bind moves in as a whole-window bind](../../docs/dev/issues.md#a-sway-title-bar-mouse-bind-moves-in-as-a-whole-window-bind)
- Major: [A sway exec chained with ; or , moves in as one shell command](../../docs/dev/issues.md#a-sway-exec-chained-with--or--moves-in-as-one-shell-command)
- Major: [A sway include path with a space breaks after a takeover](../../docs/dev/issues.md#a-sway-include-path-with-a-space-breaks-after-a-takeover)
- Major: [A sway output rule by description misses a monitor with no serial](../../docs/dev/issues.md#a-sway-output-rule-by-description-misses-a-monitor-with-no-serial)
- Major: [Managed mode's monitor-conflict check misses quoted and block output lines](../../docs/dev/issues.md#managed-modes-monitor-conflict-check-misses-quoted-and-block-output-lines)
- Major: [The detached layer's unbind list can drift from what sway holds](../../docs/dev/issues.md#the-detached-layers-unbind-list-can-drift-from-what-sway-holds)
- Cleanup: [Small shrinks in SwayManager](../../docs/dev/issues.md#small-shrinks-in-swaymanager)
- Cleanup: [Sway and niri each forward withMainBinds to the daemon](../../docs/dev/issues.md#sway-and-niri-each-forward-withmainbinds-to-the-daemon)
- Cleanup: [SwayConfigBinds keeps its own copy of sway's $variables](../../docs/dev/issues.md#swayconfigbinds-keeps-its-own-copy-of-sways-variables)
- Cleanup: [Small shrinks in the sway writer and IPC](../../docs/dev/issues.md#small-shrinks-in-the-sway-writer-and-ipc)
- Cleanup: [The sway extract's input-device case and isSwayFlag repeat the general rule](../../docs/dev/issues.md#the-sway-extracts-input-device-case-and-isswayflag-repeat-the-general-rule)
- Cleanup: [binds and takeover each keep their own isFile and git check](../../docs/dev/issues.md#binds-and-takeover-each-keep-their-own-isfile-and-git-check)

Minor (not recorded):
- sway-backend.md describes the shell-era writer and misses its biggest files: the `Files:` header (line 3) lacks `backend/internal/compositor/render/sway.go` and `backend/internal/compositor/ipc/sway.go`; line 71 (unbinds are the daemon's `SwayUnbind`, not a `PersistentProperties`), line 69 (`userconf.SwayText`, not the CLI), line 28 (only `window`/`workspace`/`output` re-read the tree), line 92 (Key capture is `SwayManager.captureKeys`).
- A user's floating_modifier on another mod is replaced by axiom's while detached (`render/sway.go:368`). Question for the maintainer: should any user `floating_modifier` but `none` make axiom's drag/resize count as taken?
- swayFiles' comment says sway skips backups that sway's include loads (`binds/sway.go:212`).
- sway's managed include loads every file in user/ (`render/sway.go:683`). Question for the maintainer: `user/*.conf` like the other two compositors?
- Nothing tests the detached layer's send order (`manager/sway.go:225`, `manager/sway_test.go`).

## Contract
Holds:
- **SwayFX:** detection through `get_version` (persisted; retried after 2 s doubling to 60 s; `ready` gates `surfacesReady`). Every SwayFX effect in QML and every SwayFX line in Go is gated on `fx`, and those lines are only ever sent at runtime.
- **`supports`:** the map matches the doc (21 keys plus 5 for SwayFX).
- **Events:** the mapping, the 50 ms debounce with stale-focus protection, the 1.5 s settle read, one listener per singleton generation, and the daemon's reload stream retrying every 2 s.
- **Shapes and primitives:** the shapes, special groups (`specialGroup`, `_specialFrom`, `specialAdopt`), key capture, and `SwayIpcManager`'s order.
- **The runtime layer:** unbinds first, a refused list resent line by line, unbind identity flags, kept presses, and state keyed per `$SWAYSOCK`.
- **Text:** quoting at runtime and in files; `SwayConfigBinds` (blocks, modes, continuations).
- **The files:** `checkLoaded` via `axiom_layer`, and output lines kept until the outputs are read.
- **Claim and release:** claim → release → claim on scratch dirs, atomic writes, relative includes made absolute, the stock example config detected.

## Coverage
Read deeply: SwayManager.qml, SwayState.qml, SwayIpcManager.qml, SwitcherKeys.qml, manager/sway.go, render/sway.go, ipc/sway.go, binds/sway.go, takeover/kinds.go (sway), userconf/sway.go; the sway paths of manager/runtime.go, writer.go, outputs.go, render/keys.go, binds/binds.go, marked.go, takeover/takeover.go and cli/compositor.go. · Outlined: CompositorManager.qml, CompositorConfigManager.qml, HyprlandManager.qml, NiriManager.qml, manager/manager.go, binds/isolate.go. · Skipped: binds/hypr.go, hyprlua.go and niri.go (other audits); nested.sh. No live logs and no nested sway. Live-only: the Blocker's SwayFX half, the `desc:` Unknown match, nested relative includes through a symlinked include.

## History
- 2026-10-19 full: 7 findings (4 major, 3 minor), fixed in 2362cd6.
- 2026-10-19 incremental since a10ba10: 2 findings (1 major, 1 minor); fixed in the commit after 158ac3d.
- 2026-10-30 full (after stage 7; deep): 18 findings (1 blocker, 6 major, 6 cleanups, 5 minor); recorded.
