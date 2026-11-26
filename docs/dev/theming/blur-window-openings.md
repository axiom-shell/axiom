# Blur window and openings

> **Files:** `qml/shell/BlurBacking.qml`, `qml/shell/BlurBackingWindow.qml`, `qml/services/ui/BlurManager.qml`, `qml/components/hosts/popout/BlurShape.qml`, `qml/components/hosts/popout/Copies.qml`, `qml/components/hosts/popout/KeyedModel.qml`, `qml/components/hosts/popout/AttachedSurfaceCopy.qml`, `qml/components/hosts/popout/ChromeComposite.qml`, `qml/components/reusable/HoledCopy.qml`, `qml/components/methods/PaintOrder.qml`, `qml/components/hosts/popout/OutsideShadow.qml`, `qml/components/hosts/window/LayerOrigin.qml`, `qml/components/hosts/popout/BorderOpening.qml`, `qml/components/hosts/popout/StrokeOpening.qml`, `qml/components/surfaces/border/BorderPanel.qml`, `qml/components/surfaces/border/RoundedBorders.qml`
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
- `qml/shell/BlurBacking`: one click-through `axiom-blur-backing` window per screen (a `qml/shell/BlurBackingWindow`), layer order 9 (under the chrome, over the overlay's page and the backdrop).
  - It draws a copy of each shape (`AttachedSurfaceCopy`, an `AttachedSurface` `mirror`, its geometry bound to the source's, sliding with it; a strip that slides reads `SlideAnimation.slideX`/`slideY`).
  - It draws every shape's fill and its stroke, in painter's order and as one image: see Strokes in the backing window. A fading copy (a toast, a menu tile, a covered island) fades alone through `BlurShape.fade`.
- It's the only one of these windows the compositor blurs, in one pass (on niri only where it sends its shapes as its blur region: [translucency](translucency-blur.md) › niri: blur regions). The overlay, the floating launcher and switcher and the other free-standing surfaces still blur themselves (notification toasts are backed by it: a card is a `BlurShape` rect, the attached box an EdgePopout).
- The chrome draws its own outer fill and stroke transparent while backed (`AttachedSurface.backed`, `BarContainer.backed`, `RoundedBorders.backed`, `ToastItem`'s border, the integrated edge menu's border-off line): it draws its content only. The one exception is the integrated edge menu's framed box, which keeps its fill and stroke in the menu window in every mode.

### Copies
- `Copies.qml` is one copy of each of `shapes`, one slot per shape; `BlurBackingWindow` makes its colour, alpha and outline copies of it, and `tests-layout/tst_ChromeComposite` draws through the same file.
- The copies are a keyed `ListModel` (`KeyedModel.qml`, by `BlurShape.uid` through `BlurManager.shapeOf`), so a shape coming or going adds or removes only its own.
- Any copy moving, resizing, sliding or changing colour, or its holes changing, nudges the window (`FrameNudge`).

### Strokes in the backing window
- While backed, the backing window draws every shape's stroke with its fill (`BlurShape.strokeColor`: an attached surface's own, else what its site sets), in painter's order (`methods/PaintOrder`: base, frame, bar, cornerJoin, surface, submenu, toast; each `BlurShape.paintRank`, a copy's `z`). A surface drawn over a bar hides the bar's stroke under its fill, so joined shapes need no cut and their strokes meet without a seam at any scale.
- It draws into two captures, in colour (premultiplied, `BlurBackingWindow.colorCopies`) and in alpha (grey, `alphaCopies`), which `ChromeComposite` joins as `vec4(color.rgb, alpha.r)`:
  - a fill is painted opaque (its colour times its alpha, or the alpha in grey), so a higher shape replaces what lies under it;
  - a stroke is painted over it at its own colour and alpha with Qt's normal blending, which over those captures is exactly Porter-Duff over: the same pixel the host drew over the backed fill before, for any stroke and fill alpha;
  - a `Rectangle` source's border is drawn the way the source draws it (on itself for a toast card, else a border-only rectangle over the fill: islands, the solid bar's inner stroke, the integrated edge menu's border-off line); a rect or frame with no fill alpha draws no fill.
  - the border's frame stroke is drawn as the border's own pieces draw it, not as a path: the strips' stroke `Rectangle`s, already left open under what joins them, a pixel centred on an opening's edge staying the stroke's (`BorderPanel.screenStrokePieces`, `Utils.tieInset`), and the corner pieces no opening covers, on the device pixels their windows show on (`RoundedBorders.strokeRects`, `cornerBoxes`; `FrameOutline.strokePixels`/`windowPixels`), so it is the pixels the unbacked border draws at any scale. The frame copy has no `HoledCopy`, and the frame's stroke is never cut again.
- Both captures are sampled 1:1 (`smooth: false`, the window's buffer in device pixels).
- At a join's fillet tips only the higher shape's stroke covers the lower stroke, so the lower shape's copy leaves its stroke out where its source leaves it open (`strokeHoles`; the frame's are its strips' own pieces instead), through `reusable/HoledCopy`: its fill drawn once, whole, and its stroke alone in clipped pieces outside the holes, no layer. The holes' outer edges are drawn in by a 64th of a px (`Utils.tieInset`, cut by `Utils.subtractHoles`, which `HoledCopy` and `FrameOutline.screenStrokePieces` both call). The scissor rounds a .5 device px into the hole, so at a fractional scale the pixel centred on a band's end lost its stroke there. The outline's drawn stroke is narrowed by the same 64th on each edge, since a CurveRenderer stroke whose edge is on a device pixel's centre draws that pixel at full coverage (a lone bright pixel in a straight wall). The holes come from the openings below, in every mode, each cut across the stroke by `EdgeAttach.strokeHoleAcross`: the stroke's width and a pixel of anti-aliased fringe either side. Along it (`EdgeAttach.strokeHoleAlong`) a hole is the span the covering surface runs over, a pixel longer where it reaches the stroked box's end: a flush surface's wall runs on from the box's there and draws that fringe itself, which the box's own wall drew under it before (a brighter dash at the join).
- `tests-layout/tst_ChromeComposite.qml` reads the composite as pixels (at scale 1 and 1.25): [Testing](../testing.md).

### Shadows in the backing window
- Backed surfaces' shadows are cast there too, from the outlines of the same shapes' copies (fill and stroke).
- Each `BlurShape` names its `shadow` (a look: BarStyle's, or its bar's). An `AttachedSurface`'s follows `castShadow` and `shadowLook`.
- The copies are grouped by look (`BlurBackingWindow.shadowKey`): its color and size.
- Each group casts one `SurfaceShadow` cut by every shape on the screen:
  - a shadow runs unbroken round joined surfaces;
  - none falls on a surface joined to the one casting it (no holes needed).
- Kept under the blur threshold, they aren't blurred.
- Where the blur has no threshold (SwayFX's `blur_ignore_transparent` blurs every pixel that isn't clear; no `supports.blurThreshold`), it would frost the whole halo. So the backing windows draw only the fills (`BlurBackingWindow.part`), and a window beside each, in a namespace nothing blurs (`axiom-shadows`; `LayerStack.layers`), casts the shadows from its own copies (`BlurManager.shadowsApart`).
- No surface casts its own, and the border has no shadow window: the backing window draws every mode's chrome (opaque and blur off too), shadows included.

### Unbacked shadows
- A surface the backing window can't place or show (Top-layer chrome under a fullscreen window, a window not placed within `LayerOrigin`'s timeout, a `FreeMenu` while it scales) casts none: it fills and strokes itself only.
- More on shadow looks: [Shadows](../popouts/shadows.md).

### Strokes left open under surfaces
- Where a joined surface's stroke meets the one it stands on, the stroke it stands on is left open by the backing window's copy (`HoledCopy`; an unbacked surface draws its stroke whole):
  - a pill's or island's far stroke under a popout (`PillStretch.opening` → `BarContainer.setRequest`);
  - a popout's side under a submenu (`BarPopouts.submenuHole`, `AttachedSurface.strokeHoles`);
  - a dock joined to the border opens it as edge popouts do.
- An opening spans only what's drawn over it (`AttachedSurface.coverStart`/`coverEnd`):
  - the box while it slides;
  - its fillets too once it's out. Until then they're behind the edge it slides from, and an opened stroke showed as a dark gap at each corner.
- Every opening is published on whole pixels (`SurfaceContext.opening`, ceil start, floor end): the pill's (`EdgePlacement`'s stretch and submenu openings, a pill bar's `PillBarJoin`, `CornerMerge`) and the border's (`BarContainer.borderOpening`/`joinOpening`) as `StrokeOpening`'s, so the thresholded mask cuts no pixel the wall covers less than half, and one is re-sent once per pixel, not every frame.
- A submenu's popup takes no compositor adjustment: its window reaches past the parent's, and a nudge left its blur and the parent's opening behind.

### Where a window is (LayerOrigin)
- Layer windows don't know where they are, so axiom works it out on every compositor ([layer arrangement](../compositor/layer-arrangement.md)):
  - each `hosts/window/LayerOrigin` states its window's anchors, margins, size, zone and when it mapped to `LayerManager`;
  - `LayerManager` places them all with `methods/layer/LayerArrange`, and each `LayerOrigin` reads its own window's rect back (`LayerManager.rectOf(owner)`).
- A window that reserves nothing has its origin before it maps, where it will go, so it's backed from its first frame. A reserving window has one only while mapped.
- On Hyprland the result is corrected from its layer list (`CompositorManager.withLayerRects`), so other apps' layers and reserved space count too; a difference is logged as `LayerManager: corrected from the compositor` (`scripts/log.sh --debug -g LayerManager`).
- Until its origin is known, a surface fills itself. Two watchdogs say so when it goes wrong (`console.warn`, once): a `LayerOrigin` whose window drew its first frame with no origin while backed, and a backing window that has shapes but isn't shown a second after they came.
- A bar popout's and submenu's place follows from their bar's.

### Joins: openings in the border's stroke
- A surface joined to the border's stroke (`EdgePopout`) publishes the stretch it covers:
  - `SurfaceManager.setBorderOpening`, through a `hosts/popout/BorderOpening`, which takes it back as it goes;
  - in screen px along the edge; its edge coordinates start at `ScreenEdgeManager.reservedWithMenusOn(startSide)`;
  - on whole pixels (see Strokes left open under backed surfaces).
- The backing window's copy of the frame cuts the stroke there (`BorderPanel.screenStrokePieces`, the corner windows' `covered`); `BorderPanel` itself draws its stroke and its row whole.
- The same goes for strokes a surface is joined over. An opening is cut in every mode, opaque too (the backing window's copies cut the stroke), so no fill shows a line through it.
- Pills publish theirs too (`BarContainer.borderOpening`, from the bar's place on screen).

### Joins on a perpendicular edge
- Any surface joined to a perpendicular edge opens that edge's stroke down to its join's fillet (`EdgeAttach.joinOpening`, `AttachedSurface.joinShown`: as much as is out past its edge), and `RoundedBorders`' `strokeHoles` take the corner piece's box there (`FrameOutline.cornerCovered`).
  - Such surfaces: a pill, a bar popout, an edge popout or dock running the whole edge (on a pill bar's edge too).
- Bar popouts merged into the bar, or on a solid bar's inner edge, do the same.

### Border off: the solid bar's inner stroke
- With the border off, a solid bar draws its own inner stroke as the one rect (the openings in its `BarContainer.setRequest`s are cut by the backing window's copies, no host cutter).
- Bar popouts set their openings directly.
- Edge popouts and docks (and bar popouts' joined ends) route the same screen-px spans through `hosts/popout/StrokeOpening`:
  - the stretch they stand on, a joined submenu's, and their joined ends' with their fillet;
  - it puts them on that bar's container (a `PillStretch`), on whole pixels (as every opening, above).

### Submenu joins
- A submenu joined to its parent's bar side reports the stretch its end covers (`SubPopout.joinSpan` → `submenuJoinSpan`).
- It's opened in the pill (a second `PillStretch`) or the border.
- The parent's fillet on that side is opened under it (`AttachedSurface.attachFilletHole`).

### Timing
- Every window drawing an opening (the bar, a popout under its submenu's hole) bursts a `FrameNudge` when it changes, since the change comes from another window sliding.
- A tiled (hollow) menu publishes no opening (`EdgePlacement._hollow`, `PillBarJoin.hollow`): the line runs on under its tiles, in every mode. A joined submenu of it publishes its own.
- A fillet's part of an opening leads the slide by a stroke's width (`AttachedSurface._filletHidden`), as the window drawing it commits a frame or so later.
