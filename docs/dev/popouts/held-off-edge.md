# Surfaces held off an edge

> **Files:** `components/hosts/popout/EdgePlacement.qml`, `components/hosts/popout/EdgePopout.qml`, `components/hosts/popout/ClosedLatch.qml`, `components/methods/SurfaceContext.qml`, `services/ui/ScreenEdgeManager.qml`
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
    - When a floating bar shares the edge, its `floatGap` is used on all three sides, so the surface lines up with its islands across and at both ends.
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
- **`slideDistance`:** only from under a transparent bar's outer edge, as a bar popout slides.
  - It is none while the overlay is open on its screen (`_overOverlay`), so the popout draws over the overlay.
  - See [Transparent bars](pill-and-floating-bars.md#transparent-bars-detached-popouts).
- **Over a fullscreen window** (`CompositorManager.hasFullscreen`), which covers the border and bars, any `EdgePopout` (OSD, floating edge menu, attached launcher) is held too (`holds`: `held` or `_overFullscreen`):
  - It uses an Auto gap, unless it is already held.
  - It joins no ends and slides under nothing.
  - Like `_overOverlay`, `_overFullscreen` follows only while the popout is closed (`ClosedLatch`), so an open box never moves.

### The dock
- **Placement:** the dock is not an `EdgePopout`, but it takes the same values from its own `EdgePlacement`.
- **Exclusive zone:** when held and reserving its space, its exclusive zone ends at its box.
- **Effect on windows:** they keep the gaps_out Hyprland adds past any zone, just as they do from a screen edge.
