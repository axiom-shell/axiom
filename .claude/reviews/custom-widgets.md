# custom-widgets
reviewed: 31af7d1 2026-10-31  (full)

A young, compact system in good shape: the Waybar reading, one script per definition, by-count Repeaters and the layouts editor's canvas reuse all hold. Open: the lock screen shows any definition once one module is placed there, a module past two cards can't be saved, and the Tooltip switch does nothing.

## Open findings
- Major: [Any custom widget reaches the lock screen past its Offer switch](../../docs/dev/issues.md#any-custom-widget-reaches-the-lock-screen-past-its-offer-switch)
- Major: [A custom widget's module past 8 grid units can't be saved](../../docs/dev/issues.md#a-custom-widgets-module-past-8-grid-units-cant-be-saved)
- Major: [A custom widget's Tooltip switch does nothing](../../docs/dev/issues.md#a-custom-widgets-tooltip-switch-does-nothing)
- Major: [A stale exec-if check can block a widget after its exec-if changed](../../docs/dev/issues.md#a-stale-exec-if-check-can-block-a-widget-after-its-exec-if-changed)
- Major: [A command naming a program shows the program as its script](../../docs/dev/issues.md#a-command-naming-a-program-shows-the-program-as-its-script)
- Cleanup: [CustomElement's six Binding blocks are Qt.binding in its setSource](../../docs/dev/issues.md#customelements-six-binding-blocks-are-qtbinding-in-its-setsource)
- Cleanup: [A custom layout without elements rebuilds its default elements every sample](../../docs/dev/issues.md#a-custom-layout-without-elements-rebuilds-its-default-elements-every-sample)

Minor (unrecorded):
- `services/apps/CustomWidgetsManager.qml:75`: `?? true` on `refreshAfter`, a default the schema fills; the doc never mentions `refreshAfter`.
- `CustomWidgetsManager.find`: an empty name matches the first definition without a refresh name; a duplicate keeps its source's `refreshName`.
- `v81.go:118`: `name[:40]` can cut mid-rune.
- Ring and Gauge schemas repeat the same `inside` setting.
- A script printing only axiom's fields (no `text`) hides by default (`hideEmpty`), as documented.

Known before this review: [A custom Ring element logs an undefined `inside` on load](../../docs/dev/issues.md#a-custom-ring-element-logs-an-undefined-inside-on-load), [A custom layout's element rect reads an undefined place](../../docs/dev/issues.md#a-custom-layouts-element-rect-reads-an-undefined-place).

## Contract
Holds: definition fields and their sources; `parse`/`resolve`/`flatten`/lattice helpers; acquire by id through `CommandManager` (json unless text), 60-sample history, re-resolve on edits, execIf on first show and refresh, actions detached with `{value}` quoted and a 300 ms refresh, no actions in the greeter, while locked, on the lock screen or in previews; IPC `refresh`/`list`; popout sized up front; prefixed element loading; element kinds from the schema; bar styles and actions; `CustomWidget:<id>` library keys through `splitKey`; the page's tabs and `EditsManager`; import and presets; v81 (tested in `steps_test.go`). A stream's refresh flushes, never restarts. Broken: the lock-screen offer is library-only; no tooltip on the bar.

## Coverage
Read deeply: every file in the scope (3568 lines). Outlined: `tst_CustomWidgetData.qml`, `CommandManager.refresh`, `stream.go`, `GridEditor`/`GridPlacement` placement, `OverlayConfig.customModuleTypes`, `ConfigDraft.save`/`ConfigManager.commit`, the store's write check. Skipped: the greeter's exec methods (the greeter audit's).

## History
- 2026-10-31 full: 7 findings (5 Major, 2 Cleanup) + 5 Minor; recorded
