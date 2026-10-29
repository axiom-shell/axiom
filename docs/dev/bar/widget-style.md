# Bar widget classes, style and colors

> **Files:** `components/bar/widgets/base/BarIconWidget.qml`, `components/bar/widgets/base/BarWidget.qml`, `components/bar/widgets/base/AudioLevelWidget.qml`, `components/bar/widgets/base/BaseWidget.qml`, `components/methods/BarWidgetStyle.qml`, `components/methods/BarAutoColors.qml`, `config/BarsConfig.qml`, `config/BarStyle.qml`, `components/bar/widgets/Workspaces/WorkspaceCell.qml`
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
    - `hovered` is what an edge menu opened by a Button stays open for.
    - `dim` is for fades of the widget's own.
- **`ValueStyleWidget`** (a `BarIconWidget`) draws a widget's value in its display style, and `ValueGraphic` is that graphic alone ([Display styles](display-styles.md)).
- **`AudioLevelWidget`** (a `ValueStyleWidget`) is shared by Volume and Microphone.
- **`bar/widgets/base/BarWidget.qml`** is the base for widgets that draw their own content. It has the same inputs plus `isVertical`.
- **`base/BaseWidget`** is the sizing and background wrapper under both.
- **`base/IconTextWidget`** (under `BarIconWidget`) lays the icon and label along the bar; a graphic of `leadLength` goes in its `lead` slot before the icon, or after it, where the label would be, with `leadAfterIcon` (a display style's ring, meters, ticker).

### Sizes come from the bar
- (Rule: `components/bar/widgets/AGENTS.md`, "Sized by the bar".)
- `BarsConfig.enrichBarConfig` derives `extent` from `widgetSize`, plus padding and whatever covers the bar.
- It resolves `fontSize` and `radius` from the bar's `overrideFontSize`/`overrideRadius`, else from Appearance's values and `Widget.radius`.

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
  - `activeColor` and `occupiedColor` hide under Plain. `emptyColor` shows only when filled, tinted, outlined or underlined.
  - `textColor` shows only when filled and the bar's text color is Auto.
  - Cells follow the widget shape: pills under capsule (`BarsConfig.cellRadius`), otherwise the radius less the inset.
- The bar's own look fields read the look it uses too (`BarsPanel` hands its form `BarsConfig.lookOf(bar)`). The separator fields hide in a boxed powerline, where `enrichBarConfig` drops separators.

### Shared and per-bar style (`BarStyle`)
- A bar's widget style, accents and shadow are a `BarStyle`: the shared one is `Bars.style` (shown in Look & Feel, reader `BarStyle`), and each bar has its own `style` (`x-inherit: Bars.style`) whose keys it leaves `null` take the shared one's.
- `BarsConfig.lookOf` fills a bar's look from both before `enrichBarConfig`, its shadow as flat `shadow` / `shadowColor` / `shadowSize`. `fontSize` and `widgetRadius` stay `null` where both leave them (Appearance's and Widget's then).
- The bar editor shows the style by `x-group` (`BarsConfig.styleGroups`, from `SchemaLayout.objectGroups`), each with a "This bar's own" switch: `BarManager.ownsStyle` / `setStyleOwned` (copies what it inherits, or sets the group back to `null`) / `updateStyleField`.

### Workspaces cells
- Workspaces sits on a background like the rest (`backgroundColor`). Its box is Auto (`neutral`).
- Its cells (`workspaces/WorkspaceCell`) are inset by `widgetSpacing` inside that box.
- A hovered cell's box is `hoverColor` (`BarsConfig.cellHoverColor`; Auto is `Theme.backgroundHighlight`). On the bar, a cell reads hover from the widget's hit area (`hitArea.hovers(cell)`), which lies over the cells: their own `MouseArea` misses the leave after a click and stays lit. In a popout it uses its own.
- Cells draw in the same style through `BarsConfig.cellColors` → `BarWidgetStyle.cell`, which gives `{ fill, stroke, indicator, content }` from the cell's state color.
  - **Filled, tinted or outlined** styles draw boxes.
  - **Styles with no box** (underline, colored icons, plain) draw the cell's number or a dot straight on the bar. The dot becomes a pill when wide, with the cells narrowed to fit.
    - For underline, each cell is underlined itself and the widget's own line is off.
    - An empty cell's content is the bar text, faded.
    - Plain tells the states apart by fading alone.
