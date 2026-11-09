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
  - `accentColor`: its color for its current state, e.g. a critical battery or a muted mic. This used to be the background. A widget names the color field it shows (`accentField`, `backgroundColor` by default on `BarIconWidget`, none on `BarWidget`), and `accentColor` is that field's color; one with a color of its own for a state (DevMode's and Updates' failure, NextEvent's soon, a custom widget's state) sets `accentField` to `""` then and its `accentColor` itself.
- They draw in `colors` = `BarsConfig.widgetColors(barConfig, accent, foregroundName, widget)`, which gives `{ fill, stroke, indicator, text, icon, iconFill, gradient }`. `widget` is what of the widget itself its look depends on: `splits` (Split), `hovered` (Fill on hover), `spot` and `auto` (the bar gradient); `BarsConfig._widgetStyle` puts them in the `style` the helper reads, so `BarWidgetStyle.colors(style, accent, own)` and `cell(style, color, own, state)` take one shape.
  - The pure `methods/BarWidgetStyle` works these out from the bar's `widgetStyle`: filled, tinted, outline, split, underline, colored icons or plain.
  - `widgetTextColor` overrides the automatic text color.
  - An outline is drawn in the bar's `outlineStroke` ([Shapes and runs](widget-shapes-runs.md#outline-strokes)).
  - The styles' own options, and how they combine with the shapes, runs and the bar gradient: [Split](#split), [Fill on hover](#fill-on-hover), [Bar gradient](#bar-gradient), [Combinations](#combinations); their shapes (split's parts, tabs, outline strokes): [Shapes and runs](widget-shapes-runs.md).
- Colors that are content rather than a background stay the widget's own: workspace cells, separators, badges, the DND icon.
- `backgroundLevel` (0–1, -1 for none) with `backgroundLevelColor`: a level its WidgetGroup fills the background's shape to (the custom widget's pill), in the background's caps with a rounded leading edge ([Shapes and runs](widget-shapes-runs.md)). A graphic a widget draws itself reads in `colors.icon`, which contrasts with a filled background.

### Split
- `widgetStyle: split` sets a widget's icon part apart from its label (`BarWidgetStyle.colors`' `split` case). The icon part (the icon, and a lead graphic: a display style's ring, sparkline or ticker) is filled with the widget's color (`iconFill`), its icon in `own`.
- `splitIcon` joined: one box round the whole widget, cut at the icon part's end by `splitDivider` ([Shapes and runs](widget-shapes-runs.md#split)). The label's part (`splitLabelFill`) is a tint of the color (`tintOpacity`), a color of its own (`splitLabelColor`, its text reading on it) or none (the bar's); its text is the widget's color on a tint or none. `widgetTextColor` overrides both texts.
- `splitIcon` badge: no box; a small shape behind the icon part, the label on the bar in the widget's color. A badge has no box to chain or hang: its powerline draws as separate and a separate badge isn't offered the tab shape.
- Only an `IconTextWidget` showing an icon (or a lead graphic) and a label splits (`IconTextWidget.splits`, which `BarIconWidget` hands `widgetColors` in `widget`). Icon-only and text-only widgets, and every `BarWidget` (Workspaces, the tray, Media, …: `widgetColors` called without `splits`), draw as filled (`BarWidgetStyle.drawnFill`), and so do Workspaces' cells (`cell`'s `split` case). In a merged run such a widget fills its own box (in the caps it has alone, as a level), so the run reads as a row of tabs like the split widgets' icon parts, rather than showing only a colored icon or colored text on the run.
- **Merged:** each widget keeps its own icon part on the run's `groupColor`, its label reading on the run (`splitLabelFill` is hidden). **Powerline:** each segment has its own icon part.
- A split bar's widgets keep `BarsConfig.enrichBarConfig`'s `splitRoom` between the two parts instead of `spacing` (`BarShapes.splitRoom`: joined, the padding either side of the divider and its depth; a badge, its reach `badgePad` plus the spacing).

### Fill on hover
- `hoverFill` (shown for tinted and outline: the boxed styles that aren't filled already; not split, which is filled where it shows its color) fills a widget under the pointer with its color, its text and icon turning to its own text color (`own`), as if filled.
- The decision is `BarWidgetStyle.fillsOnHover`; `colors()` reads `style.hovered` (`BarsConfig.widgetColors`' `widget` holds it), and the widget passes its hit area's `hovered` (`BarIconWidget`, `BarWidget`), so the background, text and icon all follow one output. With the option on, an unfilled outline's fill is its color cleared, so the fill fades in (`ColorGlide`, `animFast`) from nothing rather than through black.
- In a merged run only the hovered widget's own part fills, in the caps it has alone (`levelStartCap` / `levelEndCap`, as a level), its outline left to the run; a press tints that part on top.
- A `BarWidget` opts out with `fillsOnHover: false`: Workspaces, whose cells fill instead.

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

### Bar gradient
- `gradient` (`gradientFrom`, `gradientVia` (optional, halfway), `gradientTo`; group "Bar gradient", hidden under Plain text) runs one gradient along the whole bar, left to right (top to bottom on a vertical bar). `enrichBarConfig` gives it as `gradientColors` (the names, start to end, or null: off, or plain).
- It's measured against the bar's full length (`BarContainer.length`), not its first to last widget, so its colors don't shift when widgets come and go. Places are the layout's (`Section.mainPos`, `allocation.offsets`), never the gliding ones, so nothing re-reads them each frame of a glide: `WidgetGroup.barStart`/`barLength` → each host's `barStart`/`barLength` → its module's `barOffset`/`barLength`, from which the module works out `barSpot`, where its middle sits (0–1).
- **Only an Auto own color gives way to it.** `BarsConfig.withAutoColors` hands each widget its Auto fields' roles (`autoColors`, `{ key: role }`), and `accentAuto` is whether its `accentField` is Auto with the `accent` role. A color set on the widget, and its state colors (the other roles: alt, off, warning, critical; a recording, a low battery), keep theirs.
- `BarWidgetStyle.colors` then draws the widget in the gradient's color at `barSpot` (its text readable on it), and says in `gradient` what of its background shows the gradient itself (`gradientPart`: the fill when filled, the tint when tinted, the stroke when outlined (every `outlineStroke`: `OutlineStroke` takes the slice too), the line when underlined, split's icon part (`iconFill`: the joined part's shape or the badge, each its own slice of the widget's); null under colored icons, whose icon takes the color where it sits). A widget filled on hover fills with its slice in full. `WidgetBackground` draws its slice of it there (`BarWidgetStyle.gradientSlice`: three stops from where it starts to where it ends along the bar, `gradientStart`/`gradientEnd`), in a path shape (a `Rectangle`'s border takes no gradient) or, for the line, a `Rectangle`'s gradient.
- **A merged run** is one gradient strip in place of `groupColor` (hidden while the gradient's on): its run background takes the slice from the run's start to its end (`BarsConfig.groupColors` with the run's middle). Its widgets' labels read on the strip where they sit, and an Auto icon too (through a tint or outline it takes the gradient's color there); a set or state color stays on its icon. A split run's strip is its labels' tint (`tintOpacity`, `groupColors`' `run`), under the widgets' icon parts (and the boxes of those that don't split), each its own slice in full, so the row of tabs still reads; its labels are in the widget's color, as on split's own tint.
- **Workspaces**: the active cell takes the gradient's color where its middle sits, its `activeColor` Auto (`WorkspaceCellRow._activeLook`, through `BarWidget.barSpotOf`, which maps a point in the widget to the bar). The box (Auto `neutral`) and the other cells keep theirs, and so does the active cell in a merged run, which is a strip of the gradient itself (the cell would vanish into it).
- With no place on a bar (the bar editor's chips and the custom widget preview) a widget shows its Auto color.

### Combinations
How the four widget-style features meet (each decided in `BarWidgetStyle` or `BarShapes`, with test rows):
- **Split + tab:** both parts reach the edge the tab hangs from; the divider keeps its shape (`BarShapes._tabSideCap`). A badge has no box: a separate badge isn't offered tab.
- **Split + gradient:** the icon part (or badge) takes its slice; in a merged run see Bar gradient above. **Split + powerline:** each segment its own icon part (a badge draws as separate).
- **Split + Fill on hover:** not offered (split is already filled where it shows its color).
- **Tab + outline strokes:** every stroke is open along the edge (dashed, dotted, double, ends only: [Shapes and runs](widget-shapes-runs.md#outline-strokes)). **Tab + Fill on hover:** the hovered tab fills in its own shape, out to the edge. **Tab + gradient:** each tab its slice, fillets included. Tabs never chain as a powerline.
- **Gradient + outline strokes:** the stroke takes the slice in every stroke. **Gradient + Fill on hover:** the hovered widget fills with its slice.
- **Merged + Ends only:** a mark at the run's two ends only.

### Which color fields show
- A widget's color fields show in the bar editor's inspector only in the bar looks where they draw something.
  - Their `x-showIf` reads the look of the selected bar through `$bar.<key>` keys. The values come from `BarsConfig.lookContext`: `lookOf`, with grouping counted only for boxed styles.
  - `tst_SchemaLayout` (`test_real_schema_showIf_targets_exist`) checks that each such key names a `BarStyle` field, in a bar widget's options only.
- **The widget's own color** (`backgroundColor` titled "Color", and its state colors). It is the fill when filled, the tint or outline when tinted or outlined, the icon part's fill (and the label's tint or text) when split, the line when underlined, and the icon when merged or under colored icons.
  - Hidden under Plain text.
  - A widget with no icon (Time, the tray's box) shows it only when boxed and not merged, or when underlined.
  - Notifications' DND and badge colors are content, so they always show.
- **`foregroundColor`.** It is read only by a filled widget that isn't merged, a split one (its icon on the icon part, merged or not), or a tinted or outlined one with Fill on hover (its text while filled), and only while the bar's `widgetTextColor` is Auto. Elsewhere the text is the bar's.
- **Workspaces** (its popouts draw cells in the same style):
  - `showBackground` shows only for boxed styles (split among them: `BarsConfig.boxedStyles`). `backgroundColor` also needs the background on and the grouping not merged.
  - `activeColor` and `occupiedColor` hide under Plain. `emptyColor` shows only when filled, tinted, outlined, split or underlined. `urgentColor` always shows: under Plain an urgent cell's content takes it. With `solidBoxes` on, the active, occupied and empty colors show under every style.
  - `textColor` shows only while the bar's text color is Auto, when filled or split and the cells show numbers, dots, labels of one's own, names or the grid's arrow, or with `solidBoxes` on.
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
- Cells draw in the same style through `BarsConfig.cellColors` → `BarWidgetStyle.cell`, which gives `{ fill, stroke, indicator, content, showsHover }` from the cell's state color; `cellColors`' last argument is an options object (`{ hovered, spot, solid }`).
  - **Filled, tinted or outlined** styles draw boxes (`workspaces/CellBox`, the cell's and the sliding active box's), an outline in the bar's `outlineStroke`, with the cell's label (`labels`: its number, a small dot, or nothing) inside; split draws them filled.
  - **Fill on hover:** a lit cell (`lit`, handed to `cellColors` as `{ hovered }`) fills with its state color, its content in its own text color, and `showsHover` tells the cell to draw no `hoverColor` box of its own. The sliding active box takes the hover while the active cell is lit. Solid boxes are filled already: they keep the `hoverColor` box.
  - **Styles with no box** (underline, colored icons, plain) draw the cell's number or a dot straight on the bar, or for `labels: none` only underline's line (colored icons and plain, with no line, draw a dot; the option is hidden there). The dot becomes a pill when wide, with the cells narrowed to fit (for `none` too).
  - `showAppIcons` puts app icons in place of the label on occupied cells, under every compositor, laid out by `appIconsLayout`: `largest` the biggest window's alone; `row` up to `appIconsMax` icons side by side along the bar, the cell growing to fit (`WorkspaceCells.rowLength`), packed in its middle; `square` up to four in a block the size of a normal cell, which never changes size (one full size, two half size side by side, three as two over one, four a 2×2: `WorkspaceCells.squareSlots`, filled top left, top right, bottom left, bottom right). Row and Square choose by size and order by place (`WorkspaceCells.chosen`): the biggest windows up to the limit, each app once by its biggest window (`CompositorManager.windowsBySize` + `WorkspaceCells.distinctApps`), or with `appIconsCount: windows` every window counting (three terminals, three icons), then in the order they sit on screen: on a strip monitor strip order (`CompositorManager.stripWindows`, vertical strips too), elsewhere left to right by x, then top to bottom (`WorkspaceCells.byPosition`, floating windows by their own place); an app sits at its biggest window's place. No "+n" marker. On a vertical bar the row runs along the bar; the square is the same block. A label of one's own (`workspaceLabels`) wins over it, and it over a compositor name (`useNames`): [Workspaces](../hyprland/workspaces.md) › The bar widget.
    - For underline, each cell is underlined itself and the widget's own line is off.
    - An empty cell's content is the bar text, faded.
    - Plain tells the states apart by fading alone, but for urgent, whose content takes `urgentColor`.
  - **Solid boxes** (`solidBoxes`): every cell (active, occupied, urgent, empty) is a box filled with its state's color on any bar style, its outline and line (where the bar's style draws them) in that color too (`BarsConfig.cellColors(…, { solid })` → `BarWidgetStyle.cell` with `fill: "solid"`; an Auto active color still takes the bar gradient, and an outline bar's `outlineStroke` draws in the fill's color). Its content takes the color that reads on the fill, as filled's (`textColor` for active, occupied and urgent; the theme's foreground for empty), or the bar's text color where set. The cells count as boxed (`WorkspaceCell.solid`): square on every style, dots smaller, and the active box (`ActiveCellIndicator.solid`) slides on every style. Labels' None is offered with it on any style.
  - **Urgent** (the workspace shape's `urgent`): `BarsConfig.workspaceCellColors` gives it the `"urgent"` state in `urgentColor`, which beats occupied but not active; it colours the box, line or content as the other states do. With `urgentPulse` its box or line (its content where it has neither) fades in and out, every urgent cell of a row or popout in step (`workspaces/UrgentPulse`, one looping animation, running only while one is urgent and `Appearance.animations`). Where a cell has neither box nor line (plain, colored icons) and shows an app icon, a small dot in `urgentColor` at its corner shows it.
