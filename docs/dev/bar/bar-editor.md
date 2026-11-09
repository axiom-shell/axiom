# Bar editor

> **Files:** `qml/components/views/BarEditor/BarEditor.qml`, `qml/components/views/BarEditor/` (`BarsPanel`, `BarDragLayer`, `SectionsBoard`, `SectionLane`, `WidgetChip`, `WidgetInspector`, `LayoutOverrideField`), `qml/services/ui/BarManager.qml`, `qml/services/ui/EditsManager.qml`, `qml/components/bar/BarContainer.qml`
> **Config:** `Bars` (edited through BarManager's draft)
> **Related:** [Editors pattern](../core/editors-pattern.md), [Bar style block](style-block.md), [Bar composition](composition.md), [Layouts editor](../overlay/layouts-editor.md)

The BarEditor overlay page: the bar list and its settings under tabs, the sections board, the widget inspector beside the widget library, plus the live reports the running bars send back while it's open.

### Layout of the page
- `views/BarEditor/BarEditor.qml`, with its pieces in `views/BarEditor/`. It follows the shared [editor pattern](../core/editors-pattern.md).
- `BarsPanel`, `SectionsBoard` and `WidgetInspector` are streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)), as are the panel's field groups and each form field. The board's loader takes its height from the board (`board.implicitHeight`), so it settles a moment after the page shows.
- **Left: `BarsPanel`.**
  - Save and Discard in its header (shown while the draft differs), above the bar list.
  - The bars, with duplicate and remove.
  - The selected bar's settings under four tabs (`StyledTabBar`; the tab is `BarManager.panelTab`, kept while the page is rebuilt), each showing schema groups by their `x-group` title (`BarsConfig.editorTabs`; a `BarEditor:<key>` page link shows the tab holding that bar field, `BarManager.showBarField`): **Layout** (Placement, Size, and any Bar group no tab names), **Surface** (Surface), **Style** (the Bar style block: the style's Look, Size, Colors, Accents and Shadow, the tab's `styles`), **Behaviour** (Behaviour). Only the shown tab's groups are built.
    - Their form reads `BarsConfig.lookOf(bar)`, so a look field's `x-showIf` sees what the bar draws, even from a group it doesn't override.
    - Each field has its change marks (`FieldChangeMarks` through the form's `changedAt`): a dot while it differs from the saved bar (`BarManager.barFieldChanged` / `styleFieldChanged`; clicking it puts the saved value back, `discardBarField` / `discardStyleField`), and a reset to the schema default.
  - The Surface group's header copies the bar's look (`BarManager.styleKeys`: its style and its Size and Surface settings) and pastes it onto one bar or onto all. The copied style follows its bar by index.
  - **The Style tab** is the settings page's Bar style block (`views/Settings/BarStyleBlock`, [style block](style-block.md)) over the selected bar's look (`BarsConfig.lookOf(bar, BarManager.localStyle)`, its shadow as its object again), streamed in as one `FieldGroup`. Its tiles' samples take the selected bar's spacing; at the panel's width its sections stack in one column.
    - **Shared or the bar's own, per section** (the style groups, `BarsConfig.styleGroups`): each section's heading has a "This bar's own" switch (`owned`, `BarManager.ownsStyle(index, keys)`: true while the bar sets any of the section's keys). Turning it on gives the bar all of them, filled from the shared style; off hands them all back (`setStyleOwned`). An owned section with some keys still null (`ownsAllStyle` false: a bar saved before Colors held the gradient) says "Some of these follow the shared style." with a "Make all this bar's own" button, which owns the rest (`setStyleOwned(keys, true)`: a key already set keeps its value). A shared section collapses to its heading, "Shared with every bar." and a `SettingsLink` to the shared `Bars.style` on the settings page (its Bar style card); its form isn't built (the style's options go with Look).
    - Edits go to `BarManager.updateStyleField` (the shadow's by part, `"shadow", value, part`), change marks to `styleFieldChanged` / `discardStyleField`, so each field's edit is an undo step as everywhere in the editor.
- **Right: `BarDragLayer`.** It holds `SectionsBoard` across the top, as deep as its rows (`board.implicitHeight`), whatever the bar's edge, with `WidgetInspector` under it. A side bar's board is drawn as a top bar's; only its sections' names follow its direction (`barVertical`: Top, Center, Bottom).
  - `WidgetInspector` shows two cards, both always: the inspector (about 55%) and the widget library, side by side, or one over the other when its room is taller than wide (`stacked`).

### Sections board
- Three `SectionLane`s, rows one under another, for every bar.
- Each lane's `WidgetChip`s are a `Flow` that wraps into more rows, never scrolling. Its `indexAt` reads both axes: before the first chip on a later row than the point, or on its row past it. A line shows where the carried chip would land.
- Chips are dragged within and between lanes, or dropped in from the library. While a chip from a lane is carried, the board's `TrashTarget` ("Drop to remove") shows centred between its title and the first section, over the header and fit line.
- Each chip is its widget, live (`WidgetChip`): alone in a `WidgetGroup` with `preview: true` (its host a preview, never outlined for the editor) under an `enabled: false` item, so its background takes the bar's look as a lone widget's in a section does (its caps and their room, split's icon part, a merged run's background, Workspaces' segments), drawn on `BarManager.previewConfig` (the draft bar enriched at a fixed `Widget.px(26)` thickness, along a top edge whatever its own, with stub ends). Its properties come from that config's `widgets`, so its Auto colours are the bar's. Each streams in (`StreamedLoader`) a moment after the board. A widget showing nothing (a spacer, no tray icons) shows its type's icon and label greyed, as the drag's ghost does (no widget). With no screen, a widget that reads its screen (Workspaces) draws as on none.
- One label everywhere: `BarDragLayer.label(type)` (the type info's `label`, a custom widget's own name), by the widget's library key (`libraryKey`: `CustomWidget:<id>` for a custom widget) on chips, the inspector's title and the fit line (`widgetLabel`).
- The header (`CardHeader`, no actions of its own): undo and redo (`UndoRedoButtons` over `BarManager.history`), the drop order switch, an Unsaved chip, and the help in its "?" (`help`).
  - The drop order switch badges each chip with its place in the order a crowded bar drops widgets in (`BarLayout.dropOrder`, lowest priority first, ties right, left, center and the last listed first; spacers and hidden widgets never drop). It reads `BarManager.priorityOf(widget)`: `layout.priority`, else the type's own (`BarsConfig.defaultPriority`).
- **Fit.** Under the header, the screens the bar fits on ("Fits DP-1"), or per screen "No room on DP-1 for" and each widget hidden there as a button selecting it. While a selected widget has no room somewhere (`selectedCrowdedOn`, the narrowest such screen), two actions follow:
  - **Raise priority** (`BarManager.raiseWidgetPriority`): one above every other widget's on the bar, so it drops last.
  - **Set max length**, for an elastic widget only: caps its `maxSize` at its preferred length less its insets and its section's overflow there (`fittingMax`, from the report's `sections` and the selected `measure`); not offered when no cap would do.
- Each lane's header has a meter (`LevelMeter`, `SectionLane.fit`): how much of the section's room its widgets want on the narrowest screen (`narrowest`: the report with the least room in all), in the warning colour when they want more; its tooltip gives the pixels and the screen.
- A chip's right click selects it and opens its `StyledContextMenu`: Edit, Hide/Show, Duplicate, Remove, Move to each other section, Move to the start/end, Add a spacer before/after, Copy to bar ▸ (the other bars).
- Clicking a chip gives the board the keys: Delete, Ctrl+D, Alt+arrows (`BarManager.stepWidget`), Escape (deselect), Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y.
- Hovering a chip sets `BarManager.hoveredWidget` (outlined on the running bars); a chip whose widget a running bar has under the pointer (`BarManager.isBarHovered`) gets the hover look (`DragChip.highlighted`).

### Inspector
- With nothing selected it says how to pick one.
- Shows the widget's options, in its `x-order`, with `x-beside` fields paired (`OptionsGroup`'s `pairs`), each with its change marks (a dot while it differs from the saved widget, matched by id: `BarManager.widgetPropertyChanged` / `discardWidgetProperty`).
  - Their `x-showIf` can read the selected bar's look as `$bar.<key>` (`BarsConfig.lookContext`, passed as `context`), so colors the bar's style doesn't draw are hidden ([widget style](widget-style.md#which-color-fields-show)).
  - The links sit in the header, under its title (`InspectorHeader.links`, a wrapping row shown while `showsLinks`), so they never push the options down: what the widget opens (a `SettingsLink` with `widget`: for a Button opening an edge menu or page, `OverlayManager.openedBy`/`editOpenedBy` take it to the [layouts editor](../overlay/layouts-editor.md)), then the type's `x-link`s (`FieldLinks`). A palette button among the header's actions (a `SettingsLink` it follows) opens every bar's widget style (`Bars.style`).
- Options, then Sizing under it, each the inspector's full width.
- Shows the widget's Sizing: the `LayoutOverrideField`s from `BarsConfig.widgetLayoutSchema`. They are explained from, and start at, what the bar uses now (a size less its insets, which `maxSize`/`minSize` don't count; priority: else `BarManager.priorityOf`). The Repeater's model is the fixed key list, so an edit (which rebuilds the selected widget's config) never rebuilds a field mid-step. The minimum and maximum show only for an elastic widget (the type info's `elastic`, `x-elastic`); every widget has the priority.
- The widget library beside it: a click there adds to `BarManager.lastZone`, the section last selected or added to.
- Edits show live on the running bars.

### Undo and actions
- `BarManager.history` (an `EditHistory`) snapshots the draft's bars and the selection before every edit; the board calls its `undo()` / `redo()`. Field edits join by key (`bar:<bar>:<key>`, `style:…`, `widget:<bar>:<zone>:<index>:<key>`, `layout:…`), so typing or a stepper is one step; an edit that changes nothing records nothing. Loading or discarding the draft clears it.
- Actions on the selected widget for the board's menu and keys: `moveWidgetTo(zone, atEnd)`, `stepWidget(step)` (one place along the bar, into the next section at an end), `copyWidgetToBar(barIndex)`; and `raiseWidgetPriority(zone, index)`. Add a spacer is `addWidget(zone, "Spacer", index)`, Set max length `updateWidgetLayout(zone, index, "maxSize", value)`.
- Removing or duplicating a bar keeps the selection on its bar and widget; a removed or new bar's widgets start unselected.

### Live reports
- They are active while a BarEditor page is visible (`BarManager.watch(page)`/`unwatch`, a `ConsumerRegistry`: `editing`).
- The running bars outline the selected widget (`BarManager.isSelectedWidget(source, zone, index)` → `BarWidgetHost.highlighted`).
- They outline the widget hovered on the board the same way (`BarManager.hoveredWidget`, `isHoveredWidget` → `BarWidgetHost.hoverHighlighted`), and report the one under the pointer back (`BarWidgetHost.pointerHovered` → `WidgetGroup` → `BarManager.setBarHover`, read as `barHover` / `isBarHovered(zone, index)`), so its chip looks hovered.
- Each `BarContainer` reports `editorReport` to `BarManager.live` (`setLive(id, report)` when it changes and once it's made, so a bar made while the editor is open reports too; `clearLive(id, screen)` on destruction). A report holds:
  - `source`: the config id.
  - `screen`.
  - `hidden`: per section, the config indices `WidgetGroup.crowdedOut` hides for want of room.
  - `selected`: the highlighted host's `measure`, i.e. `policy`, `size`, `preferred`, `minimum`, `priority`, `insets` (what its `maxSize` doesn't count).
  - `sections`: per section name, `{ used, room }`: how long its widgets want to be with none hidden (`WidgetGroup.wantedLength`), and the most room it could have, the other sections as they are (`BarLayout.sectionRooms`: with `lockCenter` a side's half beside the center, less the outer group a center spacer pushes onto it).
- **Live widgets in the editor** (`WidgetGroup.preview` → `BarWidgetHost.preview`): a host with `preview: true` opens no menu popout; under an `Item { enabled: false }` it takes no input, with a `barConfig` from `BarsConfig.enrichBarConfig` (its `ends` stubbed) and `panel: null`.
- `BarManager.liveReports()` gives the selected bar's reports, one per screen. They feed:
  - the board's fit line and lane meters (above)
  - the chips' crowded badge
  - the inspector's sizing text.
- `BarContainer.widgetModel` keeps each widget's `configIndex`, since widgets hidden in config aren't on the bar; a widget drawn one box per item is several hosts with its one `configIndex` ([widget style](widget-style.md#boxes-one-per-item)), so they're selected, hovered and reported as one.
