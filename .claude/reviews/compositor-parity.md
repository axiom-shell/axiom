# compositor-parity
reviewed: b85084b 2026-10-30  (full)

The three backends implement every member the facade calls, and the takeover, autostart, session env and input gating are shared code. The parity gaps are the same input giving a different result: sway's named workspaces read as id -1, sway lists disabled outputs, niri's overview drop moves a whole column, niri misses a focus event, sway's merge turns workspace binds into raw commands, niri silently drops `release` and three look/behaviour settings, outputs.apply ignores another compositor's spelling, and the Mouse part reaches the touchpad only on Hyprland (a decision for the maintainer).

## Open findings
- Major: [niri's overview drop moves a window's whole column and switches workspace](../../docs/dev/issues.md#niris-overview-drop-moves-a-windows-whole-column-and-switches-workspace)
- Major: [sway's named workspaces all share workspace id -1](../../docs/dev/issues.md#sways-named-workspaces-all-share-workspace-id--1)
- Major: [sway lists disabled outputs as outputs](../../docs/dev/issues.md#sway-lists-disabled-outputs-as-outputs)
- Major: [niri doesn't send windowFocused for a window that opens focused](../../docs/dev/issues.md#niri-doesnt-send-windowfocused-for-a-window-that-opens-focused)
- Major: [sway's merge moves workspace binds as raw sway commands](../../docs/dev/issues.md#sways-merge-moves-workspace-binds-as-raw-sway-commands)
- Major: ["Fire on release" is offered on niri and silently dropped](../../docs/dev/issues.md#fire-on-release-is-offered-on-niri-and-silently-dropped)
- Major: [The Monitors page's Apply misses a niri-spelled monitor on Hyprland and sway](../../docs/dev/issues.md#the-monitors-pages-apply-misses-a-niri-spelled-monitor-on-hyprland-and-sway)
- Major: [Three settings stay editable on niri though its writer drops them](../../docs/dev/issues.md#three-settings-stay-editable-on-niri-though-its-writer-drops-them)
- Major: [Mouse speed, acceleration and left-handed reach the touchpad only on Hyprland](../../docs/dev/issues.md#mouse-speed-acceleration-and-left-handed-reach-the-touchpad-only-on-hyprland)
- Cleanup: [leaveSwitcher is stubbed on sway and niri, and called on them](../../docs/dev/issues.md#leaveswitcher-is-stubbed-on-sway-and-niri-and-called-on-them)
- Cleanup: [Small shrinks in SwayManager](../../docs/dev/issues.md#small-shrinks-in-swaymanager) (`runCommands`, filed by the sway review)
- Cleanup: [sway and niri build output details and descriptions twice](../../docs/dev/issues.md#sway-and-niri-build-output-details-and-descriptions-twice)
- Cleanup: [The bind merge lists user/ files three times, once per compositor](../../docs/dev/issues.md#the-bind-merge-lists-user-files-three-times-once-per-compositor)
- Cleanup: [sway's and niri's merges build a moved bind the same way twice](../../docs/dev/issues.md#sways-and-niris-merges-build-a-moved-bind-the-same-way-twice)
- Cleanup: [The merge keeps key and variable tables render already has](../../docs/dev/issues.md#the-merge-keeps-key-and-variable-tables-render-already-has)

Unrecorded (Minor): niri's empty workspace names (`NiriState.windows`/`workspace`: "workspace " in the launcher); niri misses the hotplug after zero outputs (`NiriManager._readOutputs`, sway's `_outputsRead`); contract.md's `mirrorOf` (Hyprland's is an id), "optional" `outputsApplied` (required with `monitors`) and its two-backend list; sway's and niri's merges list git-tracked files they never edit (`tracked`). Known-entry notes, added to "Backends keep stubs for calls the facade gates": `SwayManager.scrollStrip` and `NiriManager.applyRemap`.

## Contract
Holds on all three: string window ids, `focusRank` 0 = last focused, global logical geometry, logical output sizes and `reserved`, the keyboard shape, the output-details shape (physical mode px, Hz, Wayland transforms, `WxH@R.RRHz`), `configReloaded`/`keyboardLayoutChanged` signals, every ungated facade call present, `travel` order (output › focusId › move › go), silent `sendWindowToWorkspace`, graceful `closeWindow`, instant `exitSession`, sway's and niri's action queues, every supports key read (bind keys via `table.json` `needs`), one takeover driven by `takeover.Kind`, shared autostart/session env/input gating, look units, monitor rules in files, bind modifier/mouse round-trips, `locked`/`repeating`, the read-back bind shape.

## Coverage
Read deeply: the three backend managers and CompositorManager, the three State helpers, `binds/*.go`, `manager/{hypr,sway,niri,outputs}.go`, the writer and bind parts of `render`, `takeover`. Outlined: `kdl`, `ipc/niri*.go`, `daemon/compositorsocket.go`, `userconf`, CompositorConfigManager, SwitcherKeys, SwayIpcManager, BindKeys. Skipped: `scripts/dev/nested.sh`. No nested compositor run; live-only: sway disabled outputs, niri overview drop, niri focus event for a new window.

## History
- 2026-10-30 full: 19 findings (9 Major, 6 Cleanups, 4 Minor); recorded
