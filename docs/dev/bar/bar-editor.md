# Bar editor

> **Files:** `components/views/BarEditor/BarEditor.qml`, `components/views/BarEditor/` (`BarsPanel`, `BarDragLayer`, `SectionsBoard`, `SectionLane`, `WidgetChip`, `WidgetInspector`, `LayoutOverrideField`), `services/ui/BarManager.qml`, `services/ui/EditsManager.qml`, `components/bar/BarContainer.qml`
> **Config:** `Bars` (edited through BarManager's draft)
> **Related:** [Editors pattern](../core/editors-pattern.md), [Bar composition](composition.md), [Layouts editor](../overlay/layouts-editor.md)

The BarEditor overlay page: the bar list and field groups, the sections board and the widget inspector, plus the live reports the running bars send back while it's open.

### Layout of the page
- `views/BarEditor/BarEditor.qml`, with its pieces in `views/BarEditor/`. It follows the shared [editor pattern](../core/editors-pattern.md).
- `BarsPanel`, `SectionsBoard` and `WidgetInspector` are streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)), as are the panel's field groups and each form field. The board's loader takes its depth from the board (`board.implicitHeight`), so a horizontal strip settles a moment after the page shows.
- **Left: `BarsPanel`.**
  - The bars, with duplicate and remove.
  - The selected bar's field groups.
    - Their form reads `Bar.lookOf(bar)`, so a look field's `x-showIf` sees what the bar draws, even from a group it doesn't override.
  - The Style group's header copies the bar's look (`BarManager.styleKeys`: its Size and Style settings) and pastes it onto one bar or onto all. The copied style follows its bar by index.
- **Right: `BarDragLayer`.** It holds `SectionsBoard` along the side of the page the selected bar is on, with `WidgetInspector` beside it.
  - A horizontal bar gets a strip across the top or bottom. A vertical bar gets a column at the left or right.
  - The button beside the Widgets title stacks a horizontal bar's board as a column at the left (`EditsManager.barStacked`).
  - Three directions are tracked separately:
    - `BarDragLayer.vertical`: how the board is drawn.
    - `barVertical`: the bar's own direction, which names the sections.
    - `side`: the page edge the board is on.

### Sections board
- The board's five `SectionLane`s are laid out the way the bar lays out its sections (`BarLayout.layoutSections` over each lane's `naturalLength`/`minLength`).
- Each lane is a row or column of `WidgetChip`s that scrolls when it can't show them all.
  - Scrolling is by scroll bar, or by the wheel through the lane's `WheelHandler` (sideways on a horizontal lane).
  - The Flickable itself isn't interactive, so chips keep their drags.
- Chips are dragged within and between lanes, or dropped in from the library.

### Inspector
- Shows the widget's options, in its `x-order`, with `x-beside` fields paired (`OptionsGroup`'s `pairs`).
  - Their `x-showIf` can read the selected bar's look as `$bar.<key>` (`Bar.lookContext`, passed as `context`), so colors the bar's style doesn't draw are hidden ([widget style](widget-style.md#which-color-fields-show)).
  - For a Button opening an edge menu or page, `OverlayManager.openedBy`/`editOpenedBy` take it to the [layouts editor](../overlay/layouts-editor.md).
- Shows the widget's Sizing: the `LayoutOverrideField`s from `Bar.widgetLayoutSchema`. They are explained from, and start at, what the bar uses now.
- With nothing selected it shows the widget library. A click there adds to `BarManager.lastZone`, the section last selected or added to.
- Edits show live on the running bars.

### Live reports
- They are active while a BarEditor page is visible (`BarManager.watch(page)`/`unwatch`, a `ConsumerRegistry`: `editing`).
- The running bars outline the selected widget (`BarManager.isSelectedWidget(source, zone, index)` → `BarWidgetHost.highlighted`).
- Each `BarContainer` reports `editorReport` to `BarManager.live` (`setLive(id, report)`, and `clearLive(id, screen)` on destruction). A report holds:
  - `source`: the config id.
  - `screen`.
  - `hidden`: per section, the config indices `WidgetGroup.crowdedOut` hides for want of room.
  - `selected`: the highlighted host's `measure`, i.e. `policy`, `size`, `preferred`, `minimum`, `priority`.
- `BarManager.liveReports()` gives the selected bar's reports, one per screen. They feed:
  - the board's fit line ("Fits DP-1", or what has no room where)
  - the chips' crowded badge
  - the inspector's sizing text.
- `BarContainer.widgetModel` keeps each widget's `configIndex`, since widgets hidden in config aren't on the bar.
