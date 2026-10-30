# hyprland
reviewed: 9c58b36 2026-10-30  (full, re-audit with the corrected scope)

The Hyprland backend holds its contract on the main paths: only the `Hyprland*` services import Quickshell.Hyprland or send `hl.*`, the writer and runtime layer render from one table, user strings reaching Lua are quoted, the takeover's refusals, record, lock and atomic writes hold, and the isolated bind extract classifies memory deaths as documented. Its weak spots are rare and failure paths and the views: the Hyprland bind merge maps IPC binds to exec and removes by bare line number (sway and niri do neither), a claim can comment out axiom's start line inside a Lua long string, the overview can stick "open" after its monitor goes, and the Keybinds page has several state slips (lookup under a stale search, typed inspector text missing Save, the key map selecting hidden binds, renaming the wrong preset). Batch 1: 16 major, 11 cleanups; this re-audit: 13 major, 7 cleanups, 7 minor.

## Open findings
Batch 1's 27 (recorded 2026-10-30; recheck each by its `Where` in docs/dev/issues.md): the trial monitor Apply that turns a monitor off; a reload during a trial Apply; restoring a saved keybind preset; Keybinds page stale after a detached Save; bind merge deleting an hl.bind inside a helper; removing an hl.unbind whether or not its bind went; a failed profile apply never retried; one refused line stopping an eval; a user/ file with a dot; a moved raw bind with a Lua keyword key; a failed options read zeroing gaps; a slide throwing when animations go off; direct dispatches overtaking queued Lua; two recordings within 30 s; two reference paths dropping binds; the monitor prompt's bare padding; and cleanups (HyprlandManager members, `compositorSwitcher` reader, section parsed three ways, KeybindManager tables, strips repeating ActiveStrip's loader, catch-all monitor line, exit command twice, `noteReload`, Go dead helpers, bind helpers' JS halves, stale doc lines).

This re-audit's, recorded:
- Major: [The Hyprland and sway bind merges each skip half of compositor/actions](../../docs/dev/issues.md#the-hyprland-and-sway-bind-merges-each-skip-half-of-compositoractions)
- Major: [Hyprland's remove deletes whatever hl.bind is on a site's line now](../../docs/dev/issues.md#hyprlands-remove-deletes-whatever-hlbind-is-on-a-sites-line-now)
- Major: [A claim comments out axiom's start inside a long string, breaking the script](../../docs/dev/issues.md#a-claim-comments-out-axioms-start-inside-a-long-string-breaking-the-script)
- Major: [An unknown IPC function word merges as a toggle](../../docs/dev/issues.md#an-unknown-ipc-function-word-merges-as-a-toggle)
- Major: [The overview stays open with nothing shown after its monitor goes away](../../docs/dev/issues.md#the-overview-stays-open-with-nothing-shown-after-its-monitor-goes-away)
- Major: [Wide active is hidden in the perMonitor layout but still applies there](../../docs/dev/issues.md#wide-active-is-hidden-in-the-permonitor-layout-but-still-applies-there)
- Major: [A combo lookup says nothing holds a key the search or chips hide, and offers to bind it](../../docs/dev/issues.md#a-combo-lookup-says-nothing-holds-a-key-the-search-or-chips-hide-and-offers-to-bind-it)
- Major: [The bind inspector's typed label and argument miss Save](../../docs/dev/issues.md#the-bind-inspectors-typed-label-and-argument-miss-save)
- Major: [Picking a key in the key map under an edit search selects a bind the list doesn't show](../../docs/dev/issues.md#picking-a-key-in-the-key-map-under-an-edit-search-selects-a-bind-the-list-doesnt-show)
- Major: [Renaming a saved preset after switching presets renames the wrong one](../../docs/dev/issues.md#renaming-a-saved-preset-after-switching-presets-renames-the-wrong-one)
- Major: [The reference's sections and both chip rows are built while hidden](../../docs/dev/issues.md#the-references-sections-and-both-chip-rows-are-built-while-hidden)
- Major: [In the standard layout, a switch past `count` slides through an unrelated workspace](../../docs/dev/issues.md#in-the-standard-layout-a-switch-past-count-slides-through-an-unrelated-workspace)
- Major: [Where the compositor can't mirror, a profile's mirror can't be turned off or its monitor placed](../../docs/dev/issues.md#where-the-compositor-cant-mirror-a-profiles-mirror-cant-be-turned-off-or-its-monitor-placed)
- Cleanup: [The workspace strips' panel property is never read](../../docs/dev/issues.md#the-workspace-strips-panel-property-is-never-read)
- Cleanup: [Three copies of the wheel-notch accumulator](../../docs/dev/issues.md#three-copies-of-the-wheel-notch-accumulator)
- Cleanup: [The key map and the keyboard reference each carry the same modifier chips and legend](../../docs/dev/issues.md#the-key-map-and-the-keyboard-reference-each-carry-the-same-modifier-chips-and-legend)
- Cleanup: [A reference section's folded count re-derives BindRows.byModifiers' grouping](../../docs/dev/issues.md#a-reference-sections-folded-count-re-derives-bindrowsbymodifiers-grouping)
- Cleanup: [PresetSheet defers its re-choose a tick for a config that updates at once](../../docs/dev/issues.md#presetsheet-defers-its-re-choose-a-tick-for-a-config-that-updates-at-once)
- Cleanup: [The bind list's flag icons carry tooltip strings nothing shows](../../docs/dev/issues.md#the-bind-lists-flag-icons-carry-tooltip-strings-nothing-shows)
- Cleanup: [A reference section's title is worked out twice](../../docs/dev/issues.md#a-reference-sections-title-is-worked-out-twice)

Unrecorded (Minor, in report.md in full):
- Minor: An isolated extract's timeout reads "reading the binds: axiom: reading the binds took too long…"
- Minor: The merge's `crashed` reason isn't in the binds package's list
- Minor: bind-merge.md's Files header names manager/hypr.go, not manager.go
- Minor: The two bar strips' wheels step by different rules
- Minor: Workspace docs: showEmpty's default and the strip members' owner
- Minor: A tall key's corner label sits a bare 4 px in
- Minor: The 10-bit switch shows where nothing applies it, and the contract says monitorColor covers it

Notes on filed entries (from this re-audit, not refiled): the Monitors inspector's Primary switch is a common trigger for "Saving a profile that names a new monitor can move other monitors' blocks"; the trial-Apply fix should also register MonitorPromptWindow as modal in `Component.onCompleted`; the dot-name fix should skip hidden user/ files.

## Contract
Holds: C1, C2, C4; C3 on the main path (but see the Hyprland site check and batch 1's helper/unbind entries). Binds: B2–B4, B9, B12 (codes handled; `crashed` missing from the package comment), B13; isolated extract classification pinned by `TestDiedOfMemory`. Takeover: T1 (lock across claim and managed write, released before merge), T2, T5–T8; `luacheck.WholeLines`/`CodeOnly` on escapes, long brackets, EOF. IPC I1–I4, I6, I7, W2, W5, W6, W9; monitors M1–M7 (bit depth's gate aside); switcher S1–S5; keybinds K1 (but hidden builds), K2–K14 (recording lifetimes, reveal, reorder, preset plans); workspaces W1–W8 (overview board, dynamic one column, strip squeeze/drop, bar strips, indicator wrap, pinStart); every navigation through `CompositorManager`.
Doesn't hold: bind-merge.md's IPC mapping on Hyprland; bind-merge.md's and workspace-strips.md's Files headers; workspaces.md's `showEmpty` default; contract.md's `monitorColor` row; plus batch 1's ipc.md user list, window-switcher.md's "limited to the focused monitor", config-modes.md's `noteReload()`.

## Coverage
Read deeply: batch 1's set (HyprlandManager, MonitorManager, WindowSwitcherManager, CompositorConfigManager, KeybindEditor/Manager/PageState, the methods helpers, render/*.go, binds/hypr.go, hyprlua.go, manager/hypr.go, outputs.go, ipc/hypr.go, daemon/compositor*.go, takeover/kinds.go) and this re-audit's (binds/binds.go, isolate.go, marked.go, actions/actions.go, luacheck/*, takeover/takeover.go, components/surfaces/workspaces/*, shell/WorkspaceOverlay.qml, the bar Workspaces widget, the switcher UI, components/views/Keybinds/*, the keybind content parts, components/views/Monitors/*, the monitor prompt, MonitorsConfig, WorkspacesConfig, WorkspaceOverlayConfig, WorkspacesStatus, HyprlandGrab, CompositorManager's Hyprland-facing parts). Outlined: binds/sway.go, binds/niri.go, manager/manager.go (merge/remove/claim). Skipped: nothing run against a nested Hyprland (overview unplug with the native grab, batch 1's PLAUSIBLE items); OnboardingManager and GreetdManager seams by grep.

## History
- 2026-10-30 full (--deep, 3 reviewers + 3 verifiers): 28 findings (16 major, 11 cleanup, 1 outside); recorded in issues.md.
- 2026-10-30 full re-audit (--deep, 4 reviewers, lead verified; Go folders and the docs' folders now in scope): 27 new findings (13 major, 7 cleanup, 7 minor); major and cleanups for recording (--out).
