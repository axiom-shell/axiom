# hyprland
reviewed: 028e7ea 2026-10-30  (full)

The Hyprland backend holds its contract on the main paths: only the `Hyprland*` services import Quickshell.Hyprland or send `hl.*`, the writer and runtime layer render from one table, user strings reaching Lua are quoted, and the takeover's refusals, record and atomic writes hold. Its weak spots are failure and rare paths: the bind merge can delete binds it never read (a helper's `hl.bind`) or split an `hl.unbind` from its bind, a trial monitor Apply that turns a monitor off ends its own Keep/Revert, restoring a saved keybind preset makes Revert delete binds, and several evals and applies don't survive one refused line or one failed request. No blockers; 16 major, 11 cleanups, 1 outside the system (all recorded in issues.md, Phase 11 › Found by the audits). Deletion pass: about 210 lines can go.

## Open findings
All recorded in docs/dev/issues.md (`Found:` 2026-10-30, while reviewing the hyprland system); each entry there holds the scenario and fix. Recheck each by its `Where`:

Major
1. A trial monitor Apply that turns a monitor off drops its Keep/Revert — `services/compositor/MonitorManager.qml:451-456` (`onOutputsHotplugged`). PLAUSIBLE on the event: needs Hyprland's `monitorremoved` for a rule-disabled monitor (nested run).
2. A shell reload during a trial monitor Apply loses the way back — `MonitorManager.qml:303-308`. PLAUSIBLE.
3. Restoring a saved keybind preset marks every bind new, and Revert deletes it — `services/compositor/KeybindEditor.qml:101-114` (`_completeBind`), `:711` (`restorePreset`).
4. The Keybinds page goes stale after a detached-mode Save — `services/compositor/KeybindManager.qml:348` (`refreshSoon`, one caller).
5. The bind merge deletes an hl.bind inside a helper — `backend/internal/compositor/binds/hyprlua.go:340-355` (`callSite`). Reproduced.
6. The bind merge removes an hl.unbind whether or not its bind went — `binds/hypr.go:459-474`, `manager/manager.go:1290-1310` (`left`).
7. A failed monitor profile apply is never retried — `manager/outputs.go:170-171`.
8. One refused line stops the rest of a Hyprland eval — `manager/hypr.go:221-228` (`runtimeApply`), `manager/outputs.go:52`. PLAUSIBLE (does `hl.config`/`hl.monitor` raise?).
9. A user/ file with a dot in its name never loads — `render/hyprconfig.go:503`, `binds/hypr.go:383`. Reproduced.
10. A moved raw bind with a Lua keyword key compiles to nothing — `binds/hyprlua.go:467` (`luaSource`). Reproduced.
11. A failed options read sets the gaps to 0 — `services/compositor/HyprlandManager.qml:295`, `:822-824` (`_gapSides`).
12. A workspace slide throws when animations go off between legs — `HyprlandManager.qml:517-534` (`_nextSlide`).
13. Direct dispatches can overtake queued Lua — `HyprlandManager.qml:141-143,455-457,490` vs `_eval`. PLAUSIBLE.
14. Two recordings within 30 s: the first timer ends the second — `HyprlandManager.qml:412-420` (`_enterCaptureLua`). PLAUSIBLE, likely softened by KeyRecorder's `ShortcutInhibitor`.
15. Two keybind reference paths drop a key's binds — `KeybindsPageState.qml:153-156` (`_bindMods`), `components/methods/BindRows.qml:107-119` (`collapseDirections`).
16. Monitor prompt padding is a bare 18 px; check_sizes misses `pad` — `components/surfaces/monitors/MonitorPromptWindow.qml:19`.

Cleanup (deletion pass, with line counts in the entries)
17. HyprlandManager keeps members only it reads (`withAnimations`+`_optionsWaiting`, `runLua`, `withBinds`, `layerApplied`, `animations*`, chunk builder, `_bases` gate; ipc.md's user list is wrong) — about 40 lines.
18. `WindowSwitcherConfig.compositorSwitcher` unread — 3 lines (filed in the outside finding's entry, "The unused reader member check counts a member named after its key as used", whose fix finds it).
19. A bind description's section is parsed three ways (the editor's doesn't trim).
20. KeybindManager keeps `_modifiers` and nine `_keyNames` that BindKeys/KeyMap hold; skipped list twice — about 36 lines.
21. The workspace strips repeat ActiveStrip's loader — about 20 lines.
22. `HyprFileMonitorCalls` copies the managed catch-all monitor line — `render/hyprlua.go:451-459`.
23. The exit command kept in two packages — `binds/hypr.go:44`, `render/hyprconfig.go:30`.
24. `noteReload` double-counts reloads — about 9 lines; config-modes.md names it.
25. Go dead/doubled helpers (`Kind.record`, `SwitcherLeaveLua`, `UserKeyCounts`, `quoteLua`, anonymous struct ×6, setcursor ×2) — about 65 lines.
26. `BindActions.descriptionFor` dead; `withIds`/`withIDs` parity unpinned (they differ on a nil key).
27. Stale doc and comment lines (window-switcher.md scope, `orderMonitors`, BindKeys header, keys.go, EdgePopout).

Not filed (minor or refuted): compaction renumbering another output's workspaces after a replug (refuted: Hyprland hands them back before the fetch compaction waits on, workspace-strips.md › Replug; only a raw-hyprctl placement remains).

## Contract
Holds: C1 (only HyprlandManager/HyprlandGrab import Quickshell.Hyprland or dispatch; `check_structure` enforces it), C2 (one table, `render` for every mode; LuaString/ShellWord quote every user string; the writer touches only its module, managed file and takeover's records), C3 on the main path (backup first, `luacheck` before writing, atomic `edit.Replace`, failed files taken back out; broken by entries 5, 6, 10), C4 (layer rules re-added on `surfacesReady` and every `configreloaded`, each in a pcall). I1 (one connection per request, 5 s deadline, partial reply never taken as success), I2 (no eval batched), I3 (one chunk at a time, refetch after drain), I4 (six signals, no fetch for `custom`), I6, I7 (one batch at start, on reload, after `layerApplied`; but see 11). W2 (reload during read retries up to 3 times; but see 8), W5, W6, W9 (`HyprFromEnv` needs the instance signature). B2 sandbox, B6 (statementSpan rejects return/two calls/trailing code/used variable; but helpers, entry 5), B7 order, B8 (`mergeBinds`/`MergeBinds` pinned by shared cases). T1–T7 (stockSkip/releasedSkip, record, refusals). M1, M3, M4, M6 (but see 1, 2), M7 (`MatchProfile`/`HyprlandRules`; but see 7). S1–S5. K2–K6 (but see 12). KB1–KB5 (but see 3, 4, 14).
Doesn't hold: ipc.md's list of HyprlandManager's users (17); window-switcher.md "limited to the focused monitor" (27); config-modes.md's `noteReload()` (24).

## Coverage
Read deeply (by three reviewers, verified by three): HyprlandManager.qml, MonitorManager.qml, WindowSwitcherManager.qml, CompositorConfigManager.qml, KeybindEditor.qml, KeybindManager.qml, KeybindsPageState.qml, the methods helpers (WorkspaceGeometry, MonitorLayout, HyprState, HyprReply, DynamicWorkspaces, WindowOrder, BindActions, KeyNames, BindKeys, KeybindFilter, BindGroups, BindRows, KeyMap), the system's readers, render/hyprlua.go, render/hyprconfig.go, render/profiles.go, binds/hypr.go, binds/hyprlua.go, manager/hypr.go, manager/outputs.go, ipc/hypr.go, daemon/compositor.go, daemon/compositorsocket.go, takeover/kinds.go. Outlined: CompositorManager.qml (Hyprland-facing parts only: travel, remap, blocks, strips), Keybinds.qml and views/Keybinds/*, Monitors.qml, the bar Workspaces widget, shell/WindowSwitcher.qml, MonitorPromptWindow.qml, SwitcherStrip.qml, WorkspacesStatus.qml, takeover.go, manager.go (merge/left/reload paths). Skipped: nothing run against a live or nested Hyprland (findings 1, 8, 13, 14 left PLAUSIBLE for that); OnboardingManager and GreetdManager seams only by grep.

## History
- 2026-10-30 full (--deep, 3 reviewers + 3 verifiers): 28 findings (16 major, 11 cleanup, 1 outside); recorded in issues.md.
