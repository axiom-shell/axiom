# Bar editor

> **Files:** `qml/components/views/BarEditor/BarEditor.qml`, `qml/components/views/BarEditor/` (`BarsPanel`, `BarDragLayer`, `SectionsBoard`, `SectionLane`, `WidgetChip`, `WidgetInspector`, `LayoutOverrideField`), `qml/services/ui/BarManager.qml`, `qml/services/ui/EditsManager.qml`, `qml/components/bar/BarContainer.qml`
> **Config:** `Bars` (edited through BarManager's draft)
> **Related:** [Editors pattern](../core/editors-pattern.md), [Bar composition](composition.md), [Layouts editor](../overlay/layouts-editor.md)

The BarEditor overlay page: the bar list and field groups, the sections board and the widget inspector, plus the live reports the running bars send back while it's open.

### Layout of the page
- `views/BarEditor/BarEditor.qml`, with its pieces in `views/BarEditor/`. It follows the shared [editor pattern](../core/editors-pattern.md).
- `BarsPanel`, `SectionsBoard` and `WidgetInspector` are streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)), as are the panel's field groups and each form field. The board's loader takes its depth from the board (`board.implicitHeight`), so a horizontal strip settles a moment after the page shows.
- **Left: `BarsPanel`.**
  - The bars, with duplicate and remove.
  - The selected bar's field groups.
    - Their form reads `BarsConfig.lookOf(bar)`, so a look field's `x-showIf` sees what the bar draws, even from a group it doesn't override.
  - The Style group's header copies the bar's look (`BarManager.styleKeys`: its Size and Style settings) and pastes it onto one bar or onto all. The copied style follows its bar by index.
  - The style groups (`BarsConfig.styleGroups`) are shared with every bar until the bar takes its own; each links (`SettingsLink`) to its card in the shared `Bars.style` on the settings page.
- **Right: `BarDragLayer`.** It holds `SectionsBoard` along the side of the page the selected bar is on, with `WidgetInspector` beside it.
  - A horizontal bar's board runs across the top or bottom, as deep as its rows (`board.implicitHeight`). A vertical bar's is a column at the left or right, as wide as its lanes (at most half the page).
  - `BarDragLayer.vertical` (how the board is drawn) follows the bar's own direction (`barVertical`, which names the sections), and `side` (the page edge the board is on) is the bar's edge.

### Sections board
- Three `SectionLane`s: rows one under another for a top or bottom bar, columns side by side for a side bar, in a `GridLayout`.
- Each lane's `WidgetChip`s are a `Flow` that wraps (into more rows, or more columns), never scrolling. Its `indexAt` reads both axes: before the first chip on a later line than the point, or on its line past it. A line shows where the carried chip would land.
- Chips are dragged within and between lanes, or dropped in from the library.
- Each chip is its widget, live (`WidgetChip`): a `BarWidgetHost` with `preview: true` under an `enabled: false` item, on its `WidgetBackground`, drawn on `BarManager.previewConfig` (the draft bar enriched at a fixed `Widget.px(26)` thickness, along a top edge whatever its own, with stub ends). Its properties come from that config's `widgets`, so its Auto colours are the bar's. Each streams in (`StreamedLoader`) a moment after the board. A widget showing nothing (a spacer, no tray icons) shows its type's icon and label greyed, as the drag's ghost does (no widget). With no screen, a widget that reads its screen (Workspaces) draws as on none.
- One label everywhere: `BarDragLayer.label(type)` (the type info's `label`, a custom widget's own name), by the widget's library key (`libraryKey`: `CustomWidget:<id>` for a custom widget) on chips, the inspector's title and the fit line (`widgetLabel`).
- The header (`CardHeader`): undo and redo (`UndoRedoButtons` over `BarManager.history`), the drop order switch, an Unsaved chip with Save and Discard, and the help in its "?" (`help`).
  - The drop order switch badges each chip with its place in the order a crowded bar drops widgets in (`BarLayout.dropOrder`, lowest priority first, ties right, left, center and the last listed first; spacers and hidden widgets never drop). It reads `layout.priority`, else the type's own (`BarsConfig.defaultPriority`).
- A chip's right click selects it and opens its `StyledContextMenu`: Edit, Hide/Show, Duplicate, Remove, Move to each other section, Move to the start/end, Add a spacer before/after, Copy to bar ▸ (the other bars).
- Clicking a chip gives the board the keys: Delete, Ctrl+D, Alt+arrows (`BarManager.stepWidget`), Escape (deselect), Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y.
- Hovering a chip sets `BarManager.hoveredWidget` (outlined on the running bars); a chip whose widget a running bar has under the pointer (`BarManager.isBarHovered`) gets the hover look (`DragChip.highlighted`).

### Inspector
- Shows the widget's options, in its `x-order`, with `x-beside` fields paired (`OptionsGroup`'s `pairs`).
  - Their `x-showIf` can read the selected bar's look as `$bar.<key>` (`BarsConfig.lookContext`, passed as `context`), so colors the bar's style doesn't draw are hidden ([widget style](widget-style.md#which-color-fields-show)).
  - Under them, the type's `x-link`s and a link to every bar's widget style (`Bars.style`).
  - For a Button opening an edge menu or page, `OverlayManager.openedBy`/`editOpenedBy` take it to the [layouts editor](../overlay/layouts-editor.md).
- Shows the widget's Sizing: the `LayoutOverrideField`s from `BarsConfig.widgetLayoutSchema`. They are explained from, and start at, what the bar uses now.
- With nothing selected it shows the widget library. A click there adds to `BarManager.lastZone`, the section last selected or added to.
- Edits show live on the running bars.

### Undo and actions
- `BarManager.history` (an `EditHistory`) snapshots the draft's bars and the selection before every edit; `undo()` / `redo()`. Field edits join by key (`bar:<bar>:<key>`, `style:…`, `widget:<bar>:<zone>:<index>:<key>`, `layout:…`), so typing or a stepper is one step; an edit that changes nothing records nothing. Loading or discarding the draft clears it.
- Actions on the selected widget for the board's menu and keys: `moveWidgetTo(zone, atEnd)`, `stepWidget(step)` (one place along the bar, into the next section at an end), `copyWidgetToBar(barIndex)`; and `addSpacer(zone, index)`, `setWidgetPriority` / `setWidgetMax(zone, index, value)`.
- Removing or duplicating a bar keeps the selection on its bar and widget; a removed or new bar's widgets start unselected.

### Live reports
- They are active while a BarEditor page is visible (`BarManager.watch(page)`/`unwatch`, a `ConsumerRegistry`: `editing`).
- The running bars outline the selected widget (`BarManager.isSelectedWidget(source, zone, index)` → `BarWidgetHost.highlighted`).
- They outline the widget hovered on the board the same way (`BarManager.hoveredWidget`, `isHoveredWidget` → `BarWidgetHost.hoverHighlighted`), and report the one under the pointer back (`BarWidgetHost.pointerHovered` → `WidgetGroup` → `BarManager.setBarHover`, read as `barHover` / `isBarHovered(zone, index)`), so its chip looks hovered.
- Each `BarContainer` reports `editorReport` to `BarManager.live` (`setLive(id, report)` when it changes and once it's made, so a bar made while the editor is open reports too; `clearLive(id, screen)` on destruction). A report holds:
  - `source`: the config id.
  - `screen`.
  - `hidden`: per section, the config indices `WidgetGroup.crowdedOut` hides for want of room.
  - `selected`: the highlighted host's `measure`, i.e. `policy`, `size`, `preferred`, `minimum`, `priority`.
  - `sections`: per section name, `{ used, room }`: how long its widgets want to be with none hidden (`WidgetGroup.wantedLength`), and the most room it could have, the other sections as they are (`BarLayout.sectionRooms`: with `lockCenter` a side's half beside the center).
- **Live widgets in the editor** (`BarWidgetHost.preview`): a host with `preview: true` opens no menu popout; under an `Item { enabled: false }` it takes no input, with a `barConfig` from `BarsConfig.enrichBarConfig` (its `ends` stubbed) and `panel: null`.
- `BarManager.liveReports()` gives the selected bar's reports, one per screen. They feed:
  - the board's fit line ("Fits DP-1", or what has no room where)
  - the chips' crowded badge
  - the inspector's sizing text.
- `BarContainer.widgetModel` keeps each widget's `configIndex`, since widgets hidden in config aren't on the bar.
