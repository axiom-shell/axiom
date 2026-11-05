# Surfaces held off an edge

> **Files:** `qml/components/hosts/popout/EdgePlacement.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/popout/ClosedLatch.qml`, `qml/components/methods/SurfaceContext.qml`, `qml/services/ui/ScreenEdgeManager.qml`
> **Config:** `detached` and `gap` on floating edge menus (`EdgeMenus.items[]`), docks (`Dock.items[]`) and OSDs (`OSD.items[]`)
> **Related:** [Edge attach](edge-attach.md), [Surface context](surface-context.md), [Pill and floating bars](pill-and-floating-bars.md), [Dock](../features/dock.md), [OSD](../features/osd.md), [Edge menu hosts](../edge-menus/hosts.md)

Floating edge menus, docks and OSDs with `detached` set are held off their edge as islands. Edge popouts are also held over a fullscreen window. A new surface held off an edge uses these rules rather than distances of its own.

### The island and its gaps
- **Shape:** the surface is an island, `gap` in from the frame line on its own edge and on both perpendicular edges.
- **The frame line:** `ScreenEdgeManager.frameLine`, plus integrated menus' zones (`ScreenEdgeManager.frameLineOn`). Depending on what is there, it is:
  - the inner side of the border's stroke;
  - a solid bar's inner stroke;
  - a floating bar's islands;
  - a pill bar's far side;
  - a transparent bar's inner edge.
- **`ScreenEdgeManager.detachedGaps(screen, location, gap)`** gives the three gaps:
  - `gap` on each side, or
  - Auto (-1):
    - When a floating bar shares the edge, its `floatingGap` is used across, so the surface lines up with its islands; at both ends it lines up with the windows, as the islands' ends do.
    - Otherwise, per side, how far past the frame line windows start (`ScreenEdgeManager.barReservedOn` + gaps_out), so it lines up with the windows.
- **Placement origin:** each surface places itself from where its window starts (`ScreenEdgeManager.reservedWithMenusOn`).

### EdgePlacement given `held` and `gap`
`EdgePlacement` does the work, given `held` and `gap` (from the OSD, floating edge menus or docks). It provides:
- **`gaps`.**
- **`insetStart`/`insetEnd`:** the room a box keeps at an unjoined end.
  - When held, these are its gaps.
  - Otherwise they are `SurfaceContext.endRoom`: its fillet's room past the corner into the perpendicular edge. Without that room, the fillet's run along the stroke would draw a straight stub beside the corner's arc.
- **`attachAt`:** where its window's attach edge goes. When held, this is a connector gap short of its box.
- **`detached`.**

`maxBoxLength` and the clamp in `boxStart` use the insets.

### EdgePopout extras
- **`edgeOffset`.**
- **`slideDistance`:** a detached box (held, over a fullscreen window, or past a bar it doesn't grow out of) slides in from off the screen, as a bar popout's does: from the screen edge (`EdgePlacement.slideFrom`), when `EdgePlacement.slidesFromEdge` (see [Sliding in from off the screen](#sliding-in-from-off-the-screen)).
  - Whether it does, and whether its window goes under the bars (`slidesUnder`), follow only while the popout is closed (`_fromEdge`, `_under`, `ClosedLatch`es, as `BarPopouts.underBar`), so an open popout keeps its layer, namespace and window when the overlay opens, a fullscreen window appears, or its edge's bar changes or goes away.
  - Sliding from the screen edge, its window takes input on the box alone.
- **Over a fullscreen window** (`CompositorManager.hasFullscreen`), which covers the border and bars, any `EdgePopout` (OSD, floating edge menu, attached launcher, attached switcher) is held too (`holds`: `held` or `_overFullscreen`), and placed as if the screen's edges were bare (`bare`, `EdgePlacement.bare`):
  - It uses an Auto gap, unless it is already held. Bare, Auto is the gap windows keep from a bare edge (`ScreenEdgeManager.floatGaps`: gaps_out, else the screen margin), and the gaps are measured from the screen's edges (`detachedGaps`/`heldInset` with `bare`).
  - Its window ignores every zone (`ExclusionMode.Ignore`, as the toasts' area), so it spans the screen; a floating edge menu's modules are laid out from the screen's edges too.
  - It joins no ends, goes under nothing (no Top window maps over a fullscreen one), and slides in from off the screen on every compositor.
  - Like `_under`, `_overFullscreen` follows only while the popout is closed (`ClosedLatch`), so an open box never moves.

### Sliding in from off the screen
Every detached box slides in from off the screen, from `SurfaceContext.layout`:
- **`slidesUnder`:** under what's on its edge (the bars, the border, an integrated menu's strip), its window on the bars' layer as `axiom-popout-under`, ordered under them by its layer rule ([layer stacking](../generated/layers.md)). Only with `supports.layerOrder` (Hyprland), not while the overlay is open on its screen (that layer is under it), and not over a fullscreen window.
- **`slidesFromEdge`:** always, for every detached box: under the bars as above, or else over them, its window on the Overlay layer (sway and niri stack by map order, so a window mapped as it opens lands over the bars; and over the overlay), so the slide is the same on every compositor but for what it passes under.
- **`slideFrom`:** the distance from its attach edge back to the screen edge (its `attachAt`), which the surface reaches back over (`AttachedSurface.detachedOffset`), so the slide starts with the box wholly off the screen.
- The bar popouts' detached boxes (a transparent bar's, a floating bar's showing no islands) slide the same way ([Transparent bars](pill-and-floating-bars.md#transparent-bars-detached-popouts)). The dock and toasts don't yet: see [issues](../issues.md#a-detached-dock-and-toasts-dont-slide-in-from-under-the-bars).

### The dock
- **Placement:** the dock is not an `EdgePopout`, but it takes the same values from its own `EdgePlacement`.
- **Exclusive zone:** when held and reserving its space, its exclusive zone ends at its box.
- **Effect on windows:** they keep the gaps_out Hyprland adds past any zone, just as they do from a screen edge.
