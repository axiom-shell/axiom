# Surfaces held off an edge

> **Files:** `qml/components/hosts/popout/EdgePlacement.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/popout/ClosedLatch.qml`, `qml/components/methods/SurfaceContext.qml`, `qml/services/ui/ScreenEdgeManager.qml`
> **Config:** `detached`, `distance` and `animation` on floating edge menus (`Menus.items[]`, the menus' own `animation`, which adds Scale for free menus), docks (`Dock.items[]`), OSDs (`OSD.items[]`), the launcher (`Launcher`) and the window switcher (`WindowSwitcher`)
> **Related:** [Edge attach](edge-attach.md), [Surface context](surface-context.md), [Pill and floating bars](pill-and-floating-bars.md), [Dock](../features/dock.md), [OSD](../features/osd.md), [Menu hosts](../menus/hosts.md)

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
    - Otherwise, per side, how far past the frame line windows start (`ScreenEdgeManager.barReservedOn` + gaps_out), so it lines up with the windows. Across, past a bar on that edge, `ScreenEdgeManager.windowsPast` (never less than gaps_out less the bar's `trim`): where windows start with the bar reserving its space, whether or not it does, so a held box rests at the same gap from the frame line either way.
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
- **`slideDistance`:** a detached box (held, over a fullscreen window, or past a bar it doesn't grow out of) slides in from off the screen, as a bar popout's does: its window edge on the screen edge (`EdgePlacement.slideFrom`), when `EdgePlacement.slidesFromEdge` (see [Sliding in from off the screen](#sliding-in-from-off-the-screen)).
  - Whether it does follows only while the popout is closed (`_fromEdge`, a `ClosedLatch`), so an open popout keeps its window when the overlay opens or its edge's bar changes or goes away. A fullscreen window coming or going is the exception (see [Over a fullscreen window](#edgepopout-extras)): `_fromEdge` follows as the box jumps.
  - `slideFrom` (`SurfaceContext.slideFrom(layout)`) is `attachAt`: the window's edge lies on the screen edge, so the box rests where it attaches and slides in over the bars and border.
  - A detached box's window takes input on the box alone (`boxArea`), sliding or not: its surface reaches back over the bars, and where the window is over them (niri, sway) the rest of it would take the pointer from a bar widget under it.
  - A tiled edge menu ([Overview](../menus/overview.md) › Tiles) keeps that mask, its gaps included; `hollow` draws no box, and `surfaceItem` / `contentInWindow` tell it where its tiles go.
- **`fade`** (`animation` Fade, a detached box only: `fades`): it doesn't slide in: it fades in and out where it sits (`SlideAnimation.fade`, its window on the Overlay layer), and the backing window's copy of its fill fades with it (`AttachedSurfaceCopy`). A detached dock fades its content itself (`DockWindow.fades`, `AttachedSurface.hostOpacity` for its copy).
- **On a hidden auto-hiding bar's edge:** with no border and no bar in place there (`ScreenEdgeManager.edgeAway`), an attached surface is held (`EdgePlacement.holds`: `held` or `edgeAway`; the host's `held` is its own), a box at the automatic gap as over a fullscreen window but with the other edges as they are. With the border on, everything measures from its stroke instead. A bar popout follows its own bar, which it holds shown, and is never held by it. Held surfaces there (a detached OSD, dock or toasts) jump by the bar's depth as it starts to hide or has slid in (`EdgePopout._jump` on `_away`, the toasts' `_snap`, the dock by binding), as at a fullscreen change.
- **Over a fullscreen window** (`CompositorManager.hasFullscreen`), which covers the border and bars, any `EdgePopout` (OSD, floating edge menu, attached launcher, attached switcher) is held too (`holds`: `held` or `_overFullscreen`), and placed as if the screen's edges were bare (`bare`, `EdgePlacement.bare`):
  - It uses the automatic gaps (`distance` 0), unless it is already held. Bare, Auto is the gap windows keep from a bare edge (`ScreenEdgeManager.floatGaps`: gaps_out, else the screen margin), and the gaps are measured from the screen's edges (`detachedGaps`/`heldInset` with `bare`).
  - Its window ignores every zone (`ExclusionMode.Ignore`, as the toasts' area), so it spans the screen; a floating edge menu's modules are laid out from the screen's edges too.
  - It joins no ends and slides in from off the screen on every compositor.
  - **Open as it comes or goes**, the box jumps to where it would open now, with no animation (the one change an open popout moves for): `settled` goes off for a tick (the shape and submenu don't animate) while `_snapping` lets `_overFullscreen` and `_fromEdge` follow (a `Qt.callLater` after the change: the handler can run before the latches' `source` bindings, and would latch the old value), so it drops or regains its joins and fillets and takes its new place at once. Not while it's closing.
  - Its window stays mapped, keeping its namespace (Quickshell reads it only as the window maps), so nothing maps in response to fullscreen. Its window is on the Overlay layer throughout, so its layer never changes. The window's margins, exclusion and size change with it, so the compositor may show one frame of the box in its new place in the old window.
  - Otherwise `_overFullscreen` follows only while the popout is closed (`ClosedLatch`).

### Sliding in from off the screen
Every detached box slides in from off the screen, over the bars and border on its edge (unless it fades), from `SurfaceContext.layout`:
- **`slidesFromEdge`:** always, for every detached box, on every compositor: its window is on the Overlay layer, over the bars, and its window edge is the screen edge, so the box starts wholly past it.
- **`slideFrom`:** the distance from its attach edge back to the window's edge, the screen edge: `attachAt` (0 for a box that is not detached). A transparent bar's box rests where it would with the bar reserving its space, whether it does or not (`ScreenEdgeManager.windowsPast`, the one home: `EdgePlacement._detachedPush` and the held gap across, `ScreenEdgeManager.detachedGaps`, read it). The surface reaches back to the screen edge (`AttachedSurface.detachedOffset`) and `SlideAnimation` cuts there.
- **Who draws it over the bars:** the part of the box between the screen edge and the bars' inner edge (the frame line) is filled and stroked by the surface itself (`AttachedSurface.ownFillRect`, unblurred); the part past the line by the backing window, blurred as at rest (`BlurShape.fillClip`); the shadow is cast from the whole box. The line stays put as the box moves, so nothing changes hands in time ([translucency and blur](../theming/translucency-blur.md#a-box-sliding-in-over-the-bars)). `SurfaceContext.overBars` decides the line and the two rects (`EdgePlacement.overBars`: null attached, over a fullscreen window or on a bare edge): the frame line, or, if the box's slide path (its resting footprint stretched to the screen edge) touches a shown dock, that dock's inner side. The footprint is the host's `PopoutClaim` (`EdgePlacement.claim`); the docks are read from `PopoutManager.entries`.
- The bar popouts' detached boxes (a transparent bar's, a floating bar's showing no islands) slide the same way ([Transparent bars](pill-and-floating-bars.md#transparent-bars-detached-popouts)). The dock does too (its preview takes the slide only), and so do detached toasts, each card on its own ([Notifications](../features/notifications.md)).

### The dock
- **Placement:** the dock is not an `EdgePopout`, but it takes the same values from its own `EdgePlacement`, and slides in as one does: `slideDistance` (a `ClosedLatch`, closed while nothing of it is out) is `slideFrom`, so its window's edge lies on the screen edge (`edgeMargin`) and its box rests at `attachAt` plus half the connector gap. It takes the split with its `claim` (the rule skips its own entry); the preview is unbacked and slides only.
- **Exclusive zone:** when held and reserving its space, its exclusive zone ends at its box (so a dock held far across reserves up to there).
- **Fading:** with `animation` Fade it fades instead of sliding as it hides and shows.
- **Effect on windows:** they keep the gaps_out Hyprland adds past any zone, just as they do from a screen edge.
