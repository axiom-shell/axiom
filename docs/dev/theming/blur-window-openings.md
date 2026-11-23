# Blur window and openings

> **Files:** `qml/shell/BlurBacking.qml`, `qml/shell/BlurBackingWindow.qml`, `qml/services/ui/BlurManager.qml`, `qml/components/hosts/popout/BlurShape.qml`, `qml/components/hosts/popout/Copies.qml`, `qml/components/hosts/popout/KeyedModel.qml`, `qml/components/hosts/popout/AttachedSurfaceCopy.qml`, `qml/components/hosts/popout/ChromeComposite.qml`, `qml/components/reusable/HoledCopy.qml`, `qml/components/methods/PaintOrder.qml`, `qml/components/hosts/popout/OutsideShadow.qml`, `qml/components/hosts/popout/LayerOrigin.qml`, `qml/components/hosts/popout/BorderOpening.qml`, `qml/components/hosts/popout/StrokeOpening.qml`, `qml/components/reusable/HoledItem.qml`, `qml/components/surfaces/border/BorderPanel.qml`, `qml/components/surfaces/border/RoundedBorders.qml`
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
- `qml/shell/BlurBacking`: one click-through `axiom-blur-backing` window per screen (a `qml/shell/BlurBackingWindow`), layer order 9 (under the chrome, over the backdrop).
  - It draws a copy of each shape (`AttachedSurfaceCopy`, an `AttachedSurface` `mirror`, its geometry bound to the source's, sliding with it; a strip that slides reads `SlideAnimation.slideX`/`slideY`).
  - It draws every shape's fill and its stroke, in painter's order and as one image: see Strokes in the backing window. A fading copy (a toast, a menu tile, a covered island) fades alone through `BlurShape.fade`.
- It's the only one of these windows the compositor blurs, in one pass (on niri only where it sends its shapes as its blur region: [translucency](translucency-blur.md) › niri: blur regions). The overlay, the floating launcher and switcher and the other free-standing surfaces still blur themselves (notification toasts are backed by it: a card is a `BlurShape` rect, the attached box an EdgePopout).
- The chrome draws its own outer fill and stroke transparent while backed (`AttachedSurface.backed`, `BarContainer.backed`, `RoundedBorders.backed`, `ToastItem`'s border, the integrated edge menu's border-off line): it draws its content only. The one exception is the integrated edge menu's framed box, which keeps its fill and stroke in the menu window in every mode.

### Over the overlay
- The overlay (Overlay layer) covers the blur window. So while it's open on a screen (`BlurManager.aboveOverlay`), a second `BlurBackingWindow` there, `axiom-blur-backing-overlay`, draws the shapes of the surfaces on the Overlay layer (`BlurShape.overlayLayer`: bar popouts and their submenus, edge popouts, the OSD; a dock's preview has no origin and fills and blurs itself), and the first window drops them.
  - Its order (see `docs/dev/generated/layers.md`) puts it after the overlay and before every surface it draws for, and it maps without Hyprland's animation.
  - Both over windows (`fills` and `shadows`, or `all`) are always in `BlurBacking`'s model, unmapped while the overlay's windows aren't wanted (`overlayWindows`: the overlay open there, or its hand-off not yet back), so an overlay opening makes no window delegates.
  - Its blur rule never uses xray (`LayerStack.blurOverOverlay`): what it blurs is the overlay.
- Only the Overlay-layer shapes move up. Drawn over the Top layer, a bar's fill would cover the bar's content.
- The window under the overlay gives way to them: it holds their shapes as `erasers` while the windows over the overlay draw and erases each (its fill path erased, half a level under the shape's, so a popout over the overlay hides the bar's fill and stroke under it, not drawn twice) once it has given the shape up (it no longer `draws` it). The window over the overlay gives way to nothing.
- The hand-off keeps some window drawing the popout's box in every frame (`BlurBacking`'s `overlayTaken`): the main window gives the shapes up and erases them only once the overlay's window has drawn them, and draws them back at once when the overlay closes, while the other still does; that window goes after the main one's frame has them. Both draw it for at most a frame on each switch. The over windows stay in the model, unmapped until `overlayWindows`, so the hand-off flips only which window `draws` a shape, never builds a copy.
- Each window casts only its own shapes' shadows, but cuts them by every shape on the screen (the copies of the shapes the other window draws, `BlurBackingWindow.draws(shape, !over)`), as the one window does. So a popout's shadow never falls on the bar it's joined to.
- Every blur window on a screen keeps a copy of every shape there, drawing only its own (`BlurBackingWindow.draws`, `Copies.drawsOnly`): the overlay opening or closing, or a popout's layer flipping, toggles which copies show and builds none.

### Copies
- `Copies.qml` is one copy of each of `shapes` (and `erasers`), one slot per shape; `BlurBackingWindow` makes its colour, alpha and outline copies of it, and `tests-layout/tst_ChromeComposite` draws through the same file.
- The copies are a keyed `ListModel` (`KeyedModel.qml`, by `BlurShape.uid` through `BlurManager.shapeOf`), so a shape coming or going adds or removes only its own.
- Any copy moving, resizing, sliding or changing colour, or its holes changing, nudges the window (`FrameNudge`).

### Strokes in the backing window
- While backed, the backing window draws every shape's stroke with its fill (`BlurShape.strokeColor`: an attached surface's own, else what its site sets), in painter's order (`methods/PaintOrder`: base, frame, bar, merge, surface, submenu, toast; each `BlurShape.paintLevel`, a copy's `z`). A surface drawn over a bar hides the bar's stroke under its fill, so joined shapes need no cut and their strokes meet without a seam at any scale.
- It draws into two captures, in colour (premultiplied, `BlurBackingWindow.colorCopies`) and in alpha (grey, `alphaCopies`), which `ChromeComposite` joins as `vec4(color.rgb, alpha.r)`:
  - a fill is painted opaque (its colour times its alpha, or the alpha in grey), so a higher shape replaces what lies under it;
  - a stroke is painted over it at its own colour and alpha with Qt's normal blending, which over those captures is exactly Porter-Duff over: the same pixel the host drew over the backed fill before, for any stroke and fill alpha;
  - a `Rectangle` source's border is drawn the way the source draws it (on itself for a toast card, else a border-only rectangle over the fill: islands, the solid bar's inner stroke, the integrated edge menu's border-off line); a rect or frame with no fill alpha draws no fill.
  - the border's frame stroke is drawn as the border's own pieces draw it, not as a path: the strips' stroke `Rectangle`s and the corner pieces, on the device pixels their windows show on (`RoundedBorders.strokeRects`, `cornerBoxes`; `FrameOutline.strokePixels`/`windowPixels`), so it is the pixels the unbacked border draws at any scale.
- Both captures are sampled 1:1 (`smooth: false`, the window's buffer in device pixels).
- At a join's fillet tips only the higher shape's stroke covers the lower stroke, so the lower shape's copy leaves its stroke out where its source leaves it open (`strokeHoles`), through `reusable/HoledCopy`: its drawing outside the holes, its fill alone inside, in clipped pieces, no layer. The holes' outer edges are drawn in by a 64th of a px (`Utils.tieInset`, `Utils.insetUnion`). The scissor rounds a .5 device px into the hole, so at a fractional scale the pixel centred on a band's end lost its stroke there. The outline's drawn stroke is narrowed by the same 64th on each edge, since a CurveRenderer stroke whose edge is on a device pixel's centre draws that pixel at full coverage (a lone bright pixel in a straight wall). The holes come from the openings below, in every mode, each cut across the stroke by `EdgeAttach.strokeHoleAcross`: the stroke's width and a pixel of anti-aliased fringe either side. Along it (`EdgeAttach.strokeHoleAlong`) a hole is the span the covering surface runs over, a pixel longer where it reaches the stroked box's end: a flush surface's wall runs on from the box's there and draws that fringe itself, which the box's own wall drew under it before (a brighter dash at the join).
- `tests-layout/tst_ChromeComposite.qml` reads the composite as pixels (at scale 1 and 1.25): [Testing](../testing.md).

### Shadows in the backing window
- Backed surfaces' shadows are cast there too, from the outlines of the same shapes' copies (fill and stroke).
- Each `BlurShape` names its `shadow` (a look: BarStyle's, or its bar's). An `AttachedSurface`'s follows `castShadow` and `shadowLook`.
- The copies are grouped by look (`BlurBackingWindow.shadowKey`): its color and size.
- Each group casts one `SurfaceShadow` cut by every shape on the screen:
  - a shadow runs unbroken round joined surfaces;
  - none falls on a surface joined to the one casting it (no holes needed).
- Kept under the blur threshold, they aren't blurred.
- Where the blur has no threshold (SwayFX's `blur_ignore_transparent` blurs every pixel that isn't clear; no `supports.blurThreshold`), it would frost the whole halo. So the backing windows draw only the fills (`BlurBackingWindow.part`), and a window beside each, in a namespace nothing blurs (`axiom-shadows`, `axiom-shadows-overlay`; `LayerStack.layers`), casts the shadows from its own copies (`BlurManager.shadowsApart`).
- Meanwhile the surfaces' own shadows (`OutsideShadow`, inactive while `backed`) and the border's shadow window stand down, blurred or not (the backing window draws every mode's chrome: opaque and blur off too).

### Unbacked shadows
- Unbacked (Top-layer chrome under a fullscreen window, a window not placed within `LayerOrigin`'s timeout, a `FreeMenu` while it scales), each surface casts its own again, from a black copy of its shape kept off screen (`OutsideShadow.hideTarget`):
  - `AttachedSurface`'s;
  - the bar's: each pill, island and solid fill puts its copy in `shadowShape` (pills an `AttachedSurfaceCopy`).
- The bar shadow's holes:
  - the bar's `openings`, where surfaces cover its far stroke, stretched or not;
  - the fillets curving into a solid bar's stroke at either end of an opening, only up to their curve (`OutsideShadow.fillets`, from the opening's `startFillet`/`endFillet`: `SurfaceContext.opening`, in whole pixels so the fillet's cap and the stroke don't each half-cover one). That covers a pill joined to the stroke at its end, and a popout standing on the stroke, whose attach-side fillets are at both ends of its cover (`AttachedSurface.coverStartFillet`/`coverEndFillet`). Without them the bar's shadow was cut across each fillet's whole square, a hard seam where the opening ended;
  - the solid bars its ends make way for, whose stroke its window overlaps;
  - past a pill's or island's end squared for a surface running flush on from it, beside the wall and under the surface (`_flushEnds`).
- Where a wall runs on from one surface into another, each casts as if it carried on, then gives way to the other at the line where they meet: [Shadows › Walls that run on](../popouts/shadows.md#walls-that-run-on-into-another-surface-unbacked).
- More on shadow looks: [Shadows](../popouts/shadows.md).

### Strokes left open under surfaces
- Where a joined surface's stroke meets the one it stands on, the stroke it stands on is left open (while backed, by the copy's `HoledCopy`; unbacked, by the host's own `HoledItem`, `BorderPanel` pieces and corner hiding):
  - a pill's or island's far stroke under a popout (`PillStretch.opening` → `BarContainer.setRequest`);
  - a popout's side under a submenu (`BarPopouts.submenuHole`, `AttachedSurface.strokeHoles`), drawn through `reusable/HoledItem`;
  - a dock joined to the border opens it as edge popouts do.
- An opening spans only what's drawn over it (`AttachedSurface.coverStart`/`coverLength`):
  - the box while it slides;
  - its fillets too once it's out. Until then they're behind the edge it slides from, and an opened stroke showed as a dark gap at each corner.
- Every opening is published on whole pixels (`SurfaceContext.opening`, ceil start, floor end): the pill's (`EdgePlacement`'s stretch and submenu openings, a pill bar's `PillBarJoin`, `CornerMerge`) and the border's (`BarContainer.borderOpening`/`joinOpening`) as `StrokeOpening`'s, so the thresholded mask cuts no pixel the wall covers less than half, and one is re-sent once per pixel, not every frame.
- A submenu's popup takes no compositor adjustment: its window reaches past the parent's, and a nudge left its blur and the parent's opening behind.

### Where a window is (LayerOrigin)
- Layer windows don't know where they are, so axiom works it out on every compositor ([layer arrangement](../compositor/layer-arrangement.md)):
  - each `hosts/popout/LayerOrigin` reports its window's anchors, margins, size, zone and when it mapped to `LayerManager`;
  - `LayerManager` places them all with `methods/LayerArrange`, and each `LayerOrigin` reads its own window's rect back (`LayerManager.rectOf`).
- A window that reserves nothing has its origin before it maps, where it will go, so it's backed from its first frame. A reserving window has one only while mapped.
- On Hyprland the result is corrected from its layer list (`CompositorManager.withLayerRects`), so other apps' layers and reserved space count too; a difference is logged as `LayerManager: corrected from the compositor` (`scripts/log.sh --debug -g LayerManager`).
- Until its origin is known, a surface fills itself. Two watchdogs say so when it goes wrong (`console.warn`, once): a `LayerOrigin` whose window drew its first frame with no origin while backed, and a backing window that has shapes but isn't shown a second after they came.
- A bar popout's and submenu's place follows from their bar's.

### Joins: openings in the border's stroke
- A surface joined to the border's stroke (`EdgePopout`) publishes the stretch it covers:
  - `SurfaceManager.setBorderOpening`, through a `hosts/popout/BorderOpening`, which takes it back as it goes;
  - in screen px along the edge; its edge coordinates start at `ScreenEdgeManager.reservedWithMenusOn(startSide)`;
  - on whole pixels (see Strokes left open under backed surfaces).
- `BorderPanel` leaves its stroke and the fill of the stroke's row open there (`Utils.subtractSpans`).
  - It nudges its window (`FrameNudge`) only when its own openings changed: `SurfaceManager.borderOpenings` is a new array whenever any opening on any screen moves.
  - A strip's own offset along its edge (`screenOffset`) is read through `LayerOrigin`. Until then it's taken as half what the edges across it reserve.
- The same goes for strokes a surface is joined over. An opening is cut in every mode, opaque too (the backing window's copies cut the stroke), so no fill shows a line through it.
- Pills publish theirs too (`BarContainer.borderOpening`, from the bar's place on screen).

### Joins on a perpendicular edge
- Any surface joined to a perpendicular edge opens that edge's stroke down to its join's fillet (`EdgeAttach.joinOpening`, `AttachedSurface.joinShown`: as much as is out past its edge), and `RoundedBorders` leaves the corner piece out there.
  - Such surfaces: a pill, a bar popout, an edge popout or dock running the whole edge (on a pill bar's edge too).
- Bar popouts merged into the bar, or on a solid bar's inner edge, do the same.

### Border off: the solid bar's inner stroke
- With the border off, a solid bar draws its own inner stroke, left open through the openings in its `BarContainer.setRequest`s, in every mode.
- Bar popouts set their openings directly.
- Edge popouts and docks (and bar popouts' joined ends) route the same screen-px spans through `hosts/popout/StrokeOpening`:
  - the stretch they stand on, a joined submenu's, and their joined ends' with their fillet;
  - it puts them on that bar's container (a `PillStretch`), on whole pixels (as every opening, above).

### Submenu joins
- A submenu joined to its parent's bar side reports the stretch its end covers (`SubPopout.joinSpan` → `submenuJoinSpan`).
- It's opened in the pill (a second `PillStretch`) or the border.
- The parent's fillet on that side is opened under it (`AttachedSurface.attachFilletHole`).

### Timing
- Every window drawing an opening (the bar, the border strips and corners, a popout under its submenu's hole) bursts a `FrameNudge` when it changes, since the change comes from another window sliding.
- A tiled (hollow) menu publishes no opening (`EdgePlacement._hollow`, `PillBarJoin.hollow`): the line runs on under its tiles, in every mode. A joined submenu of it publishes its own.
- `HoledItem` keeps its layer while translucent (`keepLayer`), so its first hole is cut from its first frame.
- A fillet's part of an opening leads the slide by a stroke's width (`AttachedSurface._filletHidden`), as the window drawing it commits a frame or so later.
