# overlay
reviewed: 31af7d1 2026-10-31  (full)

Page loading, streaming, the grid maths and growing/expanding hold and match their docs; `GridPlacement` is well tested. What's open:
- Reopening the overlay mid-close leaves it open but hidden.
- A clean, hidden layout's problem can block the Layouts editor's Save.
- The five layouts drafts are listed by hand in eight places.
- A few small shrinks.

The maintainer asked for a close look at module sizing; it turned up two likely causes of uneven borders, noted on the existing entry.

## Open findings
- Major: [Reopening the overlay while it closes leaves it open but hidden](../../docs/dev/issues.md#reopening-the-overlay-while-it-closes-leaves-it-open-but-hidden)
- Major: [A clean layout's problem blocks saving the others in the Layouts editor](../../docs/dev/issues.md#a-clean-layouts-problem-blocks-saving-the-others-in-the-layouts-editor)
- Cleanup: [The five layouts drafts are listed by hand in eight places](../../docs/dev/issues.md#the-five-layouts-drafts-are-listed-by-hand-in-eight-places)
- Cleanup: [GridEditor's canAdd and canMove have no caller](../../docs/dev/issues.md#grideditors-canadd-and-canmove-have-no-caller)
- Cleanup: [Small shrinks in the overlay](../../docs/dev/issues.md#small-shrinks-in-the-overlay)
- Noted on existing entries: [Modules inside borders aren't sized evenly](../../docs/dev/issues.md#modules-inside-borders-arent-sized-evenly) (unrounded `rectPx` under `contentZoom`; `Card` doesn't pad, `Panel` does), and [The monitor prompt's padding is a bare 18 px, and check_sizes misses it](../../docs/dev/issues.md#the-monitor-prompts-padding-is-a-bare-18-px-and-check_sizes-misses-it) (the navigator's `inset: 6`).

Unrecorded (Minor):
- **grow-expand.md leaves out the desktop:** the docs say only the lock screen and greeter don't grow or expand, but the desktop's bounded grid (`ScreenLayoutView`, host kind `desktop`) doesn't either. Also, `expander` isn't null "for types the host's x-hosts don't take": `canExpand(type)` is what filters those.
- **The desktop's link chip and its row differ:** `OverlayManager._linkTargets.desktop.icon` is `wallpaper`, while `PagesSection` and `DesktopTarget` use `desktop_windows`.
- **ModuleGrid's header names only three hosts:** it lists Custom page, edge menu and lock screen, and leaves out the desktop, greeter and submenus.
- **With no visible page, a save moves the user off Layouts:** `OverlayPages.onCurrentIndexChanged` records `_onPinned` only while `viewsModel.length > 0`.

## Contract
These hold:
- Placement comes only from `GridPlacement`.
- `OverlayManager` edits a `ConfigDraft`, with selection through `selectView` / `GridEditor.select*`.
- Only the current page and its neighbours exist, and only while the window is visible; neighbours follow `_settled`.
- Pages are keyed by the views' JSON, and Layouts survives the rebuild (`_onPinned`).
- Page order is Custom, then tools, then Layouts.
- `fitScale` / `contentZoom` scale the views' container while the box keeps drawn px.
- Close on outside click comes only from `backgroundClicks` and `clickedOutside`.
- `reportArea` / `fitOf` drive the fits line.
- Growing is height only and towards the edge first (`growTowards`), set a tick later.
- Expanding stays in the grid, loads its content bare but padded, gets no `expander`, and dims and disables the modules.
- GridEditor's plans, push, 50-step undo and normalize work as grid-canvas.md says.
- `BuildQueueManager` runs visible owners first, within its 6 ms budget, and drops a job only after it runs.
- `StreamedLoader` streams only while `buildStreaming` or `always`.
- Repeater models come from config or counts.

## Coverage
Read deeply: OverlayPanel, OverlayPages, OverlayPage, OverlayView, OverlayGrid, OverlaySlot, ModuleGrid, ExpandedModule, OverlayPageNavigator, OverlayConfig, Custom, BaseView, Card, BuildQueueManager, StreamedLoader, Layouts, EditTarget, PageTarget and GridDragLayer. From OverlayManager, its drafts, links, areas, page edits and openers. From GridPlacement, `overlayLayout`, `zoomOf`, `revealOrder`, `grown`, `_freeTowards`, `trackSizes`, `rectPx` and `fitScale`.

Outlined: GridCanvas, GridEditor, Panel, LayoutsPanel, PagesSection, the screen-layout targets, and the rest of GridPlacement (uses and test rows counted).

Skipped: EdgeMenuEditor, MenuTarget, MenuOpening, MenusSection and OpenerButtons (edge-menus), TypePickerPopup (ui-kit), CanvasModule (beyond its known issue), ConfigDraft (config) and bench_overlay.sh. The next review should read GridCanvas's drawing and CanvasModule.

## History
- 2026-10-31 full: 5 findings recorded (2 Major, 3 Cleanup), 2 notes on existing entries, 4 Minor; recorded
