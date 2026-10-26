# Bar ends and pills

> **Files:** `components/methods/BarEnds.qml`, `tests/tst_BarEnds.qml`, `components/bar/BarContainer.qml`, `components/bar/CornerMerge.qml`, `components/methods/BarLayout.qml`, `components/hosts/popout/AttachedSurface.qml`, `components/hosts/popout/PillBarJoin.qml`, `components/hosts/popout/EdgePlacement.qml`, `services/ui/BarManager.qml`
> **Config:** `Bars[].background`, `pillMerge` (others such as `overlap`, `pillPad`, `pillConnector` are derived `barConfig` values)
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
    - `gap` is a floating bar's own float gap, else how far windows start past it.
  - **`pillBar`:** see Pill bars meeting at a corner below.
- `reach` is how far the window reaches onto the stroke at that end (`BarPanel`'s margins).
- **How `BarContainer` uses the ends:**
  - It takes per-end `endMargins`; `BarLayout.layoutSections`/`overflowHidden` take `[start, end]`.
  - It takes `islandFrom`/`islandEnd`.
  - It joins an end pill only where that end is `joinable`.
  - A transparent bar's widgets keep the same gap from each end as across the bar.
- **Placing things along the bar:**
  - `ScreenEdgeManager.barStartOn` says where a bar's window starts at each end. `EdgePlacement` places things along the bar from it (`barStart`).
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
- There is one pill per section. Pills are merged when they're at most `pillMerge` apart.
- Each pill is an `AttachedSurface` growing out of the bar's outer edge, covering the border stroke (`barConfig.overlap`).
- Widgets sit `overlap + pillPad` in from that edge.
- A pill at an end of the bar joins the perpendicular edge (`joinStart`/`joinEnd`): it sits flush on that edge's stroke, whose far corner meets it with a fillet.
- **End reach requests.** Surfaces joining the bar from the perpendicular edge ask for a pill at an end with an `endReach` (`{ atStart, to, straight }`) in `setRequest(owner, …)`, keyed by owner.
  - `BarLayout.endReaches` stretches the end pill there.
  - Or it adds a stub joined at that end, up to `pillConnector` long but never past the reach asked (so it grows from the corner with a request following a sliding surface), and stretches that. `pillRects` holds the stub as a pill like any other.
  - A request reaching nowhere past the end asks nothing.
- In pill mode the bar window is `borderRadius` thicker than `extent`, for that fillet, and masked to the bar itself.
- Floating bars take `-borderWidth` margins on both ends too, so bar-window 0 along the bar is the perpendicular stroke's outer edge.
- Floating bars and bar popouts on pill bars: see [Pill and floating bars](../popouts/pill-and-floating-bars.md). Surfaces held off an edge: see [Held off an edge](../popouts/held-off-edge.md).
