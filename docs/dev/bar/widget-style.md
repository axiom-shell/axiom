# Bar widget classes, style and colors

> **Files:** `qml/components/bar/widgets/base/BarIconWidget.qml`, `qml/components/bar/widgets/base/BarWidget.qml`, `qml/components/bar/widgets/base/AudioLevelWidget.qml`, `qml/components/bar/widgets/base/BaseWidget.qml`, `qml/components/methods/BarWidgetStyle.qml`, `qml/components/methods/BarAutoColors.qml`, `qml/config/BarsConfig.qml`, `qml/config/BarStyle.qml`, `qml/components/bar/widgets/Workspaces/WorkspaceCell.qml`
> **Config:** `BarStyle.*`, `Bars.style.*`, per bar `style` (inheriting) and `widgetTextColor`, widget color fields with `x-autoColor`
> **Related:** [Bar composition](composition.md), [Widget shapes and runs](widget-shapes-runs.md), [Schema annotations](../core/schema-annotations.md)

The base classes bar widgets extend, where their sizes come from, and how their colors are worked out: widget style, Auto colors, the shared look groups, and the Workspaces cells.

### Widget base classes
- **`bar/widgets/base/BarIconWidget.qml`** is the base for icon + label widgets.
  - It takes the `BarWidgetHost` inputs `barConfig`/`panel`/`screen`/`properties`, orientation and the configured colors.
  - Override `backgroundColor` for states. `hidden` collapses a widget with nothing to show.
  - It owns their pointer handling:
    - `clickable` + `acceptedButtons` → `clicked(button)`. The widget dims while pressed, and clicking is off while it is hidden.
    - `scrollable` → `scrolled(steps)`.
    - `hovered` is what an edge menu opened by a Button stays open for, and what a tooltip opens on. A widget taking no clicks or scrolls reads it from its hit area (or its own HoverHandler without one).
    - `dim` is for fades of the widget's own.
  - A widget's hover tooltip is a `BarToolTip` (`widget`, `text`, `shown`, `rich`): a `StyledToolTip` on the bar's inner side, built only while hovered.
- **`ValueStyleWidget`** (a `BarIconWidget`) draws a widget's value in its display style, and `ValueGraphic` is that graphic alone ([Display styles](display-styles.md)).
- **`AudioLevelWidget`** (a `ValueStyleWidget`) is shared by Volume and Microphone.
- **`bar/widgets/base/BarWidget.qml`** is the base for widgets that draw their own content. It has the same inputs plus `isVertical`.
- **`base/BaseWidget`** is the sizing wrapper under both.
- **`base/IconTextWidget`** (under `BarIconWidget`) lays the icon and label along the bar (an icon of several glyphs is one per line, stacked on a vertical bar and side by side `iconSpacing` apart on a horizontal one: the icon font's space is a whole icon wide), the label's letters centred on the icon's middle (`iconMiddle`) on a whole pixel rather than its box, which holds the descent and sat lowercase low (`TextBandPadding`: on the x-height with lowercase in it, a digit's height without, the font's bands so it moves only when lowercase comes or goes; upright under the icon, unpadded; turned along a vertical bar, it centres across it the same way); on a vertical bar the label is turned along it, or with `uprightLabel` small and upright under the icon (SystemStats' metrics, each one an IconTextWidget); a graphic of `leadLength` goes in its `lead` slot before the icon, or after it, where the label would be, with `leadAfterIcon` (a display style's ring, meters, ticker). Its label's digits are of equal width and it is measured with them as zeros, never under `minimumText` (a value's widest usual value, `"00%"`: only 100% widens it) and centred in that room, so a changing number never resizes the bar; the ticker and stacked's value (`ValueGraphic`) likewise. `textFormat` (Text.AutoText) is set to Text.PlainText by a widget showing text from outside (Next event's title), for the label, the ticker and both stacked lines.

### Sizes come from the bar
- (Rule: `qml/components/bar/widgets/AGENTS.md`, "Sized by the bar".)
- `BarsConfig.enrichBarConfig` derives `extent` and where the widgets sit across (`crossStart`) from `thickness` and `edgePadding` (`BarEnds.crossGeometry`: solid and pill bars alike).
- **What's inside scales with the bar's thickness** from how it's set at 26 px (`BarsConfig.referenceThickness`): `fontSize` is `Appearance.baseFontSize × thickness/26 × textScale/100`, and `innerPadding`/`innerGap` are the bar's settings × thickness/26 (rounded). At 26 px and 100% a bar looks as it always has; at 16 or 40 px its text, icons and spacing are that much smaller or larger, and everything drawn from them (graphics, cells, the stacked style's two lines, which shrink to fit a text scale too large for the bar) follows.
- `radius` is the look's `widgetRadius`, else `Widget.radius`.

### Widget style
- Widgets don't draw their own backgrounds. Each reports two things:
  - `hasBackground`: on by default for `BarIconWidget`, opt-in on `BarWidget`.
  - `accentColor`: its color for its current state, e.g. a critical battery or a muted mic. This used to be the background.
- They draw in `colors` = `BarsConfig.widgetColors(barConfig, accent, foregroundName)`, which gives `{ fill, stroke, indicator, text, icon }`.
  - The pure `methods/BarWidgetStyle` works these out from the bar's `widgetStyle`: filled, tinted, outline, underline, colored icons or plain.
  - `widgetTextColor` overrides the automatic text color.
- Colors that are content rather than a background stay the widget's own: workspace cells, separators, badges, the DND icon.
- `backgroundLevel` (0–1, -1 for none) with `backgroundLevelColor`: a level its WidgetGroup fills the background's shape to (the custom widget's pill), in the background's caps with a rounded leading edge ([Shapes and runs](widget-shapes-runs.md)). A graphic a widget draws itself reads in `colors.icon`, which contrasts with a filled background.

### Auto colors
- A widget color field with an `x-autoColor` role is Auto when empty, which is its default.
- `BarsConfig.enrichBarConfig` fills Auto fields in the widgets it hands out (`BarsConfig.withAutoColors`; the fields per type are in `BarsConfig.autoColorFields`). Widgets just resolve `properties.X`.
- The pure `methods/BarAutoColors` picks colors along the bar's shown widgets, every section in order. The roles are:
  - **`accent`:** the widget's own color, a base08–0F accent unlike its neighbours'. Fixed colors count as neighbours too. Every accent is used before any repeats, and an accent is kept apart from the widget's own warning/critical colors.
  - **`alt`:** a second state, as unlike its accent as possible.
  - **`warning`/`critical`:** the theme's `warning`/`error`.
  - **`off` and `neutral`:** the subtlest of base01–04 that still stands out. They are for an off state, or for a box whose content has its own colors (the tray's and Workspaces').
- Each color must stand out (WCAG contrast) from what it's seen on: the bar, or a filled merged run's `groupColor`.
  - A fill only has to show (contrast 1.3).
  - Text, strokes and icons have to read (contrast 3).
- Text colors are not Auto. Workspaces' cells are not Auto either, except the active one.

### Which color fields show
- A widget's color fields show in the bar editor's inspector only in the bar looks where they draw something.
  - Their `x-showIf` reads the look of the selected bar through `$bar.<key>` keys. The values come from `BarsConfig.lookContext`: `lookOf`, with grouping counted only for boxed styles.
  - `tst_SchemaLayout` (`test_real_schema_showIf_targets_exist`) checks that each such key names a `BarStyle` field, in a bar widget's options only.
- **The widget's own color** (`backgroundColor` titled "Color", and its state colors). It is the fill when filled, the tint or outline when tinted or outlined, the line when underlined, and the icon when merged or under colored icons.
  - Hidden under Plain text.
  - A widget with no icon (Time, the tray's box) shows it only when boxed and not merged, or when underlined.
  - Notifications' DND and badge colors are content, so they always show.
- **`foregroundColor`.** It is read only by a filled widget that isn't merged, and only while the bar's `widgetTextColor` is Auto. Elsewhere the text is the bar's.
- **Workspaces** (its popouts draw cells in the same style):
  - `showBackground` shows only for boxed styles. `backgroundColor` also needs the background on and the grouping not merged.
  - `activeColor` and `occupiedColor` hide under Plain. `emptyColor` shows only when filled, tinted, outlined or underlined. `urgentColor` always shows: under Plain an urgent cell's content takes it. With `solidBoxes` on, the active, occupied and empty colors show under every style.
  - `textColor` shows only while the bar's text color is Auto, when filled and the cells show numbers, dots, labels of one's own, names or the grid's arrow, or with `solidBoxes` on.
  - Cells follow the widget shape: pills under capsule (`BarsConfig.cellRadius`), otherwise the radius less the inset.
- The bar's own look fields read the look it uses too (`BarsPanel` hands its form `BarsConfig.lookOf(bar)`). The separator fields hide in a boxed powerline, where `enrichBarConfig` drops separators.

### Shared and per-bar style (`BarStyle`)
- A bar's widget style, accents and shadow are a `BarStyle`: the shared one is `Bars.style` (shown in Look & Feel, reader `BarStyle`), and each bar has its own `style` (`x-inherit: Bars.style`) whose keys it leaves `null` take the shared one's.
- `BarsConfig.lookOf` fills a bar's look from both before `enrichBarConfig`, its shadow as flat `shadow` / `shadowColor` / `shadowSize`. `widgetRadius` stays `null` where both leave it (Widget's then); `textScale` always has a value.
- The bar editor shows the style by `x-group` (`BarsConfig.styleGroups`, from `SchemaLayout.objectGroups`), each with a "This bar's own" switch: `BarManager.ownsStyle` / `setStyleOwned` (copies what it inherits, or sets the group back to `null`) / `updateStyleField`.

### Workspaces cells
- Workspaces sits on a background like the rest (`backgroundColor`). Its box is Auto (`neutral`).
- Its cells (`workspaces/WorkspaceCell`) are inset by `innerGap` inside that box, `spacing` apart (none, `innerGap` or twice it: `BarsConfig.workspaceCellSpacing`).
- A hovered cell's box is `hoverColor` (`BarsConfig.cellHoverColor`; Auto is `Theme.backgroundHighlight`). On the bar, a cell reads hover from the widget's hit area (`hitArea.hovers(cell)`), which lies over the cells: their own `MouseArea` misses the leave after a click and stays lit. In a popout it uses its own.
- Cells draw in the same style through `BarsConfig.cellColors` → `BarWidgetStyle.cell`, which gives `{ fill, stroke, indicator, content }` from the cell's state color.
  - **Filled, tinted or outlined** styles draw boxes, with the cell's label (`labels`: its number, a small dot, or nothing) inside.
  - **Styles with no box** (underline, colored icons, plain) draw the cell's number or a dot straight on the bar, or for `labels: none` only underline's line (colored icons and plain, with no line, draw a dot; the option is hidden there). The dot becomes a pill when wide, with the cells narrowed to fit (for `none` too).
  - `showAppIcons` puts app icons in place of the label on occupied cells, under every compositor, laid out by `appIconsLayout`: `largest` the biggest window's alone; `row` up to `appIconsMax` icons side by side along the bar, the cell growing to fit (`WorkspaceCells.rowLength`), packed in its middle; `square` up to four in a block the size of a normal cell, which never changes size (one full size, two half size side by side, three as two over one, four a 2×2: `WorkspaceCells.squareSlots`, filled top left, top right, bottom left, bottom right). Row and Square choose by size and order by place (`WorkspaceCells.chosen`): the biggest windows up to the limit, each app once by its biggest window (`CompositorManager.windowsBySize` + `WorkspaceCells.distinctApps`), or with `appIconsCount: windows` every window counting (three terminals, three icons), then in the order they sit on screen: on a strip monitor strip order (`CompositorManager.stripWindows`, vertical strips too), elsewhere left to right by x, then top to bottom (`WorkspaceCells.byPosition`, floating windows by their own place); an app sits at its biggest window's place. No "+n" marker. On a vertical bar the row runs along the bar; the square is the same block. A label of one's own (`workspaceLabels`) wins over it, and it over a compositor name (`useNames`): [Workspaces](../hyprland/workspaces.md) › The bar widget.
    - For underline, each cell is underlined itself and the widget's own line is off.
    - An empty cell's content is the bar text, faded.
    - Plain tells the states apart by fading alone, but for urgent, whose content takes `urgentColor`.
  - **Solid boxes** (`solidBoxes`): every cell (active, occupied, urgent, empty) is a box filled with its state's color on any bar style, its outline and line (where the bar's style draws them) in that color too (`BarsConfig.cellColors(…, solid)` → `BarWidgetStyle.cell` with `fill: "solid"`). Its content takes the color that reads on the fill, as filled's (`textColor` for active, occupied and urgent; the theme's foreground for empty), or the bar's text color where set. The cells count as boxed (`WorkspaceCell.solid`): square on every style, dots smaller, and the active box (`ActiveCellIndicator.solid`) slides on every style. Labels' None is offered with it on any style.
  - **Urgent** (the workspace shape's `urgent`): `BarsConfig.workspaceCellColors` gives it the `"urgent"` state in `urgentColor`, which beats occupied but not active; it colours the box, line or content as the other states do. With `urgentPulse` its box or line (its content where it has neither) fades in and out, every urgent cell of a row or popout in step (`workspaces/UrgentPulse`, one looping animation, running only while one is urgent and `Appearance.animations`). Where a cell has neither box nor line (plain, colored icons) and shows an app icon, a small dot in `urgentColor` at its corner shows it.
