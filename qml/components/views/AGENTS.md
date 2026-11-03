# Views (`components/views/`)

Overlay page types: `<Type>/<Type>.qml` is loaded by `OverlayPages` for each entry of `Overlay.items`; a view's pieces and its `schema.yaml` live beside it, shared ones in `views/base/`. Docs: `docs/dev/overlay/pages-and-grid.md`, `docs/dev/core/editors-pattern.md`, `docs/dev/core/settings-page.md`.

**Recipe:** `docs/recipes/overlay-view.md` / `docs/recipes/settings-card.md`; verify with `scripts/dev/verify.sh`.

- Views extend `BaseView` (`grid`, `viewConfig`, `pageHeight`, `sideWidth`, `editorWidth`). Copy `Settings.qml` or `Themes.qml`.
- **A page shows at once and fills in**: each panel, card and repeated section is a `StreamedLoader` sized from the page (`Layout.preferred*` or anchors), and nothing is built hidden (`wanted:` its mode's condition, never `visible`). Check with `scripts/dev/bench_overlay.sh <Type>`. Docs: `docs/dev/core/streamed-building.md`.
- **A new view = this file + a `<X>OverlayView` schema definition + its `$ref` in `definitions.OverlayView.oneOf`.** The type const is the file name; pick one that doesn't collide with a content type (`CalendarPage`, not `Calendar`).
- **A tool page** (`x-tool: true`) is always in config: add it to the `Overlay.items` default, a format-2 step that appends it to existing configs (`docs/recipes/overlay-view.md`, [migration](../../docs/recipes/migration.md)), a `_page(...)` entry in `services/ui/LauncherCommands.qml`, and a row in the `docs/usage.md` launcher table.
- Editor pages follow `docs/dev/core/editors-pattern.md`: the manager owns the draft and selection (`select*()`), the page never assigns them.
- `settings/` holds hand-built settings parts: `x-card: "<Name>"` loads `settings/<Name>Card.qml` (titled by the section's `x-cardTitle`, never in its QML), `x-intro` loads `settings/<Name>.qml`. `check_structure.py` doesn't verify these exist: check yourself.
- A new subfolder imported only from URL-loaded files needs a qs restart (ask the user).
