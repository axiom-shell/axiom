# BAR REWRITE — working plan and status (DELETE THIS FILE before the PR merges)

> Temporary handoff file for branch `bar-rewrite` in `~/repos/axiom` (the maintainer tests from this checkout).
> If you are an agent picking this up: read **Status** first, then the plan below. Keep **Status** current after every commit.

## Status
- Branch: `bar-rewrite` (from main 99ae4ee). Work lands here; implementation agents use `isolation: worktree` and the lead merges their branches into `bar-rewrite`.
- Phase: **A (schema, migration, readers) — not started.**
- Done commits: none yet.
- Running agents: none.
- Next: brief agent A with section "A" + the Contract below.
- Notes / gotchas found: (none yet)

# Bar rewrite for release: settings, schema, rendering, auto-hide, editor

## Context
The bar's config has misleading names, and `background` crams three choices (shape, attached/floating, fill) into one enum. As a result, pill bars use their own padding and sit 9 px deeper than solid ones (43 vs 34 px with the defaults), so switching style moves windows. The `leftCenter`/`rightCenter` sections are rigid. Widget names differ between the library and the bar. Font size ignores the bar's thickness, and the size override does nothing useful on most widgets. The editor scrolls sideways, shows text chips instead of widgets, hides the library while editing, and has no undo.

This one PR (maintainer: "the scope is everything for this pr") rebuilds all of it ahead of release. It has one commit per item. It exceeds the roadmap's ~800-line batch cap by the maintainer's choice, and the PR body says so and lists net lines per area.

## Decisions (maintainer, 2026-11-04)
- **Surface split:** `surface: bar | pills | none` + `floating: bool` + `floatingGap` (Auto = `null`, no -1). Pills and solid have identical extent, zone and widget positions, border on or off. The same holds for floating vs floating pills.
- **Renames:** widgetSize→`thickness`, padding→`edgePadding`, spacing→`widgetGap`, widgetPadding→`innerPadding`, widgetSpacing→`innerGap`, floatGap→`floatingGap`. `pillPadding` is removed (pills use `edgePadding`).
- **Merging:** no merge setting (pillMerge removed). One rule, used by pills, floating pills and the `merged` grouping: a group is a run between section ends and spacers. Neighbouring groups join when the gap between them is ≤ the widget gap.
- **Sections:** left / center / right. `lockCenter` stays. A new **Spacer** fills the free room on its side, several spacers share it equally, and each shrinks to `minGap` (default 0) when crowded. A spacer in the center is fixed. **Separator** loses `space`, and old space separators become Spacers with `minGap` = their size.
- **Text scale:** text, icons and inner padding scale with thickness. `textScale` % (default 100; 100% at 26 px = today's look) replaces the px font size.
- **Widget sizing:** `priority` on all widgets. `minSize` and new `maxSize` only on shrinkable widgets (Window, Media: `x-elastic`). `layout.size` is removed, and an old size on an elastic widget becomes `maxSize`.
- **Labels:** one short label per widget everywhere (Clock, Battery, Media, Window title, Workspaces, …), with the old labels as search keywords. Type ids are unchanged.
- **Defaults:** the `Bar` definition defaults equal the default bar (pills, center locked).
- **Auto-hide:** `autoHide: never | always | whenCovered`.
  - A revealed bar never reserves space. An IPC/keybind **toggle** pins it shown, and a pinned bar does reserve. `reserveSpace` is hidden unless `never`.
  - Reveals on: edge hover; a workspace change (own toggle); widget activity (own toggle); while one of its popouts is open; IPC/keybind.
  - It keeps its stack slot and slides toward its edge.
- **Stack order:** solid → strip → pills → floating → floating pills → transparent (transparent moves to last). Edge popouts of a transparent bar open past the floating bars.
- **Bar length:** `length: full | fit` + `align: start | center | end`. Scroll actions are out of scope.
- **Editor:**
  - The board still follows the bar's edge; the stack button goes.
  - Each section gets a full-width row (or full-height column on side bars) that wraps instead of scrolling.
  - Chips are live widgets with input blocked.
  - The inspector (~55%) and the library (~45%) are both visible.
  - The left panel gets tabs (Layout / Surface / Widgets / Behaviour).
  - Undo/redo; a right-click menu plus keys; editor hover outlines the widget on the real bar, and real-bar hover highlights the chip.
  - Priority badges; an actionable fit meter; an Unsaved chip plus per-field change dot and reset; help in a "?".

## Execution
All work happens on branch `bar-rewrite` in `~/repos/axiom` (the maintainer tests from it). The lead (me) writes each agent's brief and merges the agents' branches. Each implementation agent runs in its own `isolation: worktree`, with a narrow scope and the contract below quoted, and reports its commits and verify result. At most 3 agents run at once:

1. **A — schema, migration, readers** (first; everything else builds on its names).
2. **B — bar rendering** ∥ **C — editor** (C starts on A; rebases on B before its live-chip and fit-meter commits).
3. **D — auto-hide**, after B (it rewrites the same BarPanel/placeStack/ScreenEdgeManager lines), alongside C.
4. A fresh **review-branch --fix** agent over the whole branch, then the lead runs `verify.sh --all`, opens the PR and waits for CI on the pushed sha.

Each item is one commit, ending with `scripts/dev/verify.sh` printing `verify ok`. QML is edited in place (no `qmlformat -i`, no temp+rename). No translations (the pre-commit hook fills them).

### A — schema, migration, readers
1. **Two new annotations.**
   - `x-auto: {value: null, start: N}`: null passes validation, mirroring `x-inherit`. Touches `backend/internal/config/pipeline.go:146`, `SchemaValidation.qml` and `SchemaField.qml:296-312`.
   - `x-keywords`.
   - Register both in `qml/config/schema/annotations.yaml` and `docs/dev/core/schema-annotations.md`, with test rows.
2. **Schema.**
   - `definitions/widgets/Bar.yaml`:
     - groups Placement, Size, Surface, Behaviour; keys `length`, `align`, `thickness`, `edgePadding`, `widgetGap`, `innerPadding`, `innerGap`, `surface`, `floating`, `floatingGap`;
     - `lockCenter` (default true), `autoHide`, `reserveSpace` (showIf autoHide never), `revealOnWorkspace`, `revealOnActivity`, `revealFor`, `timing`, `trigger`;
     - `widgets: {left, center, right}`.
   - `BarStyle.yaml`: `textScale` replaces `fontSize`.
   - `WidgetLayout.yaml`: `priority`, `minSize`, `maxSize`.
   - New `widgets/Spacer/` (`minGap`; no popout part).
   - Separator: label "Separator"; its enum narrowed locally (the custom-widget Separator element keeps `space`).
   - Short labels + `keywords` + `elastic: true` (Window, Media) in every `widgets/*/schema.yaml`.
   - `sections/Bars.yaml` default item trimmed to what differs from the definition.
3. **Migration v93** (`backend/internal/migrate/steps/v93.go` + test, `index.yaml` version):
   - `background` → `surface` + `floating`; unknown/missing → `bar` + false. Missing `lockCenter` → false (keeps the old behaviour).
   - `floatGap` → `floatingGap` (-1 → null).
   - Renames via `renameKey` (`v86.go:69`). `innerPadding`/`innerGap` are rescaled by 26/thickness so pixels stay the same. `pillPadding`/`pillMerge` are dropped.
   - `fontSize` → `textScale` (shared and per bar, relative to `Appearance.font.size` and thickness).
   - `leftCenter`/`rightCenter` → `[...left, Spacer, ...leftCenter]` / `[...rightCenter, Spacer, ...right]`, with ids via `freeID` (`v81.go:95`).
   - Space Separators → Spacer `{minGap: size}`.
   - `layout.size` → `maxSize` on Window/Media, else dropped; `minSize` dropped on non-elastic widgets.
   - Messages in the v92 style. Test rows for every value and edge case (non-object items, existing new key, missing style, thickness 40, idempotent rerun).
4. **Readers and renames.**
   - `qml/config/BarsConfig.qml` `enrichBarConfig` emits the contract keys; geometry is unchanged in this commit.
   - `sectionNames` = 3. `availableWidgetTypes` gets `keywords` and `elastic`.
   - Every `barConfig.*` consumer is renamed (BarContainer, BarWidgetHost, WidgetGroup, CornerMerge, PillBarJoin, EdgePlacement, SurfaceContext, EdgeAttach, BarEnds, ReservedAreaWindow, ScreenEdgeManager, the widgets, `views/CustomWidgets/BarTab.qml`, the tests). A temporary 3→5-section adapter stays in BarContainer until B.
   - `LibraryOrder.filtered` matches keywords (+ a `tst_LibraryOrder` row).
   - Onboarding `LookPage.qml`/`ExampleCard.qml` and `backend/internal/saved/saved.go` `ExampleBar` (+ test) move to surface/floating.
   - Fixtures regenerated (`scripts/gen_docs.py --fixtures`).

**Contract (A → B, C, D):**
- **Enriched keys:**
  - `kind` (solid|pills|transparent|floating|floatingPills), `solid`, `pills`, `island`, `islandPills`;
  - `thickness`, `edgePadding`, `widgetGap`, `innerPadding`, `innerGap`, `fontSize`, `joinGap`;
  - `floatingGap`, `floatingGapAuto`, `fit`, `align`, `autoHide`, `revealOnWorkspace`, `revealOnActivity`, `revealFor`, `timing`, `trigger`.
- **Sections:** `["left","center","right"]`.
- **Widget layout:** `{priority, minSize, maxSize}`.
- **Type info:** `label`, `keywords`, `elastic`.

### B — bar rendering
5. **`methods/BarLayout.qml`, three sections and spacers.**
   - `layoutSections` lays out as today. Then, with a center, a side with spacers stretches to the center's edge; with no center, the free room is shared by spacer count.
   - `allocate` hands the extra room to fill widgets equally (the remainder to the last). A collapsed spacer leaves one gap.
   - `overflowHidden` uses tie order right, left, center and never drops spacers. `lockCenter` stays: spacers never move the center.
   - Tests in `tests/tst_BarLayout.qml`, plus the missing lockCenter-center-overflow row (issue).
6. **Joining groups.**
   - `BarLayout.joinGroups(spans, joinGap)` + `pillRects` replace `BarContainer.sectionPills` (`BarContainer.qml:92-122`, issue "The pill merge in BarContainer repeats BarLayout's").
   - `islandRects`/`stretchIslands`, EdgeAttach and SurfaceContext take `joinGap`.
   - In `merged` grouping, WidgetGroup's first and last runs join across sections (`joinStart`/`joinEnd`).
7. **Pills equal solid.**
   - Pure `crossGeometry`: body depth `D = max(border ? margin − bw : 0, 2·edgePadding + thickness)`.
   - Solid: extent `D` with border, `D + bw` without.
   - Pills: extent `D + bw`. The outermost pill bar with the border on has `outerReach = margin` and `stripCover = margin − bw`, with a cap under each pill, so zone, taken and widget offsets equal solid's.
   - Worked defaults: windows start at 35 px and widgets at 4..30 in both styles, border on and off.
   - `BarEnds.placeStack` outputs `outerReach`/`stripCover`; BarPanel `_outerReach`; BarContainer pill depth, cap, shadow/blur shape and border opening.
   - **Risks:** `BarContainer.qml:575-700`, `CornerMerge.qml:37`, `SurfaceContext.qml:330` `pillFoot`, and the translucent strip under the cap.
   - Tests in `tst_BarEnds` (solid == pills rows; solid-meets-solid issue row).
8. **Stack order.**
   - `BarEnds.kindIndex` and `rank` (solid 3, pills 2, floating 1, transparent 0).
   - `LayerStack.layers` order, `tst_LayerStack`, backend goldens (`backend/internal/compositor/manager/testdata/golden/**`), `tests/fixtures/layers/hyprland-two-bars.json`.
   - Remove the dead `openInside && next.island` trim arm (`BarEnds.qml:265`).
   - Popout tweak: a transparent bar's `detachedPush`/`windowsPast` opens past the floating bars (`SurfaceContext.qml:126,389`); check `ScreenEdgeManager.barStartOn` and `EdgePlacement._fromScreen`. Add `tst_SurfaceContext` rows.
9. **Scaling with thickness.** `fontSize = round(Appearance.baseFontSize · thickness/26 · textScale/100)`; innerPadding/innerGap × thickness/26. Then re-check the "stacked style clips on a thin bar" and the vertical-bar clipping issues.
10. **`length: fit`.** The surface spans the content at `align`; spacers collapse to `minGap`.
11. **Editor reports.**
    - `BarContainer.editorReport` gets per-section `{used, room}`.
    - A report on `Component.onCompleted` (fixes the issue "A bar made while the bar editor is open may never report to it").
    - `BarWidgetHost.preview` (no menu anchor, no report, `active: !preview` on the menu).

### D — auto-hide (after B)
12. **`CompositorManager.windowsCover(screen, rect)`**, moved from `DockManager.obscured` (`DockManager.qml:212-226`); DockManager uses it.
13. **New `qml/services/ui/BarRevealManager.qml`.**
    - State per bar: hover, holds, until, pinned. `shown = never || pinned || hover || holds || now < until || (whenCovered && !covered)`. One one-shot Timer.
    - `BarEnds` sorts and yields by the configured reserve and zones by the effective reserve (configured || pinned), so the slot never moves.
    - BarPanel: `exclusiveZone`, a mask strip (`trigger.size`) while hidden, and the container's x/y slid toward the edge (geometry, not Translate, so blur and shadow follow) with Appearance timing.
    - Fullscreen: the bar stays on Top under the fullscreen window, and nothing remaps.
    - The editor holds the selected bar shown.
14. **Attention.** `BaseWidget` gets `signal attention()`; `BarWidgetHost` forwards it. Emitters fire on change, never at startup:
    - Notifications: unread count rose, DND off.
    - Media: track changed while playing.
    - Battery: crossed below the low threshold.
    - Updates: count rose.
    - CustomWidget: entered warning or critical.
15. **IPC `bar`** via `IpcTarget`: `reveal [id]`, `toggle [id]` (pin, reserves), `hide [id]`; enabled only on the target instance. Keybind actions for the same, and the `docs/usage.md` IPC table.

### C — editor
16. **Shared `EditHistory`.** New `qml/services/ui/EditHistory.qml` (snapshot/restore, `record(fieldKey)` coalescing, limit 50), extracted from `GridEditor.qml:375-445`; GridEditor uses it. New shared `reusable/UndoRedoButtons.qml` from `GridCanvas.qml:170-185`.
17. **Shared pieces.**
    - New `reusable/StyledContextMenu.qml`: `DropdownSurface`; items `{text, icon, shortcut, enabled, checked, submenu}`; keyboard support.
    - New `forms/FieldChangeMarks.qml`, extracted from `SettingsField.qml:95-144` (change dot + reset to default), passed through `SchemaField.headerExtra` / `OptionsGroup`.
    - `CardHeader.help` "?" tooltip.
    - Add to `docs/dev/core/shared-ui-pieces.md`.
18. **`services/ui/BarManager.qml`.**
    - History, with Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y.
    - `hoveredWidget`/`isHoveredWidget`, and the passive `barHover` reported by BarWidgetHost while editing.
    - Actions: `moveWidgetTo`, `addSpacer`, `copyWidgetToBar`, `setWidgetPriority`, `setWidgetMax`.
    - Selection fixes in `removeBar`/`duplicateBar` (issue "Removing or copying another bar moves the editor's selection").
    - `EditsManager.barStacked` removed.
19. **Board** (`SectionsBoard`, `SectionLane`, `BarDragLayer`).
    - Three lanes: full-width rows (top/bottom bars) or full-height columns (side bars), each a `Flow`. The board still sits on the bar's edge.
    - `shortLabel` removed; one `label()` everywhere, which fixes the "Custom Widget:<id>" chip (`SectionLane.qml:202`).
    - Priority-badge toggle (drop order).
20. **Live chips.** `WidgetChip` hosts `Item { enabled: false }` → `BarWidgetHost { preview: true; barConfig: BarManager.previewConfig }` (the draft bar enriched at a fixed `Widget.px(26)`). The `DragArea` sits on top for drag, select and right-click. An empty widget shows its icon and label greyed. Chips stream in.
21. **Page.**
    - Inspector | library split: side by side, stacked when tall.
    - `BarsPanel` tabs (Layout, Surface, Widgets, Behaviour) via `StyledTabBar`.
    - Board header: Unsaved chip, Save/Discard, undo/redo.
    - Fit meter per section for the narrowest screen; clicking a crowded name selects it, with "Raise priority" / "Set max length".
    - Context menu: Edit, Hide/Show, Duplicate, Remove, Move to section/start/end, Add spacer before/after, Copy to bar.
    - Keys: Del, Ctrl+D, Alt+arrows, Esc.
    - LayoutOverrideField shows min/max only for `x-elastic` widgets.

## Docs and bookkeeping
- **Bar docs (rewrite):** `docs/dev/bar/{composition,bar-ends-pills,layering-and-corners,widget-shapes-runs,widget-style,display-styles,bar-editor}.md`. This also fixes the stale `widget-style.md` and `composition.md` text.
- **Other docs:**
  - `docs/dev/popouts/{pill-and-floating-bars,edge-attach,held-off-edge,submenus,surface-context}.md`
  - `docs/dev/features/dock.md`
  - `docs/dev/core/{schema-annotations,editors-pattern,shared-ui-pieces}.md`
  - `docs/recipes/{bar-widget,migration}.md` (and the skill copies)
  - `qml/components/bar/widgets/AGENTS.md` (thickness; Separator and Spacer have no popout)
  - `qml/services/AGENTS.md` (EditHistory)
  - `docs/usage.md`
- **issues.md:**
  - Remove, with their roadmap links, in the fixing commits:
    - "A bar made while the bar editor is open…"
    - "Removing or copying another bar…"
    - "The pill merge in BarContainer repeats BarLayout's…"
    - "Missing test rows for two helper decisions"
  - Update "Media squeezed…" (size → maxSize).
  - Add: DockMenu could use StyledContextMenu; the other `x-auto` -1 settings could move to null.
- **Roadmap and live checks:**
  - Add a roadmap.md "Live checks" entry: solid↔pills switch moves nothing (border on and off, each compositor); auto-hide reveal, pin and fullscreen; a transparent bar's popout past a floating bar.
  - Republish the "Axiom Roadmaps" artifact after merge.

## Verification
- `scripts/dev/verify.sh` after every commit and `--all` before the PR. New qmltest rows: BarLayout, BarEnds, LayerStack, SurfaceContext, LibraryOrder. Go tests: v93, saved, pipeline, goldens.
- Read `scripts/log.sh` after reloads in a nested shell (`scripts/dev/nested.sh`, `qs ipc --pid`), never the live one. No warnings beyond the two reload lines.
- In the nested shell:
  - Migrate a copy of the live config (through `SavedConfigsManager.restore`, never `cp`).
  - Screenshot (`scripts/dev/shot.sh`) solid vs pills vs floating vs floating pills, with the border on and off, and compare offsets.
  - A spacer layout (`{spacer, media, spacer, rest}`), thickness 16/26/40, auto-hide reveal/toggle via `axiom ipc` against the nested pid.
  - The editor at top and side positions: undo, context menu, live chips, hover both ways.
- Wait for CI on the pushed sha before calling the PR ready.
