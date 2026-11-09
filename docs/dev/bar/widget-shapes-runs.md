# Bar widget shapes, runs, separators and accents

> **Files:** `qml/components/bar/WidgetGroup.qml`, `qml/components/bar/WidgetDecorations.qml`, `qml/components/methods/BarRuns.qml`, `qml/components/bar/look/WidgetBackground.qml`, `qml/components/bar/look/LookBox.qml`, `qml/components/bar/look/ShapedBox.qml`, `qml/components/bar/look/OutlineStroke.qml`, `qml/components/methods/BarShapes.qml`, `qml/components/methods/BarTabs.qml`, `qml/components/methods/BarOutlines.qml`, `qml/components/methods/BarCells.qml`, `qml/components/methods/BarLayout.qml`, `qml/components/methods/BarWidgetStyle.qml`, `qml/components/reusable/SeparatorMark.qml`, `qml/components/bar/BarContainer.qml` (inline `AccentLine`), `qml/components/bar/BarWidgetHost.qml`
> **Config:** `BarStyle` (or a bar overriding it): `widgetShape`, `tabCorners`, `widgetEnds`, `widgetGrouping`, `splitIcon`, `splitDivider`, `outlineStroke`, `separatorStyle`, `shadow`, `accentLine`, `accentLineFade`. (`groupSpacing`, `shadowReach`, `tabFillet` are derived `barConfig` values.)
> **Related:** [Widget style](widget-style.md), [Bar composition](composition.md), [Layering and corners](layering-and-corners.md) (the border's shadow window), [Popout shadows](../popouts/shadows.md)

How widget backgrounds are drawn: their shapes (split's two parts, tabs, outline strokes among them), merged and powerline runs, hit testing in the drawn shape, separators at section ends, separator marks, the bar's shadow and the accent line. Which colors they're drawn in, the bar gradient included, is [Widget style](widget-style.md); how the styles, shapes and runs combine is its [Combinations](widget-style.md#combinations).

### Backgrounds and shapes
- `WidgetGroup`'s `WidgetDecorations` draws a `bar/look/WidgetBackground` under each host that has one (`BarWidgetHost.background`), placed by `BarRuns` (a merged run's background: `runBackground`; the separator marks: `marks`; a host's room: `insets`). The background follows the host's geometry and `contentOpacity`.
- It is drawn in the bar's shape settings:
  - **`widgetShape`:** rounded, capsule, slanted, arrow or tab.
    - Rounded takes the bar's widget radius. Qt caps a radius at half the thickness, so a radius that large draws the same as capsule.
    - Capsule is always a full pill, and so are the Workspaces cells inside it (`BarsConfig.cellRadius`).
  - **`widgetEnds`:** a slanted or arrow widget's (or run's) own ends. They can be shaped (an arrow's notched and pointed), pointed at both ends (an arrow's only, via `x-enumShowIf`), or rounded.
  - **`widgetGrouping`:** see Runs below.
  - **Tab** reaches from the widget out to the outer edge of what it sits on (see Tabs below).
- The shape helpers split by topic: `methods/BarShapes` (caps, segments, hit tests, the outline spec and box rects), `BarTabs` (tabs), `BarOutlines` (SVG outlines) and `BarCells` (a widget's parts as cells). They read the look's resolved fields (`look.shape`, `look.grouping`, its traits), never its style's name. Each widget gets:
  - **`segment`** (`BarShapes.segment`, from `look.shape`, `look.grouping` and the `opaque` trait): the widget's caps, and the room its content keeps clear of them. `WidgetGroup` sets this as the host's `leadInset`/`trailInset`, which are added to its sizes, and the module is inset by them.
    - **The room at a run's ends** (`BarShapes._clearOf`): how far in the inner edge of what's drawn there lies at the content's edges across, in whole pixels: the cap (a round corner's or capsule's curve, a slant's or arrow's side), inset by the outline's stroke (`strokeBand`: its width, a double's three, Ends only's end line). The content is its height across, centred, from the bar's sizes (never measured, so it can't feed back into the layout): a widget's an icon or label at the bar's `fontSize`, a Workspaces cell's its tallest label or app icon (`WorkspaceCells.contentSize`), a strip window's its app icon. `look.shape` carries the look's `radius` and `outline`, and `capped` (false where no box is drawn at the ends: an unboxed style, a separate badge), which keeps no room. A run's middle keeps none, and a powerline's joins keep half a join, as below. The widget's own `innerPadding` comes on top.
    - A Workspaces cell as a segment (`BarCells.cellSegment`) keeps clear of the stroke drawn at its end: a merged run's, else its own box's (`BarCells.cellOutline`: a double in half-width lines), none for a box of its own in a run (`boxed`: its stroke is its fill's color).
  - **Where its box lies** (`BarShapes.boxRect`): its host's rect, back under the one before, out to a tab's edge and on past a joined end. A widget's and a run's backgrounds, the host's hit area and its parts' clip, and a cell's box as a segment are each one.
  - **`path`** (`BarOutlines.path`, from one outline spec, `BarShapes.outline`: length, thickness, radius, caps, seams, tab, open ends): the outline, as an SVG path. A `Rectangle` draws rounded and capsule ends, except under the bar's gradient (a `Rectangle`'s border can't take one), where the path's `LinearGradient` (`ShapeSlice`; a `Rectangle`'s, `RectSlice`, for an underline or a split badge) fills or strokes the widget's slice; a tab and a stroke other than solid are paths too.
- Insets follow what widgets have to show, never the room they're given (which the insets help decide), so they can't feed back into the layout. Shapes follow what's shown.

### Split
- A split widget's host reports its parts (`BarWidgetHost.split`, from `IconTextWidget.splitAt` / `splitPart`): where the middle of the gap between its icon part and its label lies along it, and what the icon part holds. `WidgetGroup` hands them to its `WidgetBackground` (`splitAt`, `splitPart`), shifted by the segment's `back`.
- **Joined:** the label's part is the background's whole shape in `fill`; on a tab both parts reach the edge (see Tabs); the icon part is drawn over it in `iconFill`, from the background's start cap to the bar's `splitCap` centred on `splitAt` (`BarShapes.dividerCap`: `splitDivider` match is slanted for slant, an arrow for arrow, else straight; or straight, slant, arrow, or `curve`, a shallow arc a quarter of the thickness deep). The level, the press tint, the hover outline and the editor's highlight cover the whole shape.
- **Badge:** no box; a shape in `iconFill` round `splitPart`, `badgePad` out, at least as long as it's thick: a circle (or a pill round a lead graphic) under capsule, otherwise a square rounded by the widget radius scaled to its size.
- **Runs:** merged, each widget keeps its own icon part (or badge) on the run's `groupColor` (`groupColors` draws split's run filled), and `splitLabelFill` is hidden; a widget that doesn't split fills its own box there instead (its `levelStartCap` / `levelEndCap`), a tab in the row. Powerline chains the segments as usual, each with its own icon part; a segment counts as opaque (`BarLook`'s `opaque` trait) only when its label part has a color of its own. A badge has no box to chain: its powerline draws as separate (`BarLook.resolve`'s `grouping`) and isn't offered.

### Tabs
- A tab's background runs from the widget's inner side (the bar's edge padding kept) out to the edge it hangs from, `tabReach` past the widget (`WidgetGroup.tabReach`, from `BarContainer`). Where that edge is, per surface, is `BarEnds.tabEdge` (in from the bar window's outer edge):
  - **Solid bar:** the window's edge (the screen edge, or the bar outside it), border on or off.
  - **Pills:** a pill bar on the border reaches back over the frame (its pills one with it, `stripCover`), so its tabs run to the screen edge; a pill bar stacked inside another bar stops inside the stroke it lies on.
  - **Floating:** inside its island's stroke, not the screen.
  - **No surface:** inside the rounded border's stroke, or the screen edge with the border off.
- Its outer corners are square (`tabCorners: square`) or flared (`flared`: a concave fillet out into that edge; the setting links to the bar's Widget gap, `x-link` `BarEditor:widgetGap`, since the gap limits the fillet). Its inner corners take the widget radius, at most half the thickness (`BarTabs.tab`).
- **Every flared tab on a bar takes one fillet radius** (`barConfig.tabFillet`, `BarTabs.tabFillet`, worked out in `BarsConfig.enrichBarConfig`), on both sides and at a run's ends alike, so all its tabs look the same: the inner corners' radius, but no more than half the configured gap between widgets (`groupSpacing`: neighbours' fillets meet in it, tangent at a gap of twice the radius, never crossing; none at a gap of 0, which draws as square) nor the room at the bar's ends (`BarEnds.tabEndRoom`: a pill's gap, a solid bar's margin, a transparent bar's gaps past the border's corner). From config, never the gaps as drawn: a spacer widening a gap changes nothing, and the layout never makes room for a fillet.
- **A corner's curve** (`BarEnds.tabBounds`, `BarTabs.tabLimits`): a tab's end nearer an island's (or, on a transparent bar, the rounded border's) corner than its radius takes that corner's curve on its outer corner instead of a fillet.
- An outline's stroke is left open along the outer edge (`BarOutlines.path`'s `open`), as are the hover outline's and the editor highlight's.
- Merged runs are one tab, with fillets at the run's ends only. Tabs never chain as a powerline (`BarLook.resolve` draws a saved powerline as separate; the option is hidden).
- The host's hit area reaches out with the tab, and its content is centred in the tab (`BarWidgetHost.tabReach`, moved across by `BarTabs.tabShift`: half the reach, toward the outer edge, in whole pixels). Separator marks between tabs move with it, so they stay level with the tabs' content.
- **Split on a tab:** the icon part reaches the edge too (it's drawn by the same tab path, its end the divider: `BarTabs.sides` draws a side that isn't a tab's as `BarShapes.capPoints` has it, the right way up on either side). A badge has no box, so a separate badge isn't offered the tab shape (`x-enumShowIf`), and one saved with it draws rounded (`BarLook.resolve`'s `shape`, and `BarLook.context`).

### Outline strokes
- An outlined widget's stroke (`outlineStroke`, shown for outline) is solid, dashed, dotted, double or ends only. Solid is the Rectangle's border or the path's stroke, as ever; any other is a `bar/look/OutlineStroke` over the box (a Rectangle can't dash), so rounded and capsule draw as a path then too. Workspace cells take the same stroke (`BarCells.cellBox`), a double one in half-width lines (at least 1 px) so the inner line keeps clear of the label.
  - **Dashed / dotted:** the outline (half a line in) with a dash pattern in line widths: dashes three long two apart, dots square, one and a half apart (the curve renderer draws no zero-length dash, so dots can't be round caps). The pattern runs along `BarOutlines.dashPath`: two halves mirroring each other, each from the middle of the long sides out round its own end (at an open end, its two sides out from the middle), every part starting half a dash in (`dashOffset`), so a dash sits centred where the halves meet and both ends dash alike, wherever a single path would have started its phase.
  - **Double:** two lines of `outlineWidth`, `outlineWidth` apart (`BarOutlines.offsetPath`): each moved in square to every edge, so a slant's or arrow's sides stay parallel to the shape's and a round corner keeps its centre (its radius less the inset); a capsule's or a powerline's half circle shrinks (or, bowed in, grows) about its own. At a powerline seam the outer line lies on the seam, as a solid outline does, and the inner one two widths in from it. A line with no room left (a thin bar, a wide outline) isn't drawn.
  - **Ends only** (`BarOutlines.marks`): the outline at its ends alone, open paths in the shape, each a bracket: the end's line with arms a quarter of the thickness along the bar from its two corners, rounded (or square) `[ ]`, slanted or an arrow's point or notch alike, so they read as brackets rather than slash separators; a capsule's half circle `( )` (and a powerline's half circles) has none. A merged run has a mark at its two ends only (its widgets have no stroke of their own); a powerline one per seam, the earlier segment's end cap (a segment's start at a seam, `seamStart`, draws none).
  - **On a tab** every stroke is open along the edge it hangs from: dashed and dotted run from the middle of the inner side out round each inner corner to that edge, or on a flared tab to its fillets, which are drawn solid (`BarOutlines.fillets`: a dash pattern can't fall the same way on both), double's two lines both run out to that edge (`offsetPath` with `tab`: the inner corners and fillets keep their centres), and ends only marks the tab's two sides, each from the edge in, round its inner corner and an arm a quarter of the thickness along the inner side (`BarOutlines._tabMarks`).

### Runs: merged and powerline
- Neighbouring widgets with backgrounds form runs (`BarLayout.runs`/`runPlaces`).
- **Merged** draws one background per run in `groupColor` (`BarsConfig.groupColors`; an outline run, whose background is its line, in `groupStrokeColor`), or with a bar gradient one strip of it from the run's start to its end ([Widget style › Bar gradient](widget-style.md#bar-gradient)). Its widgets' colors move to their icons (`BarWidgetStyle`'s `group`), but for split's icon parts (see Split), a tab run (one tab, see Tabs) and a widget filled on hover (its own part). A merged outline's Ends only marks are at the run's two ends.
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
  - **The run carries on** where both widgets facing it have backgrounds (`chainStart`/`chainEnd`): `BarLayout.runPlaces` counts one more member past that end, so the widget takes a middle place. A merged background has no cap there and runs on over the gap (`joinEndReach`, `BarContainer.sectionReaches`, from the groups as drawn), its outline open at that end and at the next section's run's start (`WidgetBackground.openStart`/`openEnd`, set by the run delegate from its first and last places: `BarOutlines.path`/`offsetPath`/`marks` leave out the line, mark or tab side across an open end and keep no inset there), so the two sections' runs read as one, with no divider at the join in any stroke; a powerline segment ends in its join cap and the next section's first segment reaches back under it. Sections stack left over center over right (`Section`'s `z`) so the earlier segment draws on top.
  - A widget with no background facing it keeps `widgetGap` from it in a powerline, as inside a section.
- **Powerline** chains the widgets with no gap (`groupSpacing` 0).
  - Each segment's end cap runs into the next segment, which reaches back under it (`back`).
  - With a see-through fill (tinted, outline, or split but for a label on a color of its own), the next segment fits against the cap instead.
  - An outline's two strokes lie on the shared seam (`seamStart`/`seamEnd`).
  - A segment's content is centred on the part of it that shows: from half a join before its box to half a join before its end. Its `trail` takes the difference.
- **What breaks a chain:**
  - A widget shown without a background (the Separator) splits a chain. It keeps `widgetGap` to the widgets beside it in its section.
    - At the section's end there is no spacing; the gap to the next section stands in, as on any bar.
  - A widget showing nothing (hidden) is passed over: `runs` flags it null.

### Parts as segments
- A widget can lay its own parts out as segments of the bar's run (`BarWidget.segmented`): Workspaces with its Background off, whose cells are the segments. It still counts as a run member (`hasBackground`), so its neighbours chain to it, merge with it and give it a place, but:
  - its `WidgetBackground` is `bare` (no box of its own; the press, hover outline and editor highlight still draw);
  - its host keeps no cap room for it (`leadInset`/`trailInset` 0): each part keeps its own;
  - `WidgetGroup` hands its host `runPlace`: `sized` and `drawn` (its place in the run from what's shown, as for the insets, and as laid out, as for the shapes) and `tabLimits` (from where it's laid out; an end no nearer its bound than the bound's curve has none). It passes through a string key, as do the run flags the places are built from (`_insetKey`, `_drawnKey`: `BarRuns.flagsKey`), so a neighbour's new size, which re-reads them all, rebuilds nothing unless a place really changes. `BarWidgetHost` adds how far its parts reach past the module across, `reachStart`/`reachEnd` (a tab's out to its edge, after the content's `tabShift`), and gives it to the module as `BarWidget.runPlace`.
- The module chains its parts as one run of `cells` (Workspaces: its workspaces, then its strip's windows) inside its place, through `BarCells`:
  - **`cellSegment`** (`cellShape` from the look and `runPlace.drawn`, `cellRoom` from `runPlace.sized`): separate, each cell alone in the shape's ends; powerline, the cells continue the bar's chain (index `place.index + cell` of `place.count + cells - 1`), so the first takes the cap the segment before expects and the last ends as the widget would. The module draws over the bar's backgrounds, so its first cell always fits against the cap before it (never starts square beneath it); a later one starts square beneath the cell before where the cells' boxes are opaque (`BarLook`'s `cellOpaque` trait: filled, split, solid boxes), the cells drawn earlier over later (`z: -index`, the row over the strip). Merged, the run's background lies under the cells: a cell keeps the room of the run's end where it has one, and one drawing a box of its own there (`BarLook`'s `boxedInRun` trait: solid boxes, split's fill) takes the caps it has alone, and their room, as a merged widget's level does.
  - **`cellGap`**: no gap between cells in a powerline, else their own spacing.
  - **`cellTab`**: a tab cell takes the bar's `tabFillet` at the widget's two ends, which the widget's `tabLimits` bound, and between cells no more than half the gap between them, so neighbours' fillets never cross.
  - A cell's length is what it shows plus its room (`WorkspaceCells.roomed`), its content centred clear of its caps.
- Each part is drawn in the shared `bar/look/LookBox` (the `WidgetBackground`'s own box, a `ShapedBox`: every cap, tab, open end and outline stroke, a gradient slice), reaching back under the cell before (`back`), a flared tab's fillets out past its sides, and out to a tab's edge. `cellShape` says how far it draws past its own bounds: `drawStart`/`drawEnd` along the bar (back plus a fillet, a fillet), `reachStart`/`reachEnd` across. Only `reusable/MarginClip`s clip it, each grown by that: the module's own clips round a row of cells by its first cell's start and its last's end (`cellMargins`), the host's while it resizes by the widget's as one cell (`runDraws`). The sliding active box keeps inside the row's own length while it wraps past an end, so it never passes over the cap or fillet before the widget.

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
- A widget's parts laid out as segments (Workspaces' cells, its strip's windows) are hit in their boxes as drawn too: each has a `Workspaces/CellHitArea`, a MouseArea grown by what its box draws past it (`cellMargins`) and masked by `BarCells.cellContains` (its box from where it shows, `cellSegment`'s `shownStart`, to its end cap, out to a tab's edge). So a powerline's corners beside a cell's end cap answer for the next cell, whose box shows there, the first cell's reach back under the widget before is its own, and a tab cell is clicked out to the screen's edge. The cells ask the widget's hit area `hovers(area)` of these areas; the one box holding a strip's windows gives each icon its share of it.

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
