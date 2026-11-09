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
- **`base/IconTextWidget`** (under `BarIconWidget`) lays the icon and label along the bar (an icon of several glyphs is one per line, stacked on a vertical bar and side by side `iconSpacing` apart on a horizontal one: the icon font's space is a whole icon wide), the label's figures (a digit's height) centred on the icon's middle (`iconMiddle`) on a whole pixel rather than its box, which holds the descent and sat it high; on a vertical bar the label is turned along it, or with `uprightLabel` small and upright under the icon (SystemStats' metrics, each one an IconTextWidget); a graphic of `leadLength` goes in its `lead` slot before the icon, or after it, where the label would be, with `leadAfterIcon` (a display style's ring, meters, ticker). Its label's digits are of equal width and it is measured with them as zeros, never under `minimumText` (a value's widest usual value, `"00%"`: only 100% widens it) and centred in that room, so a changing number never resizes the bar; the ticker and stacked's value (`ValueGraphic`) likewise. `textFormat` (Text.AutoText) is set to Text.PlainText by a widget showing text from outside (Next event's title), for the label, the ticker and both stacked lines.

### Sizes come from the bar
- (Rule: `qml/components/bar/widgets/AGENTS.md`, "Sized by the bar".)
- `BarsConfig.enrichBarConfig` derives `extent` and where the widgets sit across (`crossStart`) from `thickness` and `edgePadding` (`BarEnds.crossGeometry`: solid and pill bars alike).
- **What's inside scales with the bar's thickness** from how it's set at 26 px (`BarsConfig.referenceThickness`): `fontSize` is `Appearance.baseFontSize × thickness/26 × textScale/100`, and `innerPadding`/`innerGap` are the bar's settings × thickness/26 (rounded). At 26 px and 100% a bar looks as it always has; at 16 or 40 px its text, icons and spacing are that much smaller or larger, and everything drawn from them (graphics, cells, the stacked style's two lines, which shrink to fit a text scale too large for the bar) follows.
- `radius` is the look's `widgetRadius`, else `Widget.radius`.

### Widget style
- Widgets don't draw their own backgrounds. Each reports two things:
  - `hasBackground`: on by default for `BarIconWidget`, opt-in on `BarWidget`.
  - `accentColor`: its color for its current state, e.g. a critical battery or a muted mic. This used to be the background.
- They draw in `colors` = `BarsConfig.widgetColors(barConfig, accent, foregroundName, widget)`, which gives `{ fill, stroke, indicator, text, icon, iconFill }`.
  - The pure `methods/BarWidgetStyle` works these out from the bar's `widgetStyle`: filled, tinted, outline, split, underline, colored icons or plain.
  - `widgetTextColor` overrides the automatic text color.
  - An outline is drawn in the bar's `outlineStroke` ([Shapes and runs](widget-shapes-runs.md#outline-strokes)).
- **Fill on hover** (`hoverFill`, shown for tinted and outline: the boxed styles that aren't filled already) fills a widget under the pointer with its color, its text and icon turning to its own text color (`own`), as if filled.
  - The decision is `BarWidgetStyle.fillsOnHover`; `colors()` reads `style.hovered` (`BarsConfig.widgetColors`' `widget` holds it), and the widget passes its hit area's `hovered` (`BarIconWidget`, `BarWidget`), so the background, text and icon all follow one output. With the option on, an unfilled outline's fill is its color cleared, so the fill fades in (`ColorGlide`, `animFast`) from nothing rather than through black.
  - In a merged run only the hovered widget's own part fills, in the caps it has alone (`levelStartCap` / `levelEndCap`, as a level), its outline left to the run; a press tints that part on top.
  - A `BarWidget` opts out with `fillsOnHover: false`: Workspaces, whose cells fill instead.
- Colors that are content rather than a background stay the widget's own: workspace cells, separators, badges, the DND icon.
- **Split** sets a widget's icon part apart from its label (`BarWidgetStyle.colors`' `split` case):
  - The icon part (the icon, and a lead graphic: a display style's ring, sparkline or ticker) is filled with the widget's color (`iconFill`), its icon in `own`.
  - `splitIcon` joined: one box round the whole widget, cut at the icon part's end by `splitDivider` ([Shapes and runs](widget-shapes-runs.md#split)). The label's part (`splitLabelFill`) is a tint of the color (`tintOpacity`), a color of its own (`splitLabelColor`, its text reading on it) or none (the bar's); its text is the widget's color on a tint or none. `widgetTextColor` overrides both texts.
  - `splitIcon` badge: no box; a small shape behind the icon part, the label on the bar in the widget's color.
  - Only an `IconTextWidget` showing an icon (or a lead graphic) and a label splits (`IconTextWidget.splits`, which `BarIconWidget` hands `widgetColors` in `widget`). Icon-only and text-only widgets, and every `BarWidget` (Workspaces, the tray, Media, …: `widgetColors` called without `splits`), draw as filled (`BarWidgetStyle.drawnFill`), and so do Workspaces' cells (`cell`'s `split` case).
  - A split bar's widgets keep `BarsConfig.enrichBarConfig`'s `splitRoom` between the two parts instead of `spacing` (`BarShapes.splitRoom`: joined, the padding either side of the divider and its depth; a badge, its reach `badgePad` plus the spacing).
- `backgroundLevel` (0–1, -1 for none) with `backgroundLevelColor`: a level its WidgetGroup fills the background's shape to (the custom widget's pill), in the background's caps with a rounded leading edge ([Shapes and runs](widget-shapes-runs.md)). A graphic a widget draws itself reads in `colors.icon`, which contrasts with a filled background.

### Auto colors
- A widget color field with an `x-autoColor` role is Auto when empty, which is its default.
- `BarsConfig.enrichBarConfig` fills Auto fields in the widgets it hands out (`BarsConfig.withAutoColors`; the fields per type are in `BarsConfig.autoColorFields`). Widgets just resolve `properties.X`.
- The pure `methods/BarAutoColors` picks colors along the bar's shown widgets, every section in order. The roles are:
  - **`accent`:** the widget's own color, a base08–0F accent unlike its neighbours'. Fixed colors count as neighbours too. Every accent is used before any repeats, and an accent is kept apart from the widget's own warning/critical colors.
  - **`alt`:** a second state, as unlike its accent as possible.
  - **`warning`/`critical`:** the theme's `warning`/`error`.
  - **`off` and `neutral`:** the subtlest of base01–04 that still stands out. They are for an off state, or for a box whose content has its own colors (the tray's and Workspaces').
- Each color must stand out (WCAG contrast) from what it's seen on: the bar, or a filled or split merged run's `groupColor` (`BarWidgetStyle.autoContrast`).
  - A fill only has to show (contrast 1.3).
  - Text, strokes and icons have to read (contrast 3). Split's color is its icon part's fill, and also its label's text unless the label has a color of its own or sits on a merged run.
- Text colors are not Auto. Workspaces' cells are not Auto either, except the active one.

### Which color fields show
- A widget's color fields show in the bar editor's inspector only in the bar looks where they draw something.
  - Their `x-showIf` reads the look of the selected bar through `$bar.<key>` keys. The values come from `BarsConfig.lookContext`: `lookOf`, with grouping counted only for boxed styles.
  - `tst_SchemaLayout` (`test_real_schema_showIf_targets_exist`) checks that each such key names a `BarStyle` field, in a bar widget's options only.
- **The widget's own color** (`backgroundColor` titled "Color", and its state colors). It is the fill when filled, the tint or outline when tinted or outlined, the icon part's fill (and the label's tint or text) when split, the line when underlined, and the icon when merged or under colored icons.
  - Hidden under Plain text.
  - A widget with no icon (Time, the tray's box) shows it only when boxed and not merged, or when underlined.
  - Notifications' DND and badge colors are content, so they always show.
- **`foregroundColor`.** It is read only by a filled widget that isn't merged, or a split one (its icon on the icon part, merged or not), and only while the bar's `widgetTextColor` is Auto. Elsewhere the text is the bar's.
- **Workspaces** (its popouts draw cells in the same style):
  - `showBackground` shows only for boxed styles (split among them: `BarsConfig.boxedStyles`). `backgroundColor` also needs the background on and the grouping not merged.
  - `activeColor` and `occupiedColor` hide under Plain. `emptyColor` shows only when filled, tinted, outlined or underlined.
  - `textColor` shows only when filled or split and the bar's text color is Auto.
  - Cells follow the widget shape: pills under capsule (`BarsConfig.cellRadius`), otherwise the radius less the inset.
- The bar's own look fields read the look it uses too (`BarsPanel` hands its form `BarsConfig.lookOf(bar)`). The separator fields hide in a boxed powerline, where `enrichBarConfig` drops separators.

### Shared and per-bar style (`BarStyle`)
- A bar's widget style, accents and shadow are a `BarStyle`: the shared one is `Bars.style` (shown in Look & Feel, reader `BarStyle`), and each bar has its own `style` (`x-inherit: Bars.style`) whose keys it leaves `null` take the shared one's.
- `BarsConfig.lookOf` fills a bar's look from both before `enrichBarConfig`, its shadow as flat `shadow` / `shadowColor` / `shadowSize`. `widgetRadius` stays `null` where both leave it (Widget's then); `textScale` always has a value.
- The bar editor shows the style by `x-group` (`BarsConfig.styleGroups`, from `SchemaLayout.objectGroups`), each with a "This bar's own" switch: `BarManager.ownsStyle` / `setStyleOwned` (copies what it inherits, or sets the group back to `null`) / `updateStyleField`.

### Workspaces cells
- Workspaces sits on a background like the rest (`backgroundColor`). Its box is Auto (`neutral`).
- Its cells (`workspaces/WorkspaceCell`) are inset by `innerGap` inside that box.
- A hovered cell's box is `hoverColor` (`BarsConfig.cellHoverColor`; Auto is `Theme.backgroundHighlight`). On the bar, a cell reads hover from the widget's hit area (`hitArea.hovers(cell)`), which lies over the cells: their own `MouseArea` misses the leave after a click and stays lit. In a popout it uses its own.
- Cells draw in the same style through `BarsConfig.cellColors` → `BarWidgetStyle.cell`, which gives `{ fill, stroke, indicator, content, showsHover }` from the cell's state color.
  - **Filled, tinted or outlined** styles draw boxes (`workspaces/CellBox`, the cell's and the sliding active box's), an outline in the bar's `outlineStroke`; split draws them filled.
  - **Fill on hover:** a lit cell (`lit`, handed to `cellColors` as `{ hovered }`) fills with its state color, its content in its own text color, and `showsHover` tells the cell to draw no `hoverColor` box of its own. The sliding active box takes the hover while the active cell is lit.
  - **Styles with no box** (underline, colored icons, plain) draw the cell's number or a dot straight on the bar. The dot becomes a pill when wide, with the cells narrowed to fit.
    - For underline, each cell is underlined itself and the widget's own line is off.
    - An empty cell's content is the bar text, faded.
    - Plain tells the states apart by fading alone.
