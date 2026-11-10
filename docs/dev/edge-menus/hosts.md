# Edge menu hosts (floating and integrated)

> **Files:** `qml/shell/EdgeMenus.qml`, `qml/components/surfaces/edgemenu/EdgeMenu.qml`, `qml/components/surfaces/edgemenu/EdgeMenuBody.qml`, `qml/components/surfaces/edgemenu/EdgeMenuSync.qml`, `qml/components/surfaces/edgemenu/FloatingEdgeMenu.qml`, `qml/components/surfaces/edgemenu/IntegratedEdgeMenu.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/popout/PopoutWrapperBase.qml`, `qml/services/ui/EdgeMenuManager.qml`, `qml/services/ui/ScreenEdgeManager.qml`
> **Config:** `EdgeMenus.items[].placement` (`edge` | `strip` | `free`), `length`, `offset`, `gridOffset`, `moduleScale`, `pinButton`, `frame`, `detached`, `distance`, `animation`, `background`
> **Related:** [Overview](overview.md), [Free menus](free-menus.md), [Editing and submenus](editing-submenus.md), [Pages and grid](../overlay/pages-and-grid.md), [Edge attach](../popouts/edge-attach.md), [Held off an edge](../popouts/held-off-edge.md), [Pill and floating bars](../popouts/pill-and-floating-bars.md), [Layering and corners](../bar/layering-and-corners.md)

How an edge menu is put on screen: the shared body and sync, the lattice its modules sit on, and the two edge hosts, `FloatingEdgeMenu` (placement `edge`) and `IntegratedEdgeMenu` (placement `strip`). A `free` menu's host, `FreeMenu`, is in [Free menus](free-menus.md).

### Building (`surfaces/edgemenu/`)
- `qml/shell/EdgeMenus` builds one `EdgeMenu` per enabled entry (keyed by id), which `LazyLoader`s the host for its placement (`FreeMenuPlace.hosts`: a popped-out edge menu is in the free host, [Free menus](free-menus.md) › A popped-out edge menu).
- `EdgeMenu` keeps the last live entry, so the hosts read its (schema-defaulted) fields directly.

### The body (`EdgeMenuBody`)
- Every host (`FreeMenu` too) puts `EdgeMenuBody` inside: a `ModuleGrid` on an `OverlayGrid`.
- `fixedUnit` is the card size on its screen (`EdgeMenusConfig.cardUnitOf`):
  - `OverlayConfig.cardUnitOn` of the screen: the card size there (two cards fill its short side, times `Widget.cardSize`%). It's the same whether an overlay is open or not, and the overlay's own Module size (`Overlay.moduleScale`) doesn't reach menus;
  - times the menu's Module size (`EdgeMenusConfig.scaleOf`): its `moduleScale`%, shrunk where its modules' depth across its edge (a free menu's width) would pass its screen less its padding (`GridPlacement.fitModuleScale`), its cards, gaps and zoom together. Along the edge it scrolls or is fitted instead (below).
  - The grid and everything placed by it (the lattice, the menu's size, reserved strips) use that drawn card size, and `EdgeMenusConfig.gapOf` between cards: the layout's gap drawn at the menu's zoom (`GridPlacement.gapOf`), as an overlay page's are (`OverlayGrid.gap`).
- Each module's content is zoomed as on the overlay (`ModuleGrid.zoom` → `OverlaySlot.zoom`, `ExpandedModule.zoom`): laid out at its slot's size over `EdgeMenusConfig.zoomOf` and scaled back to fill it.
  - `zoomOf`: the menu's Module size (`scaleOf`) as a factor (`GridPlacement.zoomOf`, 1 within 2 %).
  - So `moduleScale` scales text with the cards, while the screen only changes how big the cards are. Text size itself is the Interface scale's (`Widget.scale`, through `Appearance.fontSize` and the Widget sizes).
  - Submenus (`MenuSubmenu`) are an `EdgeMenuBody` too, with `submenu` set and `screen` that of their parent menu: the same grid and zoom on its screen, only capped (never stretched), with no pin or Escape of its own.
- Taking its whole edge (`fillsEdge`, `GridPlacement.menuFillsEdge`: `length` `edge`, or any integrated menu) it's stretched along the edge to `maxLength`; otherwise it scrolls along it past that.
- Its modules are laid out as `GridPlacement.menuModules` gives them: an integrated menu's moved back along the edge to start at its first module, so a lone module placed past the grid's start still spans the edge end to end. A whole-edge floating menu keeps a gap before its modules (`menuKeepsLead`: the layouts editor holds it on purpose); `menuOnScreen` draws both the same.
- Tiled (`background: none`, [Overview](overview.md) › Tiles) it draws a `MenuTile` under each card from its host's `tiles`, and reports what takes input (`maskRects`: its cards as shown and its buttons) for the host's `CardMask`.
- With `pinButton` it draws a pin in the corner away from the edge (`EdgeMenuManager.togglePinned`), after the pop-out toggle of an edge menu with `popOutButton` and before the close a popped-out one has. In the free host (`EdgeMenuBody.free`) or a submenu it has no edge (`edge` is `""`): the buttons are at the top right and growing modules grow downward.

### The lattice along the edge
- Along the edge the modules sit on a lattice fixed to the screen (`GridPlacement.menuAlong`, at the host's `unit`).
  - As many whole cells as fit between the host's `startPad` / `endPad`, centred there and moved `gridOffset` px.
- The modules start `offset` cells from centred on it (negative: towards the start), kept on it. An offset past it is flush with that end's cell.
- A menu longer than its lattice starts at `startPad` and scrolls, as does one taking its whole edge (`menuAlong`; such a menu has no `cell` on the lattice).
- `frameOf(menu)` falls back, for a menu without a running host, to what its host would report: the stroke and padding (an integrated one's frame inset and stroke, `EdgeMenusConfig.outerPadOf`, plus its padding, and its inner stroke after).
- `offset` and `gridOffset` aren't form fields (`x-settings: false`, which `SchemaLayout.objectGroups` leaves out): the layouts editor sets them (see [Editing and submenus](editing-submenus.md)).

### Frames reported to the editor
- Each host reports where its modules can sit: `EdgeMenuSync.frame` → `EdgeMenuManager.setFrame(id, { screen, startPad, endPad, across, before, after, reserves })`.
  - Cleared on destruction or an id change.
- The editor uses it, and also draws the other menus from it (`OverlayManager.menus.screenRectsOf`).

### Shared behaviour (`EdgeMenuSync`)
- Shared by all three hosts. Follows `EdgeMenuManager`, and tells it when the menu closes by itself. Unwanted, it calls `hide()` even while closing, so an open queued by a quick toggle is dropped.
- Held/revealing state, `autoDismiss`, the trigger length, grab-partner registration (the hover strip's `triggerWindow` is optional: a free menu has none).
- The reveal's cursor warp (`warpRequested`), each host warping into its own box.
- The edge hosts centre their hover strip on the modules from config (`EdgeTrigger.centre`; the floating one through `EdgePopout.triggerCentre`), since the body only loads while open.

### `edge`: `FloatingEdgeMenu`
- An `EdgePopout` (`contentPadding`, `edgeOffset`, `fillColor` / `strokeColor`, defaulting to what the OSD uses).
- It's `detached` (a plain box) when:
  - held (`EdgeMenusConfig.detachedOf`: `detached`, or tiled; `distance` across the free screen from its edge, at its automatic gaps at both ends, sliding or fading in, through `EdgePopout.held` / `distance` / `fade`; see [Held off an edge](../popouts/held-off-edge.md)); or
  - its edge has a transparent bar.
- Tiled, its surface is `hollow` (`EdgePopout.hollow`), it hands its body the `tiles` from `EdgePopout.surfaceItem` and `contentInWindow`, and its input goes on the cards (`CardMask` as `EdgePopout.maskRegions`).
- Otherwise it's attached to the border or solid bar, or meets a pill or floating bar as a bar popout does (`EdgePopout.followsBar`; see [Pill and floating bars](../popouts/pill-and-floating-bars.md)).
- Its window sits inside what's reserved on each screen edge, `ScreenEdgeManager.reservedWithMenusOn(screen, location)`:
  - `ScreenEdgeManager.barReservedOn`: the border's `screenMargin` and what each bar on the edge takes (`BarEnds.placeStack`: its zone, less the `-borderWidth` margin Hyprland counts in for a bar inside the border);
  - plus integrated menus' zones;
  - not docks, which it reaches past.
- So its edge coordinates start at `alongOrigin` (what the perpendicular edge at its start reserves), and its ends keep `startPad` / `endPad` from the screen's.
- It places its box with `position: 0` and a `positionOffset` from the modules' start, computed from the box's natural length (the end joins depend on its position).
- With `popoutAtWidget` (and `length: content`; a whole-edge menu keeps its place), opened as a widget's popout (claim kind `bar`) from a bar on its edge and screen, it centres the box on that widget instead (`PopoutAnchor.screenRect`, taken as it opens), as a bar popout does. Its hover strip stays at its layout place.
- Across its edge it sits past `ScreenEdgeManager.reservedWithMenusOn(edge)`.
- Asked for again while open (`EdgeMenuManager.engageRequested`), it engages (`EdgePopout.engage`) and comes forward; the integrated host holds no claim, so it ignores it.
- Its `PopoutClaim` ranks as it was opened (`EdgeMenuManager.claimKinds`, passed to `open`): `menu`, except opened on hover as a bar widget's popout (`PopoutAnchor.menu`, a `Button`'s `popout.menu` included), which ranks `bar`, so a neighbouring widget's popout replaces it ([Registry › Ranks](../popouts/registry.md#ranks)).

### `strip`: `IntegratedEdgeMenu`
- A `PopoutWrapperBase` with a Top-layer `axiom-edge-menu` window along the whole edge.
- It always takes the whole edge: its modules stretch along the strip from end to end, whatever `length` says (`GridPlacement.menuFillsEdge`), and its hover strip is centred on the edge.
- Its layer rule (above every bar's, [layer stacking](../generated/layers.md)) arranges it first, so it sits outermost, and the border, bars and every Normal-exclusion surface move inwards (see [Layering and corners](../bar/layering-and-corners.md)).
- Its window shows through a `LayerSlot`. With layer rules it maps only while open. Without them it's `held`: mapped from the start, a pixel deep, reserving nothing and taking no input while closed (`LayerSlot.idle`), so opening never maps it after the bars it pushes inwards ([layer arrangement](../compositor/layer-arrangement.md)).
- The zone is set once while it's open (windows retile in one step), and the strip slides in.
- With `frame`, a rounded stroked box runs the strip's whole length.
  - Its stroke's inner edge is `screenMargin` in from the strip's edges (as the border's is, so the two line up: `EdgeMenusConfig.frameInsetOf`, `outerPadOf`).
  - It holds the modules `Popouts.padding` in from its stroke.
- It reports its zone by its id (`ScreenEdgeManager.setZone`: one that moves edge or screen leaves nothing behind, and menus on one edge add up), which `BarPopouts.borderInset` takes off the perpendicular bars' length.
- No `SubPopout`, so Submenu rows are dimmed and inert here.
