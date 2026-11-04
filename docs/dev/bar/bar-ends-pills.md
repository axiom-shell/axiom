# Bar ends and pills

> **Files:** `qml/components/methods/BarEnds.qml`, `tests/tst_BarEnds.qml`, `qml/components/bar/BarContainer.qml`, `qml/components/bar/CornerMerge.qml`, `qml/components/methods/BarLayout.qml`, `qml/components/hosts/popout/AttachedSurface.qml`, `qml/components/hosts/popout/PillBarJoin.qml`, `qml/components/hosts/popout/EdgePlacement.qml`, `qml/services/ui/ScreenEdgeManager.qml`
> **Config:** `Bars.items[].surface` (`joinGap`, `overlap`, `pillPad`, `pillConnector` and others are derived `barConfig` values)
> **Related:** [Layering and corners](layering-and-corners.md), [Pill and floating bars](../popouts/pill-and-floating-bars.md), [Edge attach](../popouts/edge-attach.md), [Held off an edge](../popouts/held-off-edge.md)

What each end of a bar meets and whether surfaces may join it there, how two pill bars merge at a corner, and how pills are built and stretched by surfaces joining from the perpendicular edge. Which bar owns a corner is in [Layering and corners](layering-and-corners.md) (Bars sharing a corner).

### Ends (`BarEnds.withEnds`)
- `ScreenEdgeManager.bars` gives each bar its `ends`, worked out among the bars on its screen. Each end says what it meets, as a `kind`:
  - **`border`.**
  - **`bare`:** a bare screen edge.
  - **`solidBar`:** with the border off, a solid bar's inner stroke.
    - A pill joins it with a fillet, as it would the border (`AttachedSurface.straightJoinStart`/`straightJoinEnd`, per end).
    - The solid bar draws that stroke in pieces around its `openings`. The stroke is left open under the joined end, and under a popout standing on it or joined to it at an end, opaque or not (`BarContainer.barAt`, `solidStart`/`solidEnd`).
  - **`bar`:** a bar it makes way for, with no stroke. This is a **held** end:
    - It is kept clear of that bar's inner edge, `over` into the window, by `gap`.
    - `gap` is a floating bar's own float gap (Automatic: `floatGaps`, the screen margin with no backend), else how far windows start past it.
  - **`pillBar`:** see Pill bars meeting at a corner below.
- `reach` is how far the window reaches onto the stroke at that end (`BarPanel`'s margins).
- `barId` is the bar it meets on the perpendicular edge ("" for the frame), and `from` how far from that edge its window starts, before `reach`: past every bar there it makes way for (bars stacked on one edge: [Layering and corners](layering-and-corners.md#bars-stacked-on-one-edge-barendsstackson-placestack-edgeof)). `BarContainer.barAt` finds the bar it joins by `barId`.
- **How `BarContainer` uses the ends:**
  - It takes per-end `endMargins`; `BarLayout.layoutSections`/`overflowHidden` take `[start, end]`.
  - **Solid and pill bars' end widgets sit at the screen margin** (`BarEnds.endInset`, `tst_BarEnds`' `test_end_widgets_line_up_with_windows`): at an end that isn't held, a solid or pill bar's (part of the frame) first and last widgets sit the screen margin from the side edge (with the border off, the larger of the margin and the padding), or that far past the bars there it makes way for. Solid and pills place them alike (defaults: 8 px from the screen edge, border on or off). An end pill fills the corner and joins the frame squarely, as a solid bar does, so no fillet room is kept and the radius never counts.
  - **What isn't part of the frame lines up with the windows** (`BarEnds.windowInset`, `test_unframed_bars_line_up_with_windows`): at an end that isn't held, a floating bar's islands (and floating pills) end, and a transparent bar's first and last widgets sit, where windows start: the frame, or the bars there it makes way for, plus the compositor's gaps_out on that side (with no backend, the screen margin, as an Automatic float gap). A floating bar's own float gap only counts across it; its widgets sit inside its islands.
  - It takes `islandFrom`/`islandEnd`.
  - It joins an end pill only where that end is `joinable`.
- **Placing things along the bar:**
  - `ScreenEdgeManager.barStartOn` says where a bar's window starts at each end (its end's `from` less `reach`, integrated menus added). `EdgePlacement` places things along the bar from it (`barStart`).
  - Where an end can't be joined, a bar popout's walls stop where windows start instead. See [Edge attach](../popouts/edge-attach.md) (Walls).
- **Joining a bar end.** A bar popout joins an end only where `ScreenEdgeManager.surfaceEnd` says it may:
  - at the border, a solid bar or a bare edge, with no integrated menu; or
  - at a pill bar (`PillBarJoin`).
  - See [Pill and floating bars](../popouts/pill-and-floating-bars.md).

### Pill bars meeting at a corner
- Two pill bars merge at their corner.
- The end of the bar that makes way (the one on the screen's longer edge) is `pillBar`: joinable and not held. Its window reaches `borderWidth` back onto the other bar's far stroke.
  - Its end pill joins there with a fillet, as into a solid bar's stroke.
- It pushes the other bar a request (`bar/CornerMerge`, an `endReach` through `BarContainer.setRequest`) to run its end pill (or a stub) straight off its end, past that fillet.
  - That end is `straight`: no fillet into the border.
  - Its far stroke is opened from where the fillet meets it, and its shadow follows round the fillet. That is where the fillet's stroke ends (`CornerMerge._filletTip`): its centre line, half a stroke in from the pill's far edge, on whole pixels (`SurfaceContext.opening`). Open any further and a row of the corner shows through.
- The result is one stroke and one concave corner, as solid bars make.
- Surfaces inside the reserved space (edge popouts, docks) are arranged after every bar. They therefore meet whatever bar is on the perpendicular edge, whichever bar owns the corner.

### Pills (`BarContainer.pillRects`)
- **Groups:** a group is a run of widgets between a section's ends and its spacers (a spacer given room splits one; `WidgetGroup.drawnGroups`, `BarContainer.groupSpans`).
- **Joining:** neighbouring groups at most `joinGap` (the widget gap, or the room a divider mark takes) apart join (`BarLayout.joinGroups`, `BarContainer.joinedGroups`). It's the one rule for pills, a floating bar's islands and the `merged` grouping's backgrounds, which run on across a section's end where its groups join (`WidgetGroup.joinStart`/`joinEndReach`).
- There is one pill per joined group (`BarLayout.pillRects`, `BarContainer.groupPills`), grown by `pillGap`; pills then too close for the fillets between them (two `pillConnector`s) draw as one.
- **Pills lie as solid bars do** (`BarEnds.crossGeometry`): switching a bar between solid and pills, with no other option changed, moves neither the windows nor the widgets, border on or off (`tst_BarEnds`' `test_pills_lie_as_solid`). With the defaults (border 1 px, margin 8, padding 4, thickness 26) windows start 35 px in and the widgets span 4..30 px in both.
  - The body is the widgets with their padding either side (at least the border strip's depth, `margin − borderWidth`). A solid bar is the body (and its own stroke with the border off); a pill is the body and its far stroke.
  - A pill bar lying on the border itself (nothing reserving outside it) reaches back over the whole frame to the screen edge: its window's outer margin is the screen margin (`BarEnds.placeStack`'s `outerReach`, `BarPanel`), so it reserves the frame's room back, and its widgets sit across from the screen edge as a solid bar's do, over the frame's fill.
  - Its pills hang off the border's stroke, `stripCover` (`margin − borderWidth`) in from the window's outer edge; between them the frame shows as ever. The bar's shadow is kept off the frame (`BarContainer._stripHole`).
  - A pill bar stacked inside another bar keeps its `-borderWidth` reach onto the stroke there (`stripCover` 0).
  - Along the bar, a joined end pill's widgets sit where a solid bar's do (`BarEnds.endInset`; inside the border, just past the side stroke the pill covers), and a free end sits `pillGap` (the padding and its stroke) past its widgets.
- Each pill is an `AttachedSurface` growing out of the border's stroke, covering it (`barConfig.overlap`).
  - Its box starts half a connector gap out (`boxStart`), but never past the pill's own depth (`pillDepth − stripCover`): at a high radius the half gap is deeper than the pill, and a box starting there drew the far stroke past `pillDepth`, where a dock standing on it and the far stroke's openings (`_farHole`, taken from the pill's `farV`) don't reach.
  - Its copies (the blur window's fill, the bar's shadow: `AttachedSurfaceCopy`) take its `attachFilletRadius` with the rest of its shape.
  - **Its fillets and far corners meet in one curve.** At a high radius, a full fillet (curving down off the stroke) and a full far corner (curving back) are deeper together than the pill. Cutting the corner down to what the fillet left made the pill's end nearly square around a capsule widget. So both scale down by the same ratio until they meet (`SurfaceOutline.fitRadii`, `BarContainer.pillRadii`, read as `attachFilletRadius` and the corner radii). A joined end's fillet keeps the full radius. Where things are spaced for a pill's fillet (a held end, `_endMargin`) and the inner accent line clears its corners, they read the fitted radii. `EdgeAttach` and `SurfaceContext` still keep room for a full fillet and corner round a pill, which is only more room than needed.
- A pill at an end of the bar joins the perpendicular edge (`joinStart`/`joinEnd`): it sits flush on that edge's stroke, whose far corner meets it with a fillet.
- **End reach requests.** Surfaces joining the bar from the perpendicular edge ask for a pill at an end with an `endReach` (`{ atStart, to, straight }`) in `setRequest(owner, …)`, keyed by owner.
  - `BarLayout.endReaches` stretches the end pill there.
  - Or it adds a stub joined at that end, up to `pillConnector` long but never past the reach asked (so it grows from the corner with a request following a sliding surface), and stretches that. `pillRects` holds the stub as a pill like any other.
  - A request reaching nowhere past the end asks nothing.
- In pill mode the bar window is `borderRadius` thicker than `extent`, for that fillet, and masked to the bar itself.
- Floating bars take `-borderWidth` margins on both ends too, so bar-window 0 along the bar is the perpendicular stroke's outer edge.
- Floating bars and bar popouts on pill bars: see [Pill and floating bars](../popouts/pill-and-floating-bars.md). Surfaces held off an edge: see [Held off an edge](../popouts/held-off-edge.md).
