# Adding an overlay page type

An overlay page type is a whole page of the overlay (the full-screen layer with the navigator at the bottom). A *tool page* is the hand-built kind (Settings, Themes, the bar editor, Keybinds, Calendar): it is always in the config and shows as an icon after the user's own pages. At the end you have a page that opens from the overlay, and for a tool page from the launcher, and that streams in without a hitch.

**Copy from:** `qml/components/views/Themes/Themes.qml` + `schema.yaml` (a tool page made of streamed panels), `qml/components/views/CalendarPage/CalendarPage.qml` (a tool page that pops out into a window and keeps its state in a manager); the migration step `Version: 80` in `backend/internal/migrate/steps/steps.go` (it appends a tool page to existing configs), with `TestV80AddsTheCustomWidgetsPage` in `steps_test.go`.
**Background:** [pages and grid](../dev/overlay/pages-and-grid.md), [streamed building](../dev/core/streamed-building.md), [editors pattern](../dev/core/editors-pattern.md) (for an editor page), [page windows](../dev/overlay/page-windows.md), [migration recipe](migration.md); generated: [config/OverlayViews](../dev/config/OverlayViews.md)

## Files
1. `qml/components/views/<Type>/<Type>.qml`: the page, on `BaseView`, with its pieces beside it. The type is the file name.
2. `qml/components/views/<Type>/schema.yaml`: `label` and `icon`, plus `tool: true` and `window: true` where they apply. The schema build finds it and adds `<Type>OverlayView` to `OverlayView`; there is nothing to list by hand.
3. For a tool page only:
   - an entry in the `items` default of `qml/config/schema/sections/Overlay.yaml` (`{id: …, type: <Type>}`), which `check_structure` insists on;
   - a format-2 migration step that appends the same entry to existing configs, its test, and the `version` bump ([migration](migration.md));
   - a launcher command in `qml/services/ui/LauncherCommands.qml`;
   - the **Pages** row of the launcher table in `docs/usage.md`.
4. For a tool page that can pop out (`window: true`): `data/applications/axiom-<type>.desktop` (copy `axiom-themes.desktop`) and the type in the `pages` row of the IPC table in `docs/usage.md`.

Translation files need nothing: the pre-commit hook adds new strings to every language.

## Steps
1. Write `schema.yaml` and, for a tool page, the `Overlay.items` default entry. Then the migration step, its test and the version bump.
2. Choose a type name that is the file name and doesn't collide with a module type (`CalendarPage`, not `Calendar`).
3. Write the page on `BaseView`. Size everything from it: `pageHeight`, `sideWidth`, `editorWidth`, `cardPageWidth` and `grid`; `viewConfig` is the page's entry in `Overlay.items`. Put each panel in a `StreamedLoader` with a size from the start, as `Themes.qml` does, so the page appears at once and fills in over the next frames.
4. Add the launcher command: `root._page("<name>", [aliases], "<Type>", "<Description>")` in the list in `LauncherCommands.qml`, and the description in the `I18n.tr("…")` comment inside `_page` (the translation check reads that comment). A page that needs something chosen first passes a `before` function. A page with its own opener service gets its own command instead, as `/calendar` does with `CalendarManager.openPage()`.
5. If the page pops out, keep its state in its manager and not in the page: only one host builds the page at a time, and the window and the overlay swap ([page windows](../dev/overlay/page-windows.md)).

## Watch out for
- A new folder under `views/` that is only imported from files loaded by URL isn't scanned until qs restarts (`module "qs.components.views.<Type>" is not installed`). Ask the user to restart.
- An editor page never assigns the draft or the selection; the manager owns them (`select*()`), see the editors pattern.
- The page only exists while it or a neighbour is shown. Anything that must last goes in a service.
- Nothing is built hidden. A part shown in one mode only is a `StreamedLoader` with `wanted:` the mode's condition, not `visible: false`.
- The page's `icon` is also the launcher command's glyph (`OverlayConfig.viewIcon`).
- A migration step runs on any config of any older version, so it must check the shape of what it reads and do nothing the second time. `Version: 80` shows both.

## Check it
- `scripts/dev/verify.sh`
- `go -C backend test ./internal/migrate/steps` (the new step's cases and `TestSchemaVersionIsCurrent`), and `scripts/run_tests.sh Config` for the schema defaults.
- `scripts/dev/shot.sh page <Type>` opens the page, takes a screenshot and closes it; then read `scripts/log.sh`. A page's QML errors only reach the log once it has been opened.
- `scripts/dev/bench_overlay.sh <Type>`: no `Built … in` line should be longer than a frame or two.

## Docs to update
- [pages and grid](../dev/overlay/pages-and-grid.md): its list of tool pages. If the page can pop out, the list in [page windows](../dev/overlay/page-windows.md) too.
- The doc of the feature the page belongs to, and `docs/features.md` (Built-in pages).
