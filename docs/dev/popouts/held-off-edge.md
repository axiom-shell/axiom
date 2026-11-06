# Surfaces held off an edge

> **Files:** `qml/components/hosts/popout/EdgePlacement.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/popout/ClosedLatch.qml`, `qml/components/methods/SurfaceContext.qml`, `qml/services/ui/ScreenEdgeManager.qml`
> **Config:** `detached`, `distance` and `animation` on floating edge menus (`EdgeMenus.items[]`), docks (`Dock.items[]`), OSDs (`OSD.items[]`), the launcher (`Launcher`) and the window switcher (`WindowSwitcher`)
> **Related:** [Edge attach](edge-attach.md), [Surface context](surface-context.md), [Pill and floating bars](pill-and-floating-bars.md), [Dock](../features/dock.md), [OSD](../features/osd.md), [Edge menu hosts](../edge-menus/hosts.md)

Floating edge menus, docks, OSDs, the launcher and the window switcher with `detached` set are held off their edge as islands, all placed and drawn the same way (the launcher and switcher are `EdgePopout`s as the OSD is; the dock takes the same `EdgePlacement`). Edge popouts are also held over a fullscreen window. A new surface held off an edge uses these rules rather than distances of its own.

### The island and its gaps
- **Shape:** the surface is an island, its automatic gap in from the frame line on both perpendicular edges, and on its own edge that gap plus `distance` (0–50%) of the free screen across: 0 lines it up with the window border, 50 centres it.
- **The frame line:** `ScreenEdgeManager.frameLine`, plus integrated menus' zones (`ScreenEdgeManager.frameLineOn`). Depending on what is there, it is:
  - the inner side of the border's stroke;
  - a solid bar's inner stroke;
  - a floating bar's islands;
  - a pill bar's far side;
  - a transparent bar's inner edge.
- **`ScreenEdgeManager.heldGaps(screen, location, distance, depth, bare)`** gives the three gaps: the automatic ones (`detachedGaps` with a null gap), the one across pushed in by `distance` of the room between the automatic gaps on its edge and the opposite one, less the box's `depth` (`EdgePlacement.heldDepth`: an `EdgePopout`'s content at its deepest, `maxContentDepth`, so a growing launcher doesn't move; the dock's thickness).
- **`ScreenEdgeManager.detachedGaps(screen, location, gap, bare)`** gives the automatic gaps (the toasts still take a px `gap` there; `bare`, over a fullscreen window: from the screen's edges):
  - `gap` on each side, or
  - Auto (null):
    - When a floating bar shares the edge, its `floatingGap` is used across, so the surface lines up with its islands; at both ends it lines up with the windows, as the islands' ends do.
    - Otherwise, per side, how far past the frame line windows start (`ScreenEdgeManager.barReservedOn` + gaps_out), so it lines up with the windows.
- **Placement origin:** each surface places itself from where its window starts (`ScreenEdgeManager.reservedWithMenusOn`).

### EdgePlacement given `held` and `distance`
`EdgePlacement` does the work, given `held`, `distance` and `heldDepth` (from the OSD, floating edge menus, docks, the launcher or the window switcher). It provides:
- **`gaps`.**
- **`insetStart`/`insetEnd`:** the room a box keeps at an unjoined end.
  - When held, these are its gaps.
  - Otherwise they are `SurfaceContext.endRoom`: its fillet's room past the corner into the perpendicular edge. Without that room, the fillet's run along the stroke would draw a straight stub beside the corner's arc.
- **`attachAt`:** where its window's attach edge goes. When held, this is a connector gap short of its box.
- **`detached`.**

`maxBoxLength` and the clamp in `boxStart` use the insets.

### EdgePopout extras
- **`edgeOffset`.**
- **`slideDistance`:** a detached box (held, over a fullscreen window, or past a bar it doesn't grow out of) slides in from behind its edge, as a bar popout's does: from the screen edge under the bars, else from the frame line (`EdgePlacement.slideFrom`), when `EdgePlacement.slidesFromEdge` (see [Sliding in from off the screen](#sliding-in-from-off-the-screen)).
  - Whether it does, and whether its window goes under the bars (`slidesUnder`), follow only while the popout is closed (`_fromEdge`, `_under`, `ClosedLatch`es, as `BarPopouts.underBar`), so an open popout keeps its layer, namespace and window when the overlay opens or its edge's bar changes or goes away. A fullscreen window coming or going is the exception (see [Over a fullscreen window](#edgepopout-extras)): `_fromEdge` follows as the box jumps, `_under` (the namespace, fixed while mapped) doesn't.
  - `slideFrom` starts where the window really is (`EdgePlacement.under`, the host's window on the Top layer), not where a box opening now would: one opened under the bars with the overlay opened since still slides from the screen edge.
  - Sliding from behind its edge, its window takes input on the box alone.
- **`fade`** (`animation` Fade, a detached box only: `fades`): it neither slides from the screen edge nor goes under the bars: it fades in and out where it sits (`SlideAnimation.fade`, its window on the Overlay layer), and the blur window's copy of its fill fades with it (`AttachedSurfaceCopy`). A detached dock fades its content itself (`DockWindow.fades`, `AttachedSurface.hostOpacity` for its copy).
- **Over a fullscreen window** (`CompositorManager.hasFullscreen`), which covers the border and bars, any `EdgePopout` (OSD, floating edge menu, attached launcher, attached switcher) is held too (`holds`: `held` or `_overFullscreen`), and placed as if the screen's edges were bare (`bare`, `EdgePlacement.bare`):
  - It uses the automatic gaps (`distance` 0), unless it is already held. Bare, Auto is the gap windows keep from a bare edge (`ScreenEdgeManager.floatGaps`: gaps_out, else the screen margin), and the gaps are measured from the screen's edges (`detachedGaps`/`heldInset` with `bare`).
  - Its window ignores every zone (`ExclusionMode.Ignore`, as the toasts' area), so it spans the screen; a floating edge menu's modules are laid out from the screen's edges too.
  - It joins no ends, goes under nothing (no Top window maps over a fullscreen one), and slides in from off the screen on every compositor.
  - **Open as it comes or goes**, the box jumps to where it would open now, with no animation (the one change an open popout moves for): `settled` goes off for a tick (the shape and submenu don't animate) while `_snapping` lets `_overFullscreen` and `_fromEdge` follow (a `Qt.callLater` after the change: the handler can run before the latches' `source` bindings, and would latch the old value), so it drops or regains its joins and fillets and takes its new place at once. Not while it's closing.
  - Its window stays mapped, keeping its namespace (Quickshell reads it only as the window maps), so nothing maps in response to fullscreen. Only its layer changes in place (`windowLayer`, a live `set_layer`): one opened under the bars (Top, `axiom-popout-under`) goes to Overlay over the fullscreen window, which hides Top, and back after, its layer rule's order kept from when it mapped. One opened over the fullscreen window stays on Overlay once it's gone, sliding from the frame line when it closes (`EdgePlacement.under`). The window's margins, exclusion and size change with it, so the compositor may show one frame of the box in its new place in the old window.
  - Otherwise `_overFullscreen` follows only while the popout is closed (`ClosedLatch`).

### Sliding in from off the screen
Every detached box slides in from behind its edge (unless it fades), from `SurfaceContext.layout`:
- **`slidesUnder`:** under what's on its edge (the bars, the border, an integrated menu's strip), its window on the bars' layer as `axiom-popout-under`, ordered under them by its layer rule ([layer stacking](../generated/layers.md)). Only with `supports.layerOrder` (Hyprland), not while the overlay is open on its screen (that layer is under it), and not over a fullscreen window.
- **`slidesFromEdge`:** always, for every detached box: under the bars as above, or else its window on the Overlay layer (sway and niri stack by map order, so a window mapped as it opens lands over the bars; and over the overlay), where it can't pass under them, so it comes out of them instead: from the frame line, cut there, so the first pixel it draws is the one just past the border's or bar's inner stroke.
- **`slideFrom`:** the distance from its attach edge back to where it starts: the screen edge under the bars (its `attachAt`), else the frame line (`attachAt - frameLine`; the screen edge where that is 0: a bare edge, over a fullscreen window). The surface reaches back over it (`AttachedSurface.detachedOffset`) and `SlideAnimation` cuts there, so the slide starts with the box wholly hidden behind it.
- The bar popouts' detached boxes (a transparent bar's, a floating bar's showing no islands) slide the same way ([Transparent bars](pill-and-floating-bars.md#transparent-bars-detached-popouts)). The dock and toasts don't yet: see [issues](../issues.md#a-detached-dock-and-toasts-dont-slide-in-from-under-the-bars).

### The dock
- **Placement:** the dock is not an `EdgePopout`, but it takes the same values from its own `EdgePlacement`.
- **Exclusive zone:** when held and reserving its space, its exclusive zone ends at its box (so a dock held far across reserves up to there).
- **Fading:** with `animation` Fade it fades instead of sliding as it hides and shows.
- **Effect on windows:** they keep the gaps_out Hyprland adds past any zone, just as they do from a screen edge.
