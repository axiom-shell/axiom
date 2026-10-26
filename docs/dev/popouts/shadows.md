# Popout shadow

> **Files:** `components/hosts/popout/SurfaceShadow.qml`, `components/hosts/popout/OutsideShadow.qml`, `components/hosts/popout/AttachedSurface.qml`, `components/hosts/popout/SlideAnimation.qml`, `components/methods/SurfaceContext.qml`, `components/bar/BarContainer.qml`
> **Config:** `Bars.style.shadow` (`enabled`, `color`, `size`)
> **Related:** [Surface context](surface-context.md), [Submenus](submenus.md), [Translucency and blur](../theming/translucency-blur.md), [Blur window and openings](../theming/blur-window-openings.md), [Bar layering and corners](../bar/layering-and-corners.md)

Every surface with an exposed border casts the shell's shadow. It uses the bars' shared style's shadow (`Bars.style.shadow`: `enabled`, `color` (Auto: the accent) and `size`; reader `BarStyle.look`), as the bars and border do. It always spreads evenly, so it never slides onto a stroke the surface joins. Read this before touching how any popout, dock or submenu casts its shadow. (Rule: AGENTS.md › QML pitfalls, `MultiEffect` and `OutsideShadow`.)

### How it is drawn
- **`hosts/popout/SurfaceShadow`:** a `MultiEffect`.
  - It is kept only outside the surface's shape (`cut`), so none of it shows through a translucent fill.
  - `cut` covers only pixels the surface covers fully. Under the surface's anti-aliased edge the shadow stays; otherwise a pixel's gap shows.
- **While the blur window backs a surface,** the blur window casts the shadow instead. See [Translucency and blur](../theming/translucency-blur.md).
- **Drawn under its target** by `hosts/popout/OutsideShadow`, which captures the target with room for the shadow.
- **`holes`:** the parts OutsideShadow leaves out are:
  - where surfaces joined to the target sit;
  - for an attached surface, the stroke it grows out of, beside it as well as under it (not on a bare edge). Its window is over that stroke's, so a shadow there dims the stroke. It is darkest under the surface's soft edge, which made a 1px seam where the two strokes meet;
  - the bar's open popouts (its stretches);
  - for the border's own shadow window, `SurfaceManager.borderOpenings`.
    - A joined end's opening carries its fillet (`startFillet`/`endFillet`, `EdgeAttach.joinOpening`), and a surface's own cover its attach-side fillets at both ends.
    - That window leaves it out only as far as its curve, as a bar's `OutsideShadow.fillets` does.
- **Never on the surface's own layer:** never use a `layer.effect` on a visible surface's own layer, or hand that layer directly to a `MultiEffect`. Its padding would redraw that surface in the padded rect.

### Which look it casts
- **Each surface casts what it grows out of casts** (`SurfaceContext.shadow`). This is handed to `AttachedSurface.shadowLook`.
  - So joined shapes land in one `BlurBacking` group, and one shadow runs round them.
- **By what it grows out of:**
  - **Out of a bar** (its pills, islands, a merged box's outer edge, or a solid bar's own stroke with the border off): the bar's look (a bar may have its own, `Bars.items[].style.shadow`).
  - **Out of the border's stroke, off a bare edge, or free-standing (`detached`):** BarStyle's.
  - **A submenu:** casts its parent's look (`host.popupSurface`).

### Who casts it
- **`AttachedSurface.castShadow`:**
  - bar popouts and submenus
  - edge popouts: OSDs, floating edge menus, the attached launcher
  - docks
- **The dock's detached box.**
- **`FloatingPopout`:** a copy of its box sits behind it and casts. This covers the floating launcher and the window switcher.
- **Not a bar's own pills:** their bar's layer casts their shadow.
- **Only the outline casts it,** not the content.

### Room for it
- **Overflow:** `SlideAnimation.overflow` lets the shadow draw past the surface on every side except the one it slides from.
  - That side's clip still hides the surface until it's out.
  - It also keeps the shadow off the bar the surface grows from.
- **Window room:** each window keeps its look's reach of room for the shadow (`AttachedSurface.shadowReach`):
  - `BarPopouts.spareAcross`
  - `EdgePopout`'s depth
  - the dock's depth
  - the submenu's `shadowRoom`
- **Submenu boxes:** unbacked, a parent's own shadow also leaves out its submenu's box (`AttachedSurface.shadowHoles`, from `SubPopout`'s `submenuBox`).

### Walls that run on into another surface (unbacked)
- Unbacked, each surface casts its own shadow, so where one surface's straight wall carries on as another's, each shadow would fade out at the line where they meet, as at a corner, and the two half-faded shadows met in a visible step.
- **The rule:** each side casts as if the wall ran on past the meeting line, then gives way to the other's there. Both are at full strength at the line, so there is no step. The run-on is a wide black rect in the shadow's source: a thin strip's blur is much weaker.
- **On the surface's side** (`AttachedSurface.shadowRunOn(reach)`):
  - behind a flush end, the wall of the island or pill it continues; cut up to the stroke's outer edge by the band hole;
  - past a straight joined end (a submenu running straight into a squared pill or island, or off a bare edge), along its far wall; it gives way across the stroke it joins as well;
  - behind an attach edge it runs straight off (a bare screen edge), so the shadow beside its walls doesn't fade at the screen's edge.
  - A bar's pills cast through their bar, which adds their run-ons to its source.
- **On the bar's side** (`BarLayout.flushEnds`, tested in `tst_BarLayout`; drawn by `BarContainer._flushEnds`): a pill's or island's end squared for a surface's stretch (or an end reach: a pill bar's end pill run on to a popout on the perpendicular edge, `PillBarJoin`) casts its wall on past its inner edge, and is cut beside the wall past it and under the surface, never past the surface's box (the stretch's `box`). Only while that surface is out over the stroke (the stretch's `covered`, `PillStretch.covered` from `EdgePlacement`): squared before the surface slid out, the pill's own wall lost its shadow and the run-on glowed under it.
- **A parent and its submenu** (`AttachedSurface.wallsRunOn`, the submenu's box from `EdgeSurface`): where the submenu's box lines up with one of the parent's walls beside it (flush to a free end of its side), the parent's wall runs on and gives way past the parent's side. The submenu's own flush end runs on from its side.
- **While sliding,** the band stays on the stroke where it is in the window (it reaches `hiddenNow` further), not where it is on the surface still behind its edge: otherwise a line of the surface's shadow showed over the stroke, doubling the bar's.
- Unbacked surfaces are opaque (a compositor that can't blur gets solid surfaces, `Appearance.surfaceAlpha`; a paused blur turns them solid), so none of this meets a translucent fill; backed, the blur window's one shadow has no seams to begin with.
- What's left is about 3 levels (of 255) between the two windows' shadows at the line, and the walls' anti-aliased edge where two strokes overlap.
