# Blur window and openings

> **Files:** `shell/BlurBacking.qml`, `shell/BlurBackingWindow.qml`, `services/ui/BlurManager.qml`, `components/hosts/popout/BlurShape.qml`, `components/hosts/popout/AttachedSurfaceCopy.qml`, `components/hosts/popout/OutsideShadow.qml`, `components/hosts/popout/LayerOrigin.qml`, `components/hosts/popout/BorderOpening.qml`, `components/hosts/popout/StrokeOpening.qml`, `components/reusable/HoledItem.qml`, `components/surfaces/border/BorderPanel.qml`, `components/surfaces/border/RoundedBorders.qml`
> **Config:** `Appearance.surface.*`
> **Related:** [Translucency and blur](translucency-blur.md), [Shadows](../popouts/shadows.md), [Surface context](../popouts/surface-context.md), [Edge attach](../popouts/edge-attach.md), [Submenus](../popouts/submenus.md)

How the chrome's translucent surfaces share one blurred backing window, how their shadows are cast there, how a window learns where it is on screen, and how strokes are opened where surfaces join.

### Why one blur window
- A surface blurring on its own blurs what's drawn under it, other surfaces' fills included, up to blur size × 2^passes past its edge. So joined surfaces never matched.
- Instead the chrome registers its shapes with `BlurManager`. The chrome is:
  - the border's frame, bars, bar popouts and submenus;
  - edge popouts: OSDs, floating edge menus, the attached launcher;
  - integrated edge menus' strips, docks.
- A shape is a `hosts/popout/BlurShape`: an `AttachedSurface`, a `Rectangle` or the border's `frame`, with its top-left on screen and its fill color.
- `shell/BlurBacking`: one click-through `axiom-blur-backing` window per screen (a `shell/BlurBackingWindow`), layer order 9 (under the chrome, over the backdrop).
  - It draws a copy of each shape (`AttachedSurfaceCopy`, an `AttachedSurface` `mirror`, its geometry bound to the source's, sliding with it; a strip that slides reads `SlideAnimation.slideX`/`slideY`).
  - All copies are drawn opaque and then at the surface opacity at once, so overlaps never stack.
- It's the only one of these windows the compositor blurs, in one pass (on niri only where it sends its shapes as its blur region: [translucency](translucency-blur.md) › niri: blur regions). The overlay, the floating launcher and switcher, notifications and the other free-standing surfaces still blur themselves.
- The chrome draws its own outer fill transparent: `AttachedSurface.backed`, `BarContainer.backed`, `RoundedBorders.backed`.

### Over the overlay
- The overlay (Overlay layer) covers the blur window. So while it's open on a screen (`BlurManager.aboveOverlay`), a second `BlurBackingWindow` there, `axiom-blur-backing-overlay`, draws the shapes of the surfaces on the Overlay layer (`BlurShape.overlayLayer`: bar popouts and their submenus, edge popouts, the OSD; a dock's preview has no origin and fills and blurs itself), and the first window drops them.
  - Its order (see `docs/dev/generated/layers.md`) puts it after the overlay and before every surface it draws for, and it maps without Hyprland's animation.
  - Its blur rule never uses xray (`LayerStack.blurOverOverlay`): what it blurs is the overlay.
- Only the Overlay-layer shapes move up. Drawn over the Top layer, a bar's fill would cover the bar's content.
- Each window casts only its own shapes' shadows, but cuts them by every shape on the screen (`BlurBackingWindow.cutBy`, the other window's), as the one window does. So a popout's shadow never falls on the bar it's joined to.

### Copies
- The copies are a keyed `ListModel` (`KeyedModel`, by `BlurShape.uid` through `BlurManager.shapeOf`), so a shape coming or going adds or removes only its own.
- Any copy moving, resizing or sliding nudges the window (`FrameNudge`).

### Shadows in the blur window
- Backed surfaces' shadows are cast there too, from the same copies.
- Each `BlurShape` names its `shadow` (a look: BarStyle's, or its bar's). An `AttachedSurface`'s follows `castShadow` and `shadowLook`.
- The copies are grouped by look (`BlurBackingWindow.shadowKey`): its color and size.
- Each group casts one `SurfaceShadow` cut by every shape on the screen:
  - a shadow runs unbroken round joined surfaces;
  - none falls on a surface joined to the one casting it (no holes needed).
- Kept under the blur threshold, they aren't blurred.
- Where the blur has no threshold (SwayFX's `blur_ignore_transparent` blurs every pixel that isn't clear; no `supports.blurThreshold`), it would frost the whole halo. So the blur windows draw only the fills (`BlurBackingWindow.part`), and a window beside each, in a namespace nothing blurs (`axiom-shadows`, `axiom-shadows-overlay`; `LayerStack.layers`), casts the shadows from its own copies.
- Meanwhile the surfaces' own shadows (`OutsideShadow`, inactive while `backed`) and the border's shadow window stand down.

### Unbacked shadows
- Unbacked (paused, solid, or a window not yet placed), each surface casts its own again, from a black copy of its shape kept off screen (`OutsideShadow.hideTarget`):
  - `AttachedSurface`'s;
  - the bar's: each pill, island and solid fill puts its copy in `shadowShape` (pills an `AttachedSurfaceCopy`).
- The bar shadow's holes:
  - the bar's `openings`, where surfaces cover its far stroke, stretched or not;
  - the fillets curving into a solid bar's stroke at either end of an opening, only up to their curve (`OutsideShadow.fillets`, from the opening's `startFillet`/`endFillet`: `SurfaceContext.opening`, in whole pixels so the fillet's cap and the stroke don't each half-cover one). That covers a pill joined to the stroke at its end, and a popout standing on the stroke, whose attach-side fillets are at both ends of its cover (`AttachedSurface.coverStartFillet`/`coverEndFillet`). Without them the bar's shadow was cut across each fillet's whole square, a hard seam where the opening ended;
  - the solid bars its ends make way for, whose stroke its window overlaps;
  - past a pill's or island's end squared for a surface running flush on from it, beside the wall and under the surface (`_flushEnds`).
- Where a wall runs on from one surface into another, each casts as if it carried on, then gives way to the other at the line where they meet: [Shadows › Walls that run on](../popouts/shadows.md#walls-that-run-on-into-another-surface-unbacked).
- More on shadow looks: [Shadows](../popouts/shadows.md).

### Strokes left open under backed surfaces
- Where a surface's fill used to hide a stroke it's joined over, the stroke is left open:
  - a pill's or island's far stroke under a popout (`PillStretch.opening` → `BarContainer.setRequest`);
  - a popout's side under a submenu (`BarPopouts.submenuHole`, `AttachedSurface.strokeHoles`), drawn through `reusable/HoledItem`;
  - a dock joined to the border opens it as edge popouts do.
- An opening spans only what's drawn over it (`AttachedSurface.coverStart`/`coverLength`):
  - the box while it slides;
  - its fillets too once it's out. Until then they're behind the edge it slides from, and an opened stroke showed as a dark gap at each corner.
- A submenu's popup takes no compositor adjustment: its window reaches past the parent's, and a nudge left its blur and the parent's opening behind.

### Where a window is (LayerOrigin)
- Layer windows don't know where they are, so axiom works it out on every compositor ([layer arrangement](../compositor/layer-arrangement.md)):
  - each `hosts/popout/LayerOrigin` reports its window's anchors, margins, size, zone and when it mapped to `LayerManager`;
  - `LayerManager` places them all with `methods/LayerArrange`, and each `LayerOrigin` reads its own window's rect back (`LayerManager.rectOf`).
- A window that reserves nothing has its origin before it maps, where it will go, so it's backed from its first frame. A reserving window has one only while mapped.
- On Hyprland the result is corrected from its layer list (`CompositorManager.withLayerRects`), so other apps' layers and reserved space count too; a difference is logged as `LayerManager: corrected from the compositor` (`scripts/log.sh --debug -g LayerManager`).
- Until its origin is known, a surface fills itself.
- A bar popout's and submenu's place follows from their bar's.

### Joins: openings in the border's stroke
- A surface joined to the border's stroke (`EdgePopout`) publishes the stretch it covers:
  - `ShellManager.setBorderOpening`, through a `hosts/popout/BorderOpening`, which takes it back as it goes;
  - in screen px along the edge; its edge coordinates start at `reservedOn(startSide)`.
- `BorderPanel` leaves its stroke and the fill of the stroke's row open there (`Utils.subtractSpans`).
  - A strip's own offset along its edge (`screenOffset`) is read through `LayerOrigin`. Until then it's taken as half what the edges across it reserve.
- The same goes for strokes a surface is joined over. An opening is cut whenever surfaces are translucent, blurred or not, so a translucent fill doesn't show a line through it.
- Pills publish theirs too (`BarContainer.borderOpening`, from the bar's place on screen).

### Joins on a perpendicular edge
- Any surface joined to a perpendicular edge opens that edge's stroke down to its join's fillet (`EdgeAttach.joinOpening`, `AttachedSurface.joinShown`: as much as is out past its edge), and `RoundedBorders` leaves the corner piece out there.
  - Such surfaces: a pill, a bar popout, an edge popout or dock running the whole edge (on a pill bar's edge too).
- Bar popouts merged into the bar, or on a solid bar's inner edge, do the same.

### Border off: the solid bar's inner stroke
- With the border off, a solid bar draws its own inner stroke, left open through the openings in its `BarContainer.setRequest`s. This holds opaque or not, as the windows' stacking isn't the bar's.
- Bar popouts set their openings directly.
- Edge popouts and docks (and bar popouts' joined ends) route the same screen-px spans through `hosts/popout/StrokeOpening`:
  - the stretch they stand on, a joined submenu's, and their joined ends' with their fillet;
  - it puts them on that bar's container (a `PillStretch`), on whole pixels (`SurfaceContext.opening`).

### Submenu joins
- A submenu joined to its parent's bar side reports the stretch its end covers (`SubPopout.joinSpan` → `submenuJoinSpan`).
- It's opened in the pill (a second `PillStretch`) or the border.
- The parent's fillet on that side is opened under it (`AttachedSurface.attachFilletHole`).

### Timing
- Every window drawing an opening (the bar, the border strips and corners, a popout under its submenu's hole) bursts a `FrameNudge` when it changes, since the change comes from another window sliding.
- `HoledItem` keeps its layer while translucent (`keepLayer`), so its first hole is cut from its first frame.
- A fillet's part of an opening leads the slide by a stroke's width (`AttachedSurface._filletHidden`), as the window drawing it commits a frame or so later.
