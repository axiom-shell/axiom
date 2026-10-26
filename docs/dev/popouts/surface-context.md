# Surface context: what a surface meets at its ends

> **Files:** `components/methods/SurfaceContext.qml`, `tests/tst_SurfaceContext.qml`, `components/hosts/popout/EdgePlacement.qml`, `components/hosts/popout/EdgeSurface.qml`, `components/hosts/popout/StrokeOpening.qml`, `components/hosts/popout/SubmenuHost.qml`, `components/hosts/popout/SubmenuSide.qml`, `components/hosts/popout/PopoutAnchor.qml`, `scripts/dev/popout_matrix.py`
> **Config:** none directly (reads bars, border and integrated menus through `ScreenEdgeManager`)
> **Related:** [Edge attach](edge-attach.md), [Registry](registry.md), [Hosts and switching](hosts-and-switching.md), [Submenus](submenus.md), [Shadows](shadows.md), [Bar layering and corners](../bar/layering-and-corners.md)

Every surface that grows out of a screen edge asks one pure helper what each of its ends meets. Read this before changing how any popout, dock or submenu joins, walls off or fillets at an intersection. (Rule: AGENTS.md › UI conventions, "Popout geometry".)

### One rule set for what a surface meets
- Surfaces covered:
  - bar popouts
  - edge popouts: OSDs, floating edge menus, the attached launcher
  - docks
  - submenus
- They all ask `methods/SurfaceContext` (tested by `tests/tst_SurfaceContext.qml`) and never decide for themselves. An intersection that fillets (or doesn't) for one therefore does for all.
- **`endKind`** classifies what an end meets on the perpendicular edge. The input is `ScreenEdgeManager.surfaceEnd`, the one place the bars, the border and integrated menus' zones are read for this. The kinds:
  - `border`: a solid bar under the border counts as this too.
  - `bare`
  - `solidStroke`: a solid bar's own stroke, with the border off.
  - `pillBar`: see `PillBarJoin` in [pill and floating bars](pill-and-floating-bars.md).
  - `wall`: a transparent or floating bar, a hidden pill bar, or an integrated menu's strip.
- **`end`** combines that kind with the surface's state: held, detached, on an island, or its bar's end held clear. It produces:
  - `joins`: `EdgeAttach.joins`' `startOk`/`endOk`. When the surface is held, detached or on an island, nothing joins.
  - `strokeInset`: its window reaching onto the stroke.
  - `straight`: a bare edge's joined end.
  - `wall`: its walls stop where windows start there (`wallLine`), with its fillet inside the wall too. This applies to bar popouts, edge popouts and docks alike. It does not apply when held, since a held surface keeps its gaps. See [Edge attach › Walls](edge-attach.md#walls).
  - `sink`: who draws the stroke that a joined end covers.
- Other outputs:
  - `filletMargin` / `endRoom`: the room an unjoined end keeps, for its fillet and, while the border is on, past the frame's rounded inner corner.
  - `detached`: the one rule for a box of its own. It is detached when held, past a transparent bar, or on a floating bar showing no islands.
  - `shadow`: how it casts its shadow, taken from what it grows out of. See [Shadows](shadows.md).
  - `opening`: a stroke opening on whole pixels.
  - `submenuJoin`: how a submenu joined at its parent's bar side meets the stroke there, fillet or straight, and the parent's pill stretched for it. See [Submenus](submenus.md#what-the-submenu-hands-back).
  - `submenuPlace`: where a submenu goes along its parent's side. See [Submenus](submenus.md#placement-along-the-parents-side).

### One placement for every host
- `SurfaceContext.frame(p)` gives a surface's ends and the room it has along its edge before its box is known:
  - `lo`/`hi`, `joinFrom`/`joinTo`
  - walls and the strokes' reach
  - `joinsOf`: its joins from where it would rest
- `layout(f, p)` gives its box (via `EdgeAttach.place`) and everything that follows from it:
  - `detached`, `straight`, backfill (`merged` and `between` boxes grow from the followed bar's outer edge: attached there, with the border as their sink)
  - `attachAt` across
  - `ownSink`, shadow
- Both work in screen px along the edge. A bar popout, an edge popout and a dock at the same intersection therefore get one answer.

### EdgePlacement: the only input gatherer
`hosts/popout/EdgePlacement` is the only thing that gathers SurfaceContext's inputs.
- **What it gathers:**
  - The bar it follows: a bar popout's own bar, solid ones included (`followPanel`); otherwise the non-solid bar on its edge.
  - The perpendicular sides' end kinds, frame lines and reservations.
  - Held gaps.
- **Coordinates:** it converts to its host's coordinates. `alongStart` is where the host's along-axis 0 sits on screen.
- **Side effects it owns:**
  - its `PillStretch`es, `PillBarJoin`s and `StrokeOpening`s
  - `joinReach`, taken from its surface and window origin, and `_surfaceHidden`, what a pill bar joined at an end follows the surface along its slide by
  - for a joined submenu, how it meets the stroke (`submenuJoin`, from `SurfaceContext.submenuJoin`) and its pill reach (`_submenuReach`)
  - for a joined submenu, its reach and covered stroke, taken from the host's `SubmenuHost` (`submenu`)
- **What hosts give it:**
  - the box: `centre`, `aligned`, `contentLength`
  - where the box would rest: `probeStart`/`probeLength`, which decide its joins
- **Drawing:** hosts draw an `hosts/popout/EdgeSurface` from it.
- The full list of EdgePlacement outputs is in [Edge attach › EdgePlacement](edge-attach.md#edgeplacement).

### What stays a host's own
- **Bar popout:** one window per bar spanning its edge, the anchor, and switching in place ([Hosts and switching](hosts-and-switching.md)).
- **Edge popout:** its position, held gap and fullscreen hold ([Held off an edge](held-off-edge.md)).
- **Dock:** its magnification and hide slide.
- **Openings:** they go out through `hosts/popout/StrokeOpening`. While translucent they go to the border; otherwise they go to a solid bar's own stroke, opaque or not.
- **Submenus:** what a submenu meets on its parent's side is `hosts/popout/SubmenuSide`, inside the parent's `hosts/popout/SubmenuHost`. That host is the same for both parent kinds and is the submenu's `slot` ([Submenus](submenus.md)).

### One window model
- Every popout is a layer `PanelWindow`.
- **Bar popout window:**
  - **Exclusion:** it ignores what others reserve (`ExclusionMode.Ignore`).
  - **Span:** it spans the screen along its bar's edge, starting from the screen's edge. Where its box goes therefore follows from where the bar is alone (`mainPopup.windowOrigin`, `alongShift`).
  - **Layer:** normally the Overlay layer (`axiom-popout`, over the bar). On a transparent bar it sits under the bar (`axiom-popout-under`, followed only while closed; see [Pill and floating bars › Transparent bars](pill-and-floating-bars.md#transparent-bars-detached-popouts)).
  - **Keyboard:** it takes the keyboard itself (OnDemand) when its content asks.
- **Edge popouts** (`EdgePopout`) sit inside what's reserved; see [Hosts and switching › Screen-edge popouts](hosts-and-switching.md#screen-edge-popouts).
- **`PopoutAnchor`** finds its host by itself through its window's `popoutHost` (`QsWindow.window`). That host is either a bar's popouts or a popout's submenu.

### Testing
- `scripts/dev/popout_matrix.py` shoots every kind of popout across combinations of bar, border and opacity, for checking them by eye.
- It rewrites config.json and restores it afterwards.
- A new intersection case is a `SurfaceContext` rule plus a `tst_SurfaceContext` row.
