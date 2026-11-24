# Popout shadow

> **Files:** `qml/components/hosts/popout/SurfaceShadow.qml`, `qml/components/hosts/popout/OutsideShadow.qml`, `qml/components/hosts/popout/ShapeShadow.qml`, `qml/components/hosts/popout/AttachedSurface.qml`, `qml/components/hosts/popout/SlideAnimation.qml`, `qml/components/methods/SurfaceContext.qml`, `qml/components/bar/BarContainer.qml`
> **Config:** `Bars.style.shadow` (`enabled`, `color`, `size`)
> **Related:** [Surface context](surface-context.md), [Submenus](submenus.md), [Translucency and blur](../theming/translucency-blur.md), [Blur window and openings](../theming/blur-window-openings.md), [Bar layering and corners](../bar/layering-and-corners.md)

Every surface with an exposed border casts the shell's shadow. It uses the bars' shared style's shadow (`Bars.style.shadow`: `enabled`, `color` (Auto: the accent) and `size`; reader `BarStyle.look`), as the bars and border do. It always spreads evenly, so it never slides onto a stroke the surface joins. Read this before touching how any popout, dock or submenu casts its shadow. (Rule: [qml-pitfalls](../core/qml-pitfalls.md) › Effects.)

### How it is drawn
- **`hosts/popout/SurfaceShadow`:** a `MultiEffect`, in `Style.shadowColor(look)` (memoised per look).
  - It is kept only outside the surface's shape (`cut`), so none of it shows through a translucent fill.
  - `cut` covers only pixels the surface covers fully. Under the surface's anti-aliased edge the shadow stays; otherwise a pixel's gap shows.
- **The backing window casts the shadow,** in every mode, from the shapes' outlines (fill and stroke), as one group: what a shape joins is cut out of it and the shadow runs round the whole, so no surface casts its own and no hole or run-on is cut by hand. A surface the backing window can't place or show (the unbacked fallback) casts none. See [Translucency and blur](../theming/translucency-blur.md).
- **The overlay page box's is drawn under its target** by `hosts/popout/OutsideShadow` (through `ShapeShadow`), which captures the target with room for the shadow. `shadowColor` lets a caller set the colour (the overlay page box's `Style.shadowSoft`).
- **The overlay page box** (`hosts/popout/ShapeShadow`) draws its shadow from its size and corner radius: an OutsideShadow of a small box of that radius, rendered once (again only when the radius or shadow size changes) and cut in nine, the corners as they are and the edges stretched along their length, so the box growing between pages costs eight quads and no capture or blur of a box-sized texture. Qt API: `ShaderEffectSource` (`sourceRect`, `textureSize`, `live: false`, `scheduleUpdate`) and `MultiEffect`, all in Qt 6.5+ (Fedora stable ships 6.11).
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
  - edge popouts: OSDs, floating edge menus, the launcher and the window switcher
  - docks
- **The dock's detached box.**
- **Not a bar's own pills:** their bar's layer casts their shadow.
- **Only the outline casts it,** not the content.

### Room for it
- **Overflow:** `SlideAnimation.overflow` lets the shadow draw past the surface on every side except the one it slides from. A copy (`AttachedSurfaceCopy`) has no shadow, so `startOverflow`/`endOverflow` give it a pixel past a wall standing on its edge, for the wall's anti-aliased fringe.
  - That side's clip still hides the surface until it's out.
  - It also keeps the shadow off the bar the surface grows from.
- **Window room:** each window keeps its look's reach of room for the shadow (`AttachedSurface.shadowReach`):
  - `BarPopouts.spareAcross`
  - `EdgePopout`'s depth
  - the dock's depth
  - the submenu's `shadowRoom`
