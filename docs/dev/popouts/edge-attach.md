# Edge attach: placement along an edge

> **Files:** `components/methods/EdgeAttach.qml`, `tests/tst_EdgeAttach.qml`, `components/hosts/popout/EdgePlacement.qml`, `components/hosts/popout/PillStretch.qml`, `components/bar/BarContainer.qml`, `components/methods/BarLayout.qml`, `components/hosts/popout/BarPopouts.qml`
> **Config:** none directly
> **Related:** [Surface context](surface-context.md), [Pill and floating bars](pill-and-floating-bars.md), [Held off an edge](held-off-edge.md), [Submenus](submenus.md), [Bar layering and corners](../bar/layering-and-corners.md)

`components/methods/EdgeAttach` (pure, tested by `tests/tst_EdgeAttach.qml`) decides where a box goes along its edge, and how it meets what's there. It is shared by bar popouts, every `EdgePopout` (OSDs, floating edge menus, the attached launcher) and docks.

### joins and place
- **`joins`:** an end joins a joinable perpendicular stroke when the box would either be pushed back from that stroke or come within a connector gap of it.
  - Every surface does this unless it is held off its edge. OSDs and the launcher are included.
- **`place`:** returns the mode, which is one of:
  - `plain`
  - out of a `pill` or out of an `island`. These follow the same rules: a pill bar's pills are met the way islands are; see [Floating bars](pill-and-floating-bars.md#floating-bars-islands).
  - `merged`: grown from the outer edge of a pill bar that is showing no pills.
  - `between`: with `between` set (`SurfaceContext.layout` sets it; submenus don't), a box centred between a pill bar's pills or a floating bar's islands grows from the bar's outer edge, over the bar, when it keeps more than `pillMerge` and two fillets' room from every pill. Closer than that, it grows out of the nearest pill as before.

  Alongside the mode it returns:
  - the box's `start`/`end`
  - the content's `contentStart`/`contentOffset`
  - joined and flush ends, and fillet margins
  - the surface's span
  - the pill or island `stretch`

### The content sits where it wants to
- **Content stays put:** the content sits at its anchor or its `position`. It moves only to stay on the screen or on its island.
- **The box grows instead:** to reach a joined stroke, an island's end, or a pill stroke it would just miss, the box grows around the content. The content does not move to make the box fit.
- **Hosts:** they place their content at `contentOffset`, rather than centring or stretching it.
- **A side ending just short of the pill's end:**
  - **The case:** out of a pill or island, a side may end too close to the pill's end for a fillet. It would then run flush to the pill with empty space beside it.
  - **With `pillGrows`:** the side keeps its fillet instead. `pillGrows` is set for bar popouts and for `EdgePlacement` (edge popouts and docks).
    - The pill or island grows past its end far enough to carry the fillet (`stretch`).
    - The box stays its content's size.
  - **Where the pill can't grow:** the side runs flush as before. There are two such cases:
    - a pill that joins the perpendicular edge, which the box then joins too;
    - past where islands may reach (`islandFrom`/`islandTo`).
  - **With no radius:** a fillet and corner then take no room, so a side reaching the pill's end exactly runs flush into it, whether or not the pill can grow. Its wall continues the pill's edge. Standing on the pill's corner instead, its backfill cut the end of that edge's stroke away: a notch where a submenu met its parent's square corner.
- **With `pillJoins` (`EdgePlacement`):** a box on a pill bar that `joins` a perpendicular edge joins it from whichever pill it grows out of. Examples are a floating edge menu or a dock running the whole edge.
  - That pill's stretch reaches to the bar's end (`pillFrom`/`pillTo`) and carries `joinStart`/`joinEnd`.
  - So the pill joins the edge too once it gets there (`BarLayout.shownStretches`), rather than ending in a squared cap across the bar.
- **Merging stretched pills:** `BarLayout.stretchIslands` merges them in order of where they start, because a stretch may reach back over the pills before its own.

### Walls
- **Which ends are walls:** an end with nothing to join.
  - Examples: another bar on the perpendicular edge that is transparent or floating, or an integrated menu's strip.
  - A pill bar is joined, not walled; see [Bar popouts on pill bars](pill-and-floating-bars.md#bar-popouts-and-pill-bars).
  - This is `SurfaceContext.end`'s `wall`.
- **Where the box sits:** a box at a wall (a bar popout's, an edge popout's or a dock's) sits in line with the windows there.
  - **That line** is `SurfaceContext.wallLine`: the further of that edge's frame line and its reserved space plus gaps_out, with the border on or off.
  - **Its fillet** curves past that line, beside the stroke it stands on.
- **How far in:** the box is pushed in only as far as that fillet needs to clear the frame's rounded inner corner.
  - The amount is `SurfaceContext.wallAt`, from `ScreenEdgeManager.cornerLine`.
  - The corner line is the frame's inner edge, which a floating or transparent bar sits inside.
- **`wallFrom`/`wallTo`** (in `EdgeAttach`): where the whole surface, its fillet included, stops. It never joins that edge.
- **Fillet over reserved space:** where the fillet starts short of where windows start (over a transparent bar's reserved space), `frame` widens the end's `strokeInset`.
  - So an edge popout's or dock's window reaches back far enough to hold the fillet, rather than clipping its arc.
- **On a pill or island:** the content also keeps a full fillet, and the pill's or island's full corner, inside what the pill may reach.
  - A pill bar's own window ends there (`pillReachStart`/`pillReachEnd`).
  - So a side never runs flush past the wall.
- **Short of room:** when room runs out (a floating bar owning the corner, its island reaching over the bar it pushes aside), the box moves in. No radius shrinks: fillets and corners are always whole.
- **Floating bar held clear:** a floating bar held clear of the other bar takes no wall at that end. Its islands, and so its popouts, already keep to the windows there.

### Nudge (submenus)
- **Why submenus differ:** their "pill" is the parent's box, so `SubPopout` calls `place` with `nudge` set, rather than letting the box grow.
- **How `nudge` works:** the content moves whichever way is shorter without growing anything. It goes either up to that end, or back far enough for the fillet.
- **How far:** either move is less than a fillet's room.

### Pill stretch
- **Handing the stretch to the bar:** a surface standing on or joining a bar does this through `hosts/popout/PillStretch`.
  - It is owner-keyed: `BarContainer.setRequest(owner, { stretch, opening, endReach })`. Any number can be active at once.
  - The bar keeps each part in a map of its own, so a stretch changing never re-runs what reads the end reaches (`pillRects`).
  - Stretches are combined per pill by `BarLayout.stretchOf`, and shown by `BarLayout.shownStretches`.
  - A stretch carries the pill it stands on at rest (`pill`) and its surface's box (`box`). The bar finds the pill by that span when its index has gone stale (`BarLayout.pillIndex`: an end reach's stub came or went before the stretch was sent again), and the box bounds how far a squared end's shadow runs on under the surface (`BarLayout.flushEnds`).
- **The owner sets the pace; the bar draws what it's sent, as sent.** The bar animates none of it, so a surface and the pill it stands on can't drift apart.
  - A `PillStretch` animates its own `progress` (animFast) and sends its stretch that far out from the pill's own span (`EdgeAttach.progressStretch`).
  - A stretch changing while it's out (a switch in place, a resize) glides there.
  - With `tracks`, the stretch follows its surface along a slide by itself and is sent as given.
  - Pushes go at the end of the pass (`Qt.callLater`): what one sends reshapes the pills it reads.
  - The pills' position follows the layout at once.

### Choreography
How the context a surface needs (a pill to stand on, a pill reaching along a joined end) moves with the surface itself. Decisions (whether an end fillets, which pill it lands on) are made from where things rest, never from what's drawn.
- **Context across the slide grows first, then the surface slides.** Closing mirrors it: the box slides away, then the context draws back.
  - **Own pill or island widening** for a bar popout, edge popout or dock: the surface slides out only once `PillStretch.ready` (its `progress` has reached 1).
    - The host sets `open`, and readiness is judged a turn of the event loop later, because a host's stretch comes in with its content.
    - Once ready it holds while the surface stays open, so a switch in place or a resize never pulls the box back.
    - Who waits: bar popouts, on `surface.active`; edge popouts, on `EdgePlacement.stretchReady`; docks, on `shown`. No stretch, no wait.
  - **A parent box stretching past its end** for a submenu longer than its side: see [Submenus › Lifetime](submenus.md#lifetime).
- **Context along the slide follows the surface.** Its tip moves with the surface's drawn far wall, never past where it rests: with it, or a stroke ahead without `supports.layerFrameSync` (niri), where the bar can commit a frame or so after the surface's window (`EdgePlacement._slideLead`). Nothing waits for it.
  - **A perpendicular pill bar's end pill** under a joined end (`PillBarJoin`, from `EdgePlacement._surfaceHidden`). Its far stroke opens only as far as the surface has come.
  - **The pill reach under a submenu** joined at its parent's bar side (`EdgePlacement._submenuReach`, from `SubmenuHost.hidden`).
  - A stub grown at the bar's end for one is never longer than the reach asked (`BarLayout.endReaches`), so it grows from the corner.

### EdgePlacement
- **Every host reaches EdgeAttach through `hosts/popout/EdgePlacement`.** It reports what's on the edge.
- **Its ends, from SurfaceContext:**
  - `startEnd`/`endEnd`, `joinStart`/`joinEnd`
  - `strokeInsetStart`/`End`
  - `lo`/`hi` and `insetStart`/`End`. These come from held gaps, a wall, a floating bar's island reach, or `endRoom` from the frame line.
  - `straightJoinStart`/`End`
- **Placement outputs:** `place`, `detached`, `straight`, `attachAt`/`attachFromBar`, `backfill`, `slidesUnder` (from `SurfaceContext.layout`: a detached box past a transparent bar with `supports.layerOrder`, the overlay not open over it, given as `overOverlay` and latched by the host).
- **Look outputs:** `shadow`/`shadowLook`, `backed`/`opaque`, its openings and its `PillStretch`es.
- **Following the bar:** it follows its bar unless held (`followsBar`), on pills and islands alike.
  - Past a transparent bar, a detached box goes past it (`BarsConfig.detachedPush`).
- How EdgePlacement gathers its inputs is in [Surface context](surface-context.md#edgeplacement-the-only-input-gatherer).
