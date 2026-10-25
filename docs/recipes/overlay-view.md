# Recipe: a new overlay view type (incl. tool pages)

> **Use when:** adding a page type to the overlay. A *tool page* (`x-tool: true`: Settings, BarEditor, Themes, Keybinds, Monitors, CalendarPage) is a hand-built page that is always in config.
> **Copy from:** `components/views/Settings/Settings.qml` (a small `BaseView` page), `components/views/Themes/Themes.qml`; schema `components/views/CalendarPage/schema.yaml`.
> **Docs:** [overlay/pages-and-grid](../dev/overlay/pages-and-grid.md), [core/streamed-building](../dev/core/streamed-building.md), [core/editors-pattern](../dev/core/editors-pattern.md) (for an editor page), rules in `components/views/AGENTS.md`; generated: [config/OverlayViews](../dev/config/OverlayViews.md).

## Files to touch
1. `components/views/<Type>/<Type>.qml`: the page; its pieces beside it.
2. `components/views/<Type>/schema.yaml`: the type's schema, beside it. The build finds it (index.yaml's `kinds`), expands it over `definitions/kinds/ViewBase.yaml` into `<Type>OverlayView` and adds it to `OverlayView`'s `oneOf`: nothing else to list.
3. Tool page only:
   - `config/schema/sections/Overlay.yaml`'s `items` `default` array: append `{ type: <Type>, id: <type> }`;
   - a format-2 step appending it to existing configs, with its test and the `version` bump ([migration](migration.md));
   - `services/ui/LauncherCommands.qml`: a way to open it (below);
   - `docs/usage.md`: the **Pages** row of the launcher command table.
4. `config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys, empty, to every language and the template.

## Skeleton
```qml
pragma ComponentBehavior: Bound
import QtQuick
import qs.services.<group>  // FooManager's folder: core, compositor, session, system, ui or apps
import qs.components.views.FooPage

// <What the page is for and where its state lives (FooManager).>
BaseView {
  id: root

  Component.onCompleted: FooManager.ensureLoaded()

  // Each panel streamed in as the page opens, at its size from the start
  StreamedLoader {
    Layout.preferredWidth: root.sideWidth
    Layout.preferredHeight: root.pageHeight
    label: "foo sidebar"
    sourceComponent: FooSidebar {}
  }

  StreamedLoader {
    Layout.preferredWidth: root.editorWidth
    Layout.preferredHeight: root.pageHeight
    label: "foo editor"
    sourceComponent: FooEditor {}
  }
}
```
(`import QtQuick.Layouts` and `qs.components.reusable` too.) The page shows at once and its panels fill in over the next frames: wrap long or repeated parts inside them the same way, build nothing hidden, and check it with `scripts/dev/bench_overlay.sh FooPage` (no `Built … in` line over a frame or two). See [streamed-building](../dev/core/streamed-building.md).
Schema (`schema.yaml` beside `FooPage.qml`):
```yaml
label: Foo
icon: build
tool: true
```
Migration step (tool page; [migration](migration.md)):
```go
// v<N> added the Foo page: every config gets it once
{Version: <N>, Run: func(cfg *jsonx.Object) []string {
	overlay, _ := cfg.Value("Overlay").(*jsonx.Object)
	if overlay == nil {
		return nil
	}
	items, _ := overlay.Value("items").(*jsonx.Array)
	if items == nil {
		return nil
	}
	for _, item := range items.Items {
		if view, _ := item.(*jsonx.Object); view != nil && view.Value("type") == "FooPage" {
			return nil
		}
	}
	items.Append(jsonx.Obj("type", "FooPage", "id", "fooPage"))
	return []string{"Overlay.items: added the Foo page"}
}},
```

## Steps
1. Schema first: `schema.yaml`, and for a tool page the `Overlay.items` default entry. Then the migration step and version bump, then its test.
2. Pick a type const that's the file name and doesn't collide with a content type (`CalendarPage`, not `Calendar`).
3. Write the view on `BaseView`: size from `grid`, `pageHeight`, `sideWidth`, `editorWidth`, `cardPageWidth`; `viewConfig` is its entry in `Overlay.items`.
4. Opening it from the launcher: add `root._page("<name>", [aliases], "<Type>", "<Description>")` to `LauncherCommands.list`, and add `I18n.tr("<Description>")` to the declaration comment in `_page`. If the page should open on something chosen first, pass `before`; or give it its own command calling a service, as `/calendar` does (`CalendarManager.openPage()`, which falls back to a page holding the Calendar module).
5. Verify.

## Gotchas
- A new subfolder imported only from URL-loaded files isn't scanned until qs restarts (`module "qs.components.views.FooPage" is not installed`): ask the user to restart.
- Editor pages: the manager owns the draft and the selection (`select*()`); the page never assigns them ([core/editors-pattern](../dev/core/editors-pattern.md)).
- The page exists only while it or a neighbour is shown: lasting state goes in a service.
- Its `icon` is also the launcher command's glyph (`OverlayConfig.viewIcon(type)`).
- The migration step must be idempotent and must check its input's shape.

## Verify
- `scripts/dev/verify.sh`
- `scripts/run_tests.sh Config` (defaults, the migration test, `test_migration_is_idempotent`)
- `scripts/dev/shot.sh page <Type>`

## Docs to update
- [overlay/pages-and-grid](../dev/overlay/pages-and-grid.md) (the tool page list), the feature's doc, `docs/usage.md`.
