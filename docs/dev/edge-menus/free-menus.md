# Free menus

> **Files:** `qml/components/surfaces/edgemenu/FreeMenu.qml`, `qml/services/ui/EdgeMenuManager.qml`, `qml/services/core/StateManager.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/methods/PopoutGeometry.qml`, `qml/components/methods/FreeMenuPlace.qml`, `tests/tst_FreeMenuPlace.qml`, `qml/components/methods/SurfaceContext.qml`, `qml/components/surfaces/edgemenu/EdgeMenu.qml`, `qml/components/surfaces/edgemenu/EdgeMenuSync.qml`, `qml/components/surfaces/edgemenu/EdgeMenuBody.qml`, `qml/config/EdgeMenusConfig.qml`, `qml/components/bar/BarWidgetHost.qml`
> **Config:** `EdgeMenus.items[]` with `placement: "free"`: `freeAnchor` (`at`: `centre` | `cursor` | `point`, `x`, `y`), `freeAnimation` (`fade` | `scale` | `slide`), `draggable`, `background`, `screen`, `pinButton`, `backgroundColor` / `borderColor`, `open.delay`, `close.*`
> **Related:** [Overview](overview.md), [Hosts](hosts.md), [Editing and submenus](editing-submenus.md), [Popout registry](../popouts/registry.md), [Popout submenus](../popouts/submenus.md), [Layer arrangement](../compositor/layer-arrangement.md), [Plan](../plans/menus-rework.md)

A menu with no edge (`EdgeMenusConfig.isFree`). It opens in a window of its own, `FreeMenu`, at the bar widget that opened it, or at its `freeAnchor` (or where it was dragged this session). Submenu rows can also open it beside another menu, in that menu's submenu (unchanged, see [Editing and submenus](editing-submenus.md)). The same window also shows a popped-out edge menu (below).

### Opening it
- **As a bar widget's popout.** A widget's `popout.menu` can name a free menu (`EdgeMenusConfig.popoutMenuOf`). Its `PopoutAnchor` opens the menu after the menu's own `open.delay` (`EdgeMenusConfig.popoutDelayOf`; a free menu has no edge to hover). The menu ranks as a bar popout (claim kind `bar`).
- **By a bind, IPC, the launcher or a bar Button.** `EdgeMenuManager.open` / `toggle` / `reveal`, as for every menu. It opens at its `freeAnchor` on its `screen`, or at its session spot (Dragging). A bar Button passes itself as the anchor, so it opens at the Button. A reveal warps the cursor into its box.
- **The layouts editor's "Show on screen".** If an `edge` menu has a Submenu row opening the free menu, the editor opens it there, beside that menu. Otherwise it opens the free menu on its own (`EdgeMenuEditor.canPreview`).

### Where it goes (`FreeMenuPlace`)
- Pure. The host hands it:
  - the screen's size;
  - what is kept clear at each edge: `ScreenEdgeManager.reservedWithMenusOn` plus the compositor's `gapsOut` there;
  - the box (its content plus padding);
  - the opener: `PopoutAnchor.screenRect`, taken as it opens, only when it is on the menu's screen;
  - the `freeAnchor`;
  - the cursor (`CompositorManager.withCursorPos`, asked for as it opens; the claim waits for the answer, `_locating`);
  - a spot, from `FreeMenuPlace.spot` (below), or none.
- **With a spot**, the box's top-left goes there. It slides in from the nearest screen edge.
- **The spot** (`FreeMenuPlace.spot`), first that applies:
  - where it was dragged since it opened;
  - a popped-out edge menu's spot as it popped out;
  - none when a bar widget opened it (it goes to the widget);
  - its session spot (`EdgeMenuManager.positions`), only while it's `draggable`, on its screen (another screen, or one gone, drops it) and its `freeAnchor` is the one it was dragged from (`anchor`, `FreeMenuPlace.anchorKey`: changing the anchor in Layouts drops it).
- **With an opener**, the box is centred on the widget along its bar's edge, flush with what is kept clear there, and slides in from that edge.
- **Otherwise** it is centred on the cursor, on the point (`x` / `y` % of the screen), or on the free area. It slides in from the screen edge nearest its centre (`nearestEdge`).
- Either way it is clamped into the free area. A box that is too big keeps its start.
- The host reads the result and never re-derives it. The slide edge is latched once the box shows (`ClosedLatch`), so a growing box doesn't turn round.
- A widget on another screen opens the menu at its anchor on its own screen, as a floating edge menu's `popoutAtWidget` does.

### The window
- **Its own full-screen window.** A `PanelWindow` on layer Top, namespace `axiom-menu`, anchored to every side, with `ExclusionMode.Ignore`.
  - It never resizes: its input mask is the box alone (tiled, the gaps between its cards too), and that only once the claim is granted.
  - This follows the toasts' detached window, and avoids the growth glitch of a layer window resizing while shown.
- **Its place in the stack.** A `LayerSlot`, `held`. Where layers stack by map order, it is mapped from the start and draws and takes nothing while closed (`idle`), so opening it never puts it after the bars. With layer rules it maps only while open. On Top, the compositor hides it under a fullscreen window.
- **Keyboard.** `OnDemand`: it takes the keyboard when clicked. Escape closes it (`EdgeMenuBody`).
- **Outside clicks, no grab** (decided 2026-11-10: a click on a window "Close + reach window"). Open, unpinned (not `EdgeMenuSync.held`) and with `close.onOutsideClick` on, a `FocusLeave` closes it: once the compositor focuses a window (`CompositorManager.activeWindowId` turning to one), or once it had the keyboard (it was clicked) and keyboard focus left it and its submenu. It holds nothing, so the windows behind stay usable and focusable, and the click that closes it reaches its window, on Hyprland, niri and sway alike.
  - Before, it took a `FocusGrab`: Hyprland's native grab kept the pointer and keyboard off other windows and ate the click that ended it; elsewhere every screen's backdrop window caught clicks under it and the menu took the keyboard exclusively. A popped-out or pinned menu, held, never took it: that was the difference the maintainer saw.
  - Limits: a click on the window already focused closes it only once the menu had the keyboard; one on a bar, the border or the wallpaper focuses no window and leaves it open; with focus following the mouse (Hyprland's `input:follow_mouse 1`, sway's `focus_follows_mouse yes`, niri's `focus-follows-mouse`) pointing at another window focuses it, which closes it as a click would.
  - A click in its submenu is inside it. Its header's Reset position menu alone takes a `FocusGrab` while open.
- **The box.** A detached `EdgeSurface`. What it meets comes from `SurfaceContext.free()`: nothing (no joins, no flush ends, never straight off an edge). With no bar, its shadow is BarStyle's. A small `shape` object hands that to the surface and the `SubmenuHost`, in the shape an `EdgePlacement` would.
- **Its fill.** The blur window draws it where it backs Top surfaces on the menu's screen, except while it scales: the blur window's copy doesn't scale. Tiled, the box is `hollow` and the tiles are drawn the same way (`tiles`, from `shape.backed` and the content's place on the screen).
- **Animation (`freeAnimation`).**
  - `fade`: `AttachedSurface.fade`.
  - `scale`: from 90 %, fading as it scales (`Appearance.animNormal`, `Appearance.easing`).
  - `slide`: in from its slide edge, clipped there, as any detached box slides.

### Submenus inside it
- It hosts a `SubmenuHost`, and its window's `popoutHost` is that submenu, so Submenu rows inside a free menu open beside its box.
- The `SubmenuSide` rules apply to it as to a detached box: it opens towards the screen's nearer half (or away from a side slide edge). A submenu longer than the box stretches the box past its top or bottom.

### Its claim
- A `PopoutClaim` keyed `menu:<id>`, with edge `""` and the box's footprint on the screen.
- Its kind is the opener's (`EdgeMenuManager.claimKinds`): `bar` for a widget's popout, else `menu`.
- Held by the editor (previewing), it is `resident`: it gives way and comes back.
- **It ranks as any popout** (decided 2026-11-10: "Bars must not move/redraw when making an action"). Unpinned, as its kind: a higher popout over it (the launcher) closes it, and a lower one it covers (a bar popout over a `menu`-kind one) doesn't open.
- **Pinned (or a popped-out edge menu), it ranks as a pinned menu** (`FreeMenuPlace.ranksPinned`): lowest, `resident`, so it gives way (hides) while a popout covers it and comes back after ("Menu hides, comes back"), as a pinned edge menu does. Hovered, just opened or asked for again (`engageRequested`, also for a popped-out one opened again) it is `engaged` and ranks as its kind meanwhile, as `EdgePopout.engaged`. The overlay opening closes it, as it closes a pinned edge menu ([Popout registry](../popouts/registry.md) › Free menus).
- **Its layer.** Its window is on Top under every popout (`tst_LayerStack`'s `test_free_menu_order`), so a popout opening over it draws on top while its box goes.
- **Clicks.** It is no grab partner of the other popouts: a click on it closes an open bar or edge popout, as any outside click does. It takes the keyboard only when clicked (`OnDemand`), never exclusively.

### Pinning
- `EdgeMenuManager.canPin` takes a free menu in its own window (its `EdgeMenuBody` isn't a submenu's), so the `pinButton` and QuickActions' `pin` work on it. Shown in another menu's submenu it has no pin.
- Pins are saved in `ui/edgemenus.json`, as for every menu, and a pinned free menu opens again when qs starts (at its `freeAnchor`).
- On Top, a pinned one hides under a fullscreen window and comes back after it (the compositor's doing; a live check).

### Dragging
- With `draggable` on (the default), its header moves the box while dragged, whenever it's open, pinned or not. The header is the box's top padding, a `DragArea` in the surface, so hovering it is hovering the box (`keepAlive`).
- `FreeMenuPlace.canDrag`: a free menu, or a popped-out edge menu, with `draggable` on.
- Nothing is previewed while dragging. The box goes where the drag puts it (`_dragged`, the spot), clamped as any spot is. Its claim's footprint follows, so it closes what it now covers below it.
- **On release**, `FreeMenuPlace.keepsDrag` says whether the spot is kept: only for a free menu opened on its own (a bind, IPC, a pin reopening). A copy a widget opened, and a popped-out edge menu, move for the moment only. Kept, `EdgeMenuManager.storePosition` stores it with the `freeAnchor` it was dragged from.
- **The session spot.** `EdgeMenuManager.positions`, kept in `$XDG_RUNTIME_DIR/axiom/state/menu-positions.json` through `StateManager.createSessionHandler`: read at each load, so it survives qs reloads and restarts, and gone at logout (the runtime folder is). It is never written to config.
- **Reset.** A right click on the header offers Reset position (a `StyledContextMenu`; while it's open the window's mask takes its box and the focus grab is on, so a click elsewhere closes it). IPC `edgeMenu resetPosition <id>` does the same. Both call `EdgeMenuManager.resetPosition`, and the open menu goes back to its anchor, even dragged since it opened (`positionReset`).
- A pin still reopens it when qs starts. After a logout that is at its `freeAnchor`.

### A popped-out edge menu
- An `edge` menu with `popOutButton` (`EdgeMenusConfig.canPopOut`; never a strip, and a free menu has none) has a pop-out toggle beside its pin (`EdgeMenuBody`).
- **Popping out.** `EdgeMenuManager.togglePoppedOut` asks its `FloatingEdgeMenu` (`popOutRequested`), which answers `popOut(id, spot)` with its content's place on the screen less the padding (`EdgePopout.contentOnScreen`). `EdgeMenuManager.poppedOut` then holds that spot.
- **The handover.** `EdgeMenu` loads the hosts `FreeMenuPlace.hosts` names. A popped-out edge menu is in the free host, and its edge host stays until the free one has drawn its box (`boxShown`, latched in `_handedOver` so a fullscreen window hiding the free one never brings the edge one back).
  - The free box comes up with no animation (`animationDuration` 0) at that spot, clamped into the free area. So a box attached to its edge moves inwards by the edge's gap.
  - Both hosts' claims are keyed `menu:<id>`. The free one's replaces the edge one's entry, and `PopoutManager.update` ignores the edge one from then on.
  - It keeps its edge's layout: a top or bottom menu's modules along a row (`vertical`), its whole-edge stretch along that axis.
- **While out**, it is held as if pinned (`EdgeMenuManager.isHeld`): it doesn't close on leave or on an outside click, and its claim ranks as a pinned menu's (`FreeMenuPlace.ranksPinned`). A close button shows beside the pin. Dragged, it moves for the moment only.
- `EdgeMenuManager.open` and `reveal` do nothing to it (no second copy), and its edge host, with its hover strip, isn't loaded.
- **Closed = docked.** `EdgeMenuManager.close` docks a popped-out menu (`dock`), closed: the close button, the pop-out toggle, a bind or bar Button toggle, `edgeMenu close`, Escape. The next open is on its edge.
- **Nothing is kept.** `poppedOut` is in the `PersistentProperties` only so a reload can dock it, closed (`_run.onLoaded`). It is never in `ui/edgemenus.json`.
- A fullscreen window only hides it (its window is on Top).

### Sharing with the edge hosts
- **`EdgeMenuSync`.** It follows `EdgeMenuManager` and reports a self-close. Its `triggerWindow` is optional: a free menu has no hover strip. It reports no frame (`placementOf` is null for a free menu).
- **`EdgeMenuBody`.** Its `edge` is `""` for a free menu or a submenu: the pin sits at the top right and growing modules grow downward. `GridPlacement.menuFillsEdge` is false for a free menu, whatever its kept `length`.
- **Layer stack.** `axiom-menu` has order 7, beside the integrated menus (the two never meet), under the popouts that slide out from under the bars, and below the Overlay layer (popouts, the overlay). It is in `blurBacked` and `blurChrome`.

### Testing
- `tst_PopoutGeometry` (`test_free_menu`), `tst_FreeMenuPlace` (the place, `spot`, `keepsDrag`, `canDrag`, `ranksPinned`, `hosts`), the `test_free` row of `tst_SurfaceContext`, `tst_LayerStack` (`test_free_menu_order`, `test_sequence_free_menu_held`) and `tst_LayerArrange` (`test_full_screen_ignore`).
- On screen: a nested niri (`scripts/dev/nested.sh niri`) with a free menu in its config.
  - Open it by IPC (`edgeMenu open <id>`).
  - Open it as a widget's popout through a temporary IPC hook that calls `EdgeMenuManager.open(id, anchor, "bar")` with the widget's `PopoutAnchor`.
  - Pinned (`edgeMenu pin <id>`), open an overlapping popout and check `popouts list` shows the menu `yielded` (`pinned resident`), then `open` again once the popout closes. Unpinned, an overlapping lower popout isn't listed (refused), and the launcher closes the menu.
  - Screenshot with `WAYLAND_DISPLAY=<nested> grim`.
  - Run the nested shell with a scratch `XDG_RUNTIME_DIR` (its socket path must stay under 108 characters), so its session spots aren't the live shell's.
  - Session spots: a temporary IPC hook calling `storePosition` stands in for a drop (no simulated pointer). Reopen by IPC, reload, change the `freeAnchor`, and `resetPosition`; `popouts list` shows where the box went.
  - Pop-out: a temporary IPC hook calling `togglePoppedOut`. Then `edgeMenu open` (nothing changes), `close` and `toggle` (docked, closed), and a reload while it's out (docked, closed).
- Fullscreen hiding and the blur on each compositor are live checks ([live-checks](../live-checks.md)).
