---
paths:
  - "qml/components/views/**"
---

# Views (`qml/components/views/`)

Overlay page types: `<Type>/<Type>.qml` + `schema.yaml` (expanded over `definitions/kinds/ViewBase.yaml`), loaded by `OverlayPages` for each `Overlay.items` entry; shared pieces in `base/`. Docs: `docs/dev/overlay/pages-and-grid.md`, `docs/dev/core/editors-pattern.md`, `docs/dev/core/settings-page.md`. Recipes: `/overlay-view`, `/settings-card`.

- Views extend `BaseView` (`grid`, `viewConfig`, `pageHeight`, `sideWidth`, `editorWidth`). The type name must not collide with a content type (`CalendarPage`, not `Calendar`).
- **A page shows at once and fills in**: each panel, card and repeated section is a `StreamedLoader` sized from the page, gated by `wanted:` (never `visible`). Measure with `scripts/dev/bench_overlay.sh <Type>`.
- **A tool page** (`x-tool`) is always in config: the `Overlay.items` default, a format-2 step appending it, a `_page(…)` entry in `qml/services/ui/LauncherCommands.qml`, a row in the `docs/usage.md` launcher table. One with `x-window` pops out into its own window and gets a `data/applications/axiom-<type>.desktop`: its state lives in its manager, never the page (`docs/dev/overlay/page-windows.md`).
- Editor pages never assign the draft or selection; the manager owns them (`select*()`).
- `Settings/` holds hand-built settings parts: `x-card: {file, title, wide, folds}` loads `Settings/<file>Card.qml` (titled by `title`, never in its QML), `x-intro` and `x-row` load `Settings/<Name>.qml` (`docs/dev/core/schema-annotations.md` › Hand-built parts).
