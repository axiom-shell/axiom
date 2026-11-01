# Popouts on floating, pill and transparent bars

> **Files:** `components/bar/BarContainer.qml`, `components/methods/BarLayout.qml`, `components/methods/EdgeAttach.qml`, `components/hosts/popout/PillBarJoin.qml`, `components/hosts/popout/AttachedSurface.qml`, `components/hosts/popout/BarPopouts.qml`, `components/hosts/popout/EdgePopout.qml`, `components/hosts/popout/EdgePlacement.qml`, `components/hosts/popout/ClosedLatch.qml`
> **Config:** `Bar.background` (`floating`, `floatingPills`, `pills`, transparent), `Bar.floatGap`, `Bar.pillMerge` (per bar in `Bars`; `island`/`islandPills` are derived on `barConfig`)
> **Related:** [Edge attach](edge-attach.md), [Surface context](surface-context.md), [Held off an edge](held-off-edge.md), [Bar layering and corners](../bar/layering-and-corners.md), [Shadows](shadows.md)

How surfaces meet the three non-solid bar backgrounds. Solid bars, the border, corner sharing and plain pills are in [Bar layering and corners](../bar/layering-and-corners.md).

### Floating bars (islands)
- **Settings:** `background: "floating" | "floatingPills"`, with `barConfig.island`/`islandPills`.
- **Laid out like tiled windows:** the islands are held their float gap in from the border's stroke (or from the bare screen edge). The gap applies across the bar and from both ends (`islandStart`).
  - **`floatGap` Automatic (-1):** this is the compositor's gaps_out on the bar's edge, the same gap windows keep. So the islands' ends line up with the windows'. With no compositor backend (gaps unknown, `gapsOut` 0) it's `Appearance.screenMargin` (`ScreenEdgeManager.floatGaps`), so the bar isn't flush on the border.
  - **Each island** is a rounded box with a stroke all round, holding the widgets and their `padding`.
- **Read as pills:** `BarContainer.pillRects` holds the islands shaped like pills (`BarLayout.islandRects`), so the popout code reads them as pills.
  - The shape is either one island from limit to limit, or one per group, merged within `pillMerge`.
  - They are drawn from `pillShapes` (`BarLayout.stretchIslands`).
- **Nothing joins a floating bar.** `joinable` is true only for a solid bar.
- **Surfaces on an island:**
  - **Which island:** a popout, edge popout or dock uses the island under its centre, otherwise the nearest.
  - **Where it grows from:** out of the island's inner stroke (`attachAt`). It never merges (`EdgeAttach.place`, island mode).
  - **Sides that keep their fillet:** a side whose fillet lands on the island keeps it. The same holds when it lands on a neighbour the island stretches to within `pillMerge` of; the two then draw as one while the surface is open.
  - **Other sides:** any other side reaches to the island's end and runs flush into it. Where the box goes past the island, the island is stretched to the box.
- **Repaint after a stretch:** a stretch changing while a surface is open is drawn by the bar, but wasn't shown until the bar committed again. So `BarContainer` paints a few frames of its own after one changes (its `FrameNudge`, `repaint`).
- **Flush sides:** a flush side runs into the island in one straight line (`AttachedSurface.flushStart`/`flushEnd`).
  - It is a wall continuing the island's end, with its backfill kept off that stroke.
  - The island squares that inner corner (`squareStart`/`squareEnd`, animated).
- **Reservation:** floating bars reserve space up to their islands, so windows keep gaps_out from them as from a screen edge.
  - gaps_in applies only between windows.
  - `BarsConfig.reserveTrim` is 0 for floating bars, whatever their float gap.

### Bar popouts and pill bars
- **Joining ends:** bar popouts join an end the same way edge popouts do (`EdgeAttach.joins`).
- **Pill bar on a perpendicular edge:** bar popouts, edge popouts and docks all also join a pill bar (`background: "pills"`) there.
  - **The joining piece:** `hosts/popout/PillBarJoin`, a `PillStretch` on that bar's container. Its `available` is what makes the end joinable.
  - **Where the end sits:** on that bar's far stroke. Its window reaches a stroke's width onto it, as it does onto the border's or a solid bar's stroke.
    - Every end does this except a bare screen edge's (`EdgePopout.startStrokeInset`/`endStrokeInset`; the dock's likewise).
  - **The bar's end pill runs out along the box** (the `endReach` of its `BarContainer.setRequest`).
    - The reach comes from `joinReach`, the far wall's reach (`AttachedSurface.joinWall`).
    - It follows the box's far wall as it slides (`hidden`), and its far stroke opens only as far as the box has come ([Choreography](edge-attach.md#choreography)).
    - Either the end pill is stretched, or a stub is grown where the bar has no pill near its end (`BarLayout.endReaches`).
- **Filleted join:** this applies where one of the bar's own pills (`sectionPills`, before any stretch) shows past the wall's outer edge at all (half a stroke out from where it rests, where a straight join would square it) and reaches within a fillet, a corner and `pillMerge` of it (`EdgeAttach.pillJoinFilleted`, read as `PillBarJoin.filleted`).
  - A pill showing past the wall by less than a fillet and a corner is stretched to carry them: a stretch only grows, so it couldn't square at the wall, and a straight join met its side in a bare T.
  - The wall is where the surface's far wall rests (`EdgePlacement.joinReach`, from the layout's `attachAt`), never where it's drawn: the decision resizes the surface and its window a frame apart, and it slides in, so a measured wall moved and flipped the decision back.
  - The end curves into its far stroke with a fillet, as it would into a solid bar's.
  - The pill carries on past the fillet by its own corner's radius.
  - Its far stroke is left open under the box and fillet. This is an opening with a fillet at that end (`startFillet`/`endFillet`), which the bar's shadow follows round.
- **Straight join:** otherwise the end runs straight (`straightJoinStart`/`End`).
  - It runs into a pill or stub that goes only as far as the far wall and squares there (`square`).
  - The wall runs on into its end.
  - Its far stroke is left open inside the wall under a translucent box.
- **The pill still curves out** to the border as ever, following the surface along its slide ([Choreography](edge-attach.md#choreography)).
- **A bar popout joining one** stretches its own pill to its bar's end (`pillJoins`).
  - On a pill, the box joins an end that `joins` asks for wherever its pill can reach that edge, or where its fillet would pass the stroke there.
  - The pill of a bar that owns the corner runs on past it, under the other bar's end.
  - **A side running flush to such a pill joins the edge** wherever that pill runs past where an unjoined box may reach (`lo`/`hi`) and the edge can be joined (`joinableStart`/`joinableEnd`). It never runs on behind the other bar's pills.
- **Floating or transparent bar on a perpendicular edge:** past one, an attached edge popout's or dock's free end is a wall, as a bar popout's is.
  - Its box stops where windows start there, lining up with a detached box.
  - Its fillet is inside the wall too, keeping the windows' gap from the bar.
- **Every surface on a pill bar** (edge popouts and docks alike) grows out of a pill's far stroke exactly as it would out of an island:
  - **Stretching:** the pill under it (otherwise the nearest) stretches, animated, to carry it, joining neighbours within `pillMerge`.
  - **Flush ends:** the pill squares its far corner where the box runs flush into its end (`AttachedSurface.startCornerRadius`/`endCornerRadius`, animated).
  - **Perpendicular joins:** at a pill that joins the perpendicular edge, the box joins that edge too.
- **Between pills:** a surface centred between pills or islands (`EdgeAttach.place`'s `between` mode) that keeps more than `pillMerge` and two fillets' room from each grows from the bar's outer edge instead, over the bar's reserved area, as on a bare stretch of a solid edge.
  - It grows out of the border's stroke (opened under it), or straight off a bare screen edge.
  - Its content starts at that edge (`attachClearance` 0, unlike `merged`), so a dock there sits in the bar's empty room. An edge popout there takes the bar's empty depth off its padding on that side (`SurfaceContext.layout`'s `attachFill`), as it does the border's margin.
  - It stretches no pill. Too close to a pill, it grows out of the nearest one as above.
- **`BarContainer.pillShapes`** is the pills (or islands) as drawn: stretched and merged.
- **Merged boxes:** only a pill bar showing no pills leaves a box to grow from its outer edge (`EdgePlacement.merged`). That box is as deep as the pills would be.
- **Flush wall through the backfill:** a flush wall runs on through the surface's backfill, covering the end of the stroke it continues. The backfill leaves that spot open, and the glow used to show through it as a seam.

### Transparent bars (detached popouts)
- **On a transparent bar, popouts are `detached`:** plain rounded boxes on the bar's own edge.
  - They never join an end; they're clamped clear of it.
- **Their window:**
  - Whether it slides under is `EdgePlacement.slidesUnder` (`SurfaceContext.layout`), for bar and edge popouts alike.
  - It is on the bar's layer: the bar popout's window, `BarPopouts.underBar`.
  - Its namespace is `axiom-popout-under`, whose layer rule ([layer stacking](../generated/layers.md)) stacks it under the bars and border.
  - It starts at the bar's outer edge, and the box (`AttachedSurface.detachedOffset`) slides out from beneath the bar.
- **Over the overlay:** that same rule also stacks the window under the overlay.
  - So while the overlay is open on its screen (`SurfaceManager.surfaceOpenOn("overlay", screen)`), the window opens on the Overlay layer instead (`axiom-popout`), over the overlay, without the slide.
  - That's latched while the popout is open, so the overlay opening closes the bar popouts and floating edge menus on its screen (`PopoutManager.closeOn`, from `OverlayPanel`); opened again, they open over it. Integrated menus, docks, OSDs and the launcher stay.
- **Without layer rules** (no `CompositorManager.supports.layerOrder`: sway, niri), a window mapped as it opens lands over the bar whatever its namespace, so it never slides under: it opens over the bar as it does over the overlay ([layer arrangement](../compositor/layer-arrangement.md)).
- **Detached edge popouts do the same as bar popouts:**
  - They slide out from under a transparent bar only (`EdgePopout.slideDistance`).
  - While the overlay is open they open over it (`_overOverlay`). This is a `ClosedLatch`, since it changes the window's namespace.
  - Over anything else they open on top, sliding out within their own window.
