# Submenus (one level deep)

> **Files:** `qml/components/hosts/popout/SubPopout.qml`, `qml/components/hosts/popout/SubmenuHost.qml`, `qml/components/hosts/popout/SubmenuSide.qml`, `qml/components/hosts/popout/BarPopouts.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/popout/AttachedSurface.qml`, `qml/components/content/Submenu/MenuSubmenu.qml`, `qml/components/content/SystemTray/SystemTray.qml`
> **Config:** none
> **Related:** [Hosts and switching](hosts-and-switching.md), [Edge attach](edge-attach.md), [Surface context](surface-context.md), [Registry](registry.md), [Menu submenus](../menus/editing-submenus.md)

Every popout host can open one submenu beside its box. This doc covers how the submenu is placed, how it joins the parent's side, and what it hands back to the parent to draw.

### The submenu host
- **One per popout host:** every popout host owns one `hosts/popout/SubPopout` (`submenu`).
- **Opening one:** a `PopoutAnchor` in the host's content opens content in the submenu (`content/<name>/<name>.qml`, chosen by the payload's `name`).
  - Examples of such anchors: the tray's entries, an edge menu's modules.
  - The content is given `wrapper` and the payload's fields.
  - It opens beside the parent's box, level with what opened it.
- **Inside a submenu:** an anchor there replaces the submenu in place.
- **The parent's `SubmenuHost`** (the submenu's `slot`):
  - **What it exposes:** what the submenu attaches to, namely `attachBox`, the side's free and join ends, and `popupScreenOrigin`/`Placed`.
  - **What it takes back from the submenu:**
    - `submenuHole` and `submenuBox`, which the parent's `EdgeSurface` reads.
    - `submenuJoinSpan`, which the parent's `EdgePlacement` reads as `joinSpan`, together with `wall` and `hidden`, in its own coordinates.
    - Its `FrameNudge`, in the parent's `window`, redraws the hole as the submenu slides.
  - **What it asks back for:** `parentStretch`, drawn as `shownStretchTop`/`Bottom`.
  - **What it hands the submenu:** `join` (how it meets the stroke at the bar side, `EdgePlacement.submenuJoin`) and `contextReady`.
- **Edge popouts:** an edge popout's box doesn't join or stretch for a submenu.
- **Same parent side for both parent kinds:** `BarPopouts` and `EdgePopout` each hold one `SubmenuHost`, and both expose:
  - `attachBox`
  - `side`: a `hosts/popout/SubmenuSide`, which has:
    - `joinTop`/`joinBottom`, `freeTop`/`freeBottom`
    - `growsUp`, and squared corners
    - `parentStretch`, drawn as `shownStretchTop`/`Bottom` with the corners it squares
    - `flushStart`/`EndThrough`
- **Reaching the pill:** a joined submenu's outer wall (`SubmenuHost.wall`, at rest) decides how it meets the pill or island through `SurfaceContext.submenuJoin`, in `EdgePlacement.submenuJoin`. Its stretch goes on the bar under its own owner (`EdgePlacement._submenuStretch`), following the submenu along its slide.

### Lifetime
- **In PopoutManager:** the submenu is registered as its parent's.
- **Closing with the parent:** it closes with the parent. It also closes when the parent switches content, or gives way to a popout over it. These closes, and the tray menu's on hovering an item with no submenu, go through `hide()` (`SubPopout.hide`), so a submenu queued while it was closing doesn't open after.
- **Keeping the parent up:** it keeps the parent open while it's open (`PopoutWrapperBase.childOpen`, from its `submenuHost`).
- **Closing with the pointer off the parent:** this takes the parent with it (`ownHovered`).
- **Inside its parent's focus grab:** an edge popout's grab (a floating edge menu closing on an outside click) takes the submenu's window too (`SubPopout.popupWindow`), so a click in the submenu isn't outside. The overlay's grab lets it through as a grab partner (`SurfaceManager.registerGrabPartner`).
- **Its context first:** a submenu longer than the parent's side stretches the parent's box past its end (`parentStretch`). That stretch grows out first (`SubmenuHost`'s progress, animFast), and the submenu slides out only once it has (`SubmenuHost.contextReady`, read by its surface's `active`). Closing mirrors it: the submenu slides away, then the box draws back. A stretch changing while it's out (gliding to a sibling's submenu) glides there. See [Choreography](edge-attach.md#choreography).
- **Its pill reach follows it:** the pill or island stretched along under a joined submenu runs out with its outer wall as it slides (`SubmenuHost.hidden`), and back with it.
- **Tray cascade:** a submenu that closes with the pointer off both the tray menu and its icon (the pointer left, or an entry was picked) closes the menu at once (`content/SystemTray`). This is a cascade, not the menu's own dismiss delay after it.

### Position
- **Opening level with its anchor:** the anchor is measured inside the parent's box (the slot's `anchorOffsetOf(item)`, through `AttachedSurface.contentBox`). So one opened while the parent still slides out lands where the parent comes to rest.
- **Vertical limits:** it stays within the screen's room up and down, inside what's reserved at its top and bottom (`SubPopout.screenFrom`/`screenTo`).
- **Taller content:** content that may be taller (`Submenu/MenuSubmenu`, a tray submenu: `parts/TraySubmenu` through `TrayMenuList.maxHeight`) scrolls past `maxContentHeight`.
- **Where the stretch goes:**
  - **On a top or bottom edge** the stretch is across the box, so the window keeps that room from the start. A window growing while it shows is drawn for a frame with its old contents squeezed into the new size.
    - A horizontal bar's popout window takes the screen's whole depth (`BarPopouts.wholeDepth`).
    - An edge popout with `roomForSubmenus` (a floating menu holding a `Submenu` module) takes the screen's depth across its edge.
  - **On a side edge** it stretches along the edge, inside the window (`EdgePlacement`'s `aligned`/`contentLength`).

### Switching in place
- **Gliding between submenus:** another submenu of the same popout, whether a sibling item's or one drilled into, glides level with its item and resizes. Bar popouts do the same; see [Hosts and switching](hosts-and-switching.md#switching-in-place).
- **The popup:** it spans everywhere a submenu of that menu can sit (and keeps the largest size since it opened), masked to the surface.

### Placement along the parent's side
- **Placed like a bar popout along a pill:** `SurfaceContext.submenuPlace` (tested in `tst_SurfaceContext`): `EdgeAttach.place` in pill mode, with the parent's box at rest and the slot's `attachBox` as the pill. It also holds the reach rules below: a fillet and the parent's corner kept clear of a cornered end, the reach to a free or joined end, the screen's limits, and hanging past the top when `growsUp`.
  - Its first item stays level with the hovered one, moved only to stay within reach or nudged (`place`'s `nudge`; see [Edge attach](edge-attach.md#nudge-submenus)).
- **No room for its fillet:** the side runs flush to a free end of the parent's side.
  - `side.freeTop`/`freeBottom` are its far edge's ends, plus its bar side too on a detached box.
  - The parent squares its corner there, and a detached box's near corner too (`AttachedSurface.startNearRadius`/`endNearRadius`).
- **At the bar side** of a solid bar's box, a pill's, an island's or a merged box, it joins the stroke the parent grows from instead.
  - The join is `side.joinTop`/`joinBottom` at `side.attachLine`, through `AttachedSurface.joinStart`/`joinEnd`. On a bare screen edge it runs straight.
  - This works the way a popout joins the perpendicular border.
  - Its window keeps no shadow room past that line.
- **Longer than the side:** the submenu stretches the parent's box past its far end.

### What the submenu hands back
- **`SubPopout.parentStretch`** is `{ top, bottom, squareTop, squareBottom, joined, wall }` (`wall`: its outer wall at rest, x in the parent's window, while joined at the bar side).
  - `BarPopouts` draws it: `shownStretchTop`/`Bottom`, the corner flags, and the window keeping room for it as it does for its box.
- **Meeting a pill, the way a bar popout does** (`SurfaceContext.submenuJoin`, tested in `tst_SurfaceContext`; read back as `SubPopout.joinFillets`):
  - **Something shows past its wall:** the parent's own pill or island, or a neighbour starting within the fillet, its corner and `joinGap` of the wall: the rule a pill bar's joined end follows (`EdgeAttach.pillJoinFilleted`). Its outer fillet then curves into the stroke, and the parent's pill is carried on past the fillet and its corner (merging into that neighbour), as a bar popout's `pillGrows` does. A wall running straight into a pill that carried on past it met it at a bare right angle.
  - **Otherwise** its wall runs straight up (`straightJoins`) into the pill or island, which is stretched to the wall and squared there.
  - Short of room to grow (past where islands may reach, or the strokes at the edge's ends), it runs straight, at that limit.
  - Off a pill (the border's or a solid bar's stroke), it fillets where that stroke runs on past its fillet and corner.
- **Its straight wall runs through the backfill row:** a straight joined end's far wall carries on through the row it covers past that end (`SurfaceOutline` `joinThroughStart`/`End`, drawn beside that row's fill in `AttachedSurface`), into the squared pill. Stopped at the box, it left a pixel of the wall open where the two met.
- **The parent's own wall:** while a submenu is joined, the parent's wall on that side, if it ran flush into the pill's end, stops at the attach edge instead of running on through the backfill (`AttachedSurface.flushStartThrough`/`flushEndThrough`). The stroke it continued now carries on under the submenu.
- **Covering the backfill row:** on a pill or island the submenu also covers the parent's backfill row beside it (`AttachedSurface.joinBackfill`, `side.backfill`).
  - That row is plain fill past its joined end, outside its shadowed outline, and its window keeps that row.
  - Without this, the parent's glow showed there as a dash.
- **Shadow:**
  - A submenu casts its parent's shadow look (`host.popupSurface`).
  - Unbacked, a parent's own shadow leaves out its submenu's box (`AttachedSurface.shadowHoles`, from `SubPopout`'s `submenuBox`).
  - See [Shadows](shadows.md).
