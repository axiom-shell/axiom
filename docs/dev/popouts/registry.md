# Popout registry and collisions

> **Files:** `services/ui/PopoutManager.qml`, `components/hosts/popout/PopoutClaim.qml`, `components/methods/PopoutGeometry.qml`, `tests/tst_PopoutGeometry.qml`, `components/methods/SurfaceOutline.qml`, `components/hosts/popout/LayerOrigin.qml`, `components/bar/BarPanel.qml`
> **Config:** none
> **Related:** [Surface context](surface-context.md), [Hosts and switching](hosts-and-switching.md), [Submenus](submenus.md), [Edge menu hosts](../edge-menus/hosts.md)

`services/ui/PopoutManager` knows every popout that is showing, and where. A popout opening closes only what it overlaps, decided by rank. Read this before adding a popout kind or changing which one wins. (Rule: AGENTS.md › UI conventions, "Popout collisions".)

### Claims
- **Who holds a claim:** every bar popout, edge popout (OSDs, floating edge menus, the attached launcher), floating popout (the detached launcher, the window switcher), dock and submenu holds a `hosts/popout/PopoutClaim`.
- **`key` values:**
  - `bar:<id>`
  - `osd:<id>:<screen>`
  - `menu:<id>`
  - `launcher:<screen>` (attached or detached)
  - `switcher:<screen>` (the window switcher, ranked `launcher`)
  - `dock:<id>:<screen>`
  - `<parent>/submenu`
- **Other fields:** `kind`, `screen`, `edge`, `pinned`, `resident`, `parentKey`.
- **When it registers:** while the popout `wants` to show and has a footprint. An edge or floating popout waits until its window has an origin (`LayerOrigin.settled`, from `LayerManager`, or given up on after 400 ms): the estimate before that can be far off (a floating menu's was ~1700 px out), and a claim made from it missed what it covered.
- **Footprint:** the rects it covers, in screen px, with fillets and backfill included (`methods/SurfaceOutline.footprint`). It is offset by where its window is:
  - `LayerOrigin.placed`: its origin, or until it has one, an estimate on its edge.
  - A bar popout uses its bar's origin (`BarPanel.screenPlaced`).
- **Location report:** `entries`, visible with `qs ipc call popouts list`.

### Ranks
The rules are pure: `methods/PopoutGeometry`, tested by `tests/tst_PopoutGeometry.qml`. Ranks, lowest first:
1. `pinned`: any pinned popout, of any kind, while it isn't `engaged`.
2. `dock`
3. `osd`
4. `bar`
5. `menu`
6. `launcher`

A submenu ranks as its parent. A floating menu opened as a bar widget's popout (by its `PopoutAnchor`, on hover; a `Button`'s too, through its `popout.menu`) ranks `bar`: a neighbour's popout replaces it, as bar popouts replace each other. Opened by a click (a `Button`'s click action), a keybind or its edge it ranks `menu`.

**Engaged.** An `EdgePopout` is engaged in these cases:
- **Opening:** from the moment it starts opening.
- **Asked for again while open:** via `EdgeMenuManager.engageRequested`. A keybind or bar Button that toggles a covered menu brings it forward rather than closing it.
- **Grace period:** it stays engaged until a grace period passes without the pointer reaching it.
- **Hovered:** while the pointer is on it, on its hover strip, or on what opened it.

While engaged it ranks as its kind, so it opens over a dock. Once let go it drops back to `pinned` and gives way again.

### Resolving
- **`resolve`:** a claim closes only what its footprint overlaps.
  - **Lower and equal ranks** close; the newer one wins.
  - **A higher rank refuses it** (`refused`): it doesn't open. A refused OSD's poke is dropped.
  - **Exempt pairs:** a popout's own submenu, or its parent, never collides with it.
- **Residents** (docks, pinned menus, a menu previewing from its editor) give way instead of closing:
  - `yielded`: hidden, with its pill drawn back.
  - **Coming back:** once nothing above them covers them they return (`resumable`, highest first).
  - **No ping-pong:** one coming back never evicts another of its rank, so two never take turns.
  - **Unpinned while away:** it closes.
- **Showing only once granted:** a host shows only once granted (`PopoutClaim.held`: granted, or closing after it was). The pill it stands on therefore draws back only after its box has slid away.
- **Same-frame handover:** the evicted popouts start closing in the same frame the new one starts opening.
- **Footprint changes:** if a claim's footprint changes while it shows (a resize, a switch in place, its window's real place arriving), it re-resolves as a claim does: it closes anything below it that it now covers, and gives way itself (refused, or yielded if resident) to anything above it. A popout never stays open over a higher one.

### An open popout never moves
- A bar popout keeps the anchor rect it opened at; a widget moving or growing meanwhile doesn't drag it.
- It opens where it belongs the next time.
