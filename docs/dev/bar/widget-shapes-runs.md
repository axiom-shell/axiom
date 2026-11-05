# Bar widget shapes, runs, separators and accents

> **Files:** `qml/components/bar/WidgetGroup.qml`, `qml/components/bar/WidgetBackground.qml`, `qml/components/methods/BarShapes.qml`, `qml/components/methods/BarLayout.qml`, `qml/components/methods/BarWidgetStyle.qml`, `qml/components/reusable/SeparatorMark.qml`, `qml/components/bar/BarContainer.qml` (inline `AccentLine`), `qml/components/bar/BarWidgetHost.qml`
> **Config:** `BarStyle` (or a bar overriding it): `widgetShape`, `widgetEnds`, `widgetGrouping`, `separatorStyle`, `shadow`, `accentLine`, `accentLineFade`. (`groupSpacing`, `shadowReach` are derived `barConfig` values.)
> **Related:** [Widget style](widget-style.md), [Bar composition](composition.md), [Layering and corners](layering-and-corners.md) (the border's shadow window), [Popout shadows](../popouts/shadows.md)

How widget backgrounds are drawn: their shapes, merged and powerline runs, hit testing in the drawn shape, separators at section ends, separator marks, the bar's shadow and the accent line.

### Backgrounds and shapes
- `WidgetGroup` draws a `bar/WidgetBackground` under each host that has one (`BarWidgetHost.background`). The background follows the host's geometry and `contentOpacity`.
- It is drawn in the bar's shape settings:
  - **`widgetShape`:** rounded, capsule, slanted or arrow.
    - Rounded takes the bar's widget radius. Qt caps a radius at half the thickness, so a radius that large draws the same as capsule.
    - Capsule is always a full pill, and so are the Workspaces cells inside it (`BarsConfig.cellRadius`).
  - **`widgetEnds`:** a slanted or arrow widget's (or run's) own ends. They can be shaped (an arrow's notched and pointed), pointed at both ends (an arrow's only, via `x-enumShowIf`), or rounded.
  - **`widgetGrouping`:** see Runs below.
- `methods/BarShapes` gives each widget two things:
  - **`segment`:** the widget's caps, and the room its content keeps clear of them. `WidgetGroup` sets this as the host's `leadInset`/`trailInset`, which are added to its sizes, and the module is inset by them.
  - **`path`:** the outline, as an SVG path. A `Rectangle` draws rounded and capsule ends.
- Insets follow what widgets have to show, never the room they're given (which the insets help decide), so they can't feed back into the layout. Shapes follow what's shown.

### Runs: merged and powerline
- Neighbouring widgets with backgrounds form runs (`BarLayout.runs`/`runPlaces`).
- **Merged** draws one background per run in `groupColor` (`BarsConfig.groupColors`). Its widgets' colors move to their icons (`BarWidgetStyle`'s `group`).
  - Widget insets keep their cap room, joined or not.
- A spacer given room splits runs, as it splits groups; a collapsed one is passed over.

### Joined sections
- A section boundary **joins** where a spacer pushed a widget against the next section (`BarLayout.sectionJoins`): left|center when the left side has a spacer or the center has one before its centered group, center|right when the right side has one or the center has one after it, left|right (no center) when either side has one, and the widgets facing the boundary are widgets (not a spacer, not a Separator). With `lockCenter` off, a spacer anywhere packs the sections end to end, so every such boundary joins. Center spacers and the unlocked layout: [Bar composition](composition.md).
  - For example, left `[a b spacer c]`, center `[d spacer e spacer f]`, right `[g spacer h i]` joins c to d and f to g, `e` staying centered.
  - It's decided from the config's shape and what each widget shows (its size without its insets, `WidgetGroup.joinMeasures`), never from where things land: a side with no spacer never joins, however close it's crowded. Widgets hidden for want of room still count.
  - A join never moves the center's centered group: with `lockCenter` it stays dead center.
- A joined boundary keeps the gap between a section's widgets (`groupSpacing`: none in a powerline, a separator mark's room with marks on) instead of the gap between sections (`BarLayout.boundaryGaps`, passed to `layoutSections`, `sectionRooms` and `overflowHidden`).
- Across it (`BarContainer.sectionJoins`, `WidgetGroup.joinStart`/`joinEnd`):
  - **A separator mark** is drawn in the gap, as between widgets in a section.
  - **The run carries on** where both widgets facing it have backgrounds (`chainStart`/`chainEnd`): `BarLayout.runPlaces` counts one more member past that end, so the widget takes a middle place. A merged background has no cap there and runs on over the gap (`joinEndReach`, `BarContainer.sectionReaches`, from the groups as drawn); a powerline segment ends in its join cap and the next section's first segment reaches back under it. Sections stack left over center over right (`Section`'s `z`) so the earlier segment draws on top.
  - A widget with no background facing it keeps `widgetGap` from it in a powerline, as inside a section.
- **Powerline** chains the widgets with no gap (`groupSpacing` 0).
  - Each segment's end cap runs into the next segment, which reaches back under it (`back`).
  - With a see-through fill (tinted or outline), the next segment fits against the cap instead.
  - An outline's two strokes lie on the shared seam (`seamStart`/`seamEnd`).
  - A segment's content is centred on the part of it that shows: from half a join before its box to half a join before its end. Its `trail` takes the difference.
- **What breaks a chain:**
  - A widget shown without a background (the Separator) splits a chain. It keeps `widgetGap` to the widgets beside it in its section.
    - At the section's end there is no spacing; the gap to the next section stands in, as on any bar.
  - A widget showing nothing (hidden) is passed over: `runs` flags it null.

### Background states
- The background follows a widget's `dim`, not its press fade. A press fade would show a powerline neighbour's square start through it.
- It draws the following, each in the widget's shape as it shows and inset all round:
  - **A press:** a tint of its text color (`pressed`).
  - **The hover outline:** for `hoverOutline` widgets (Button).
  - **The bar editor's highlight.**
- `shownStart` gives where the shape starts. A powerline segment's start is the cap before it, whatever that cap is drawn with.

### Hit shapes
- Widgets are hovered and clicked in the same shape they're drawn in. Slants and arrows therefore have no dead gaps, and no cut-off corners that answer for a neighbour.
- `WidgetGroup` hands each host that has a background its drawn segment (`hitShape`).
- The host keeps a `hitArea` item over the module:
  - It reaches `back` under the segment before it.
  - Its `mask` tests points with `BarShapes.contains`.
  - It tracks `hovered` with its own HoverHandler.
- `BarIconWidget`'s MouseArea reparents into the hit area, so clicks land in the shape.
- A `PopoutAnchor` given the widget's `hitArea` reads its `hovered`. Nothing under the hit area is itself hovered, so:
  - A widget with several anchors (the tray's icons) gives each one `hitArea.hovers(item)`.
  - The Workspaces switchers likewise pass the widget's hit area on to their anchors.
  - (A HoverHandler moved in after it's made isn't reliably hovered.)

### Separators at a section's end
- Separators at a section's end stand in the gap between sections rather than in their own section (`BarLayout.edgeHang`, from each group's `divides` widgets).
- The center section is centered without them (`layoutSections`' `centerHang`). `overflowHidden` reads `divides` from the measures itself.
- They're left out of the section's pill or island, except at the ends of the first and last sections showing, where they act as padding.
- So a Separator closing the center and one opening right-center look the same.

### Separator marks (accents)
- `WidgetGroup` draws a `SeparatorMark` in each gap between shown widgets (`separatorStyle`).
- A widget's `backgroundLevel` (0–1, -1 for none; the pill display style) is drawn by its `WidgetBackground` as the background's own shape in `backgroundLevelColor`, seen along the bar (up a vertical one) through a `ClippingRectangle` window: the background's cap where it starts, a rounded edge (a capsule's, else the bar's radius) where it stops, and full, the background's own end unless that's flat, so a level never stops square. The window overhangs the start by the bar's thickness, so a low level keeps inside the background's cap rather than squeezing its corners square. Its caps are `BarShapes.segment`'s `levelStartCap` / `levelEndCap`: the widget's own, except in a merged run, where they're the caps it would have alone (not the run's flat middle), so a pill looks the same merged as separate.
- No mark is drawn beside a widget that `divides` (the Separator), nor in a powerline.
- With marks on, the gap between a section's widgets is the mark's room along the bar plus `separatorGap` either side (`BarLayout.dividerGap`, as `groupSpacing` in `BarsConfig.enrichBarConfig`) instead of the bar's `spacing`.

### Bar shadow
- `BarContainer` paints the bar in one `surface` layer: its background, inner stroke and pills.
- A `shadow` (on or off) therefore follows their outline without redrawing for the widgets: a `MultiEffect` shadow spread evenly round it, in `shadowColor` (Auto: the accent).
- `shadowReach` widens the bar window on its inner side. The input mask stays the bar.
- `BarsConfig.shadowColor` resolves a shadow's color, both for the bar and for the border's inward shadow (see [Layering and corners](layering-and-corners.md#border-shadow-window)): `BarsConfig.shadowBaseColor`, capped at `Appearance.shadowAlphaMax` and premultiplied, as `MultiEffect` blends `shadowColor` (a color cleared by its alpha alone still adds its light). Windows matching axiom's shadow take `shadowBaseColor` ([window look](../compositor/window-look.md)).

### Accent line
- Above the shadow, an `AccentLine` (an inline component in `BarContainer`) runs along the bar's inner or outer edge (`accentLine`), fading into `accentLineFade`.
- It lies inside whatever stroke is there, or runs along each pill.
