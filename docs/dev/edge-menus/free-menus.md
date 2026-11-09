# Free menus

> **Files:** `qml/components/surfaces/edgemenu/FreeMenu.qml`, `qml/components/methods/PopoutGeometry.qml`, `qml/components/methods/FreeMenuPlace.qml`, `tests/tst_FreeMenuPlace.qml`, `qml/components/methods/SurfaceContext.qml`, `qml/components/surfaces/edgemenu/EdgeMenu.qml`, `qml/components/surfaces/edgemenu/EdgeMenuSync.qml`, `qml/components/surfaces/edgemenu/EdgeMenuBody.qml`, `qml/config/EdgeMenusConfig.qml`, `qml/components/bar/BarWidgetHost.qml`
> **Config:** `EdgeMenus.items[]` with `placement: "free"`: `freeAnchor` (`at`: `centre` | `cursor` | `point`, `x`, `y`), `freeAnimation` (`fade` | `scale` | `slide`), `screen`, `pinButton`, `backgroundColor` / `borderColor`, `open.delay`, `close.*`
> **Related:** [Overview](overview.md), [Hosts](hosts.md), [Editing and submenus](editing-submenus.md), [Popout registry](../popouts/registry.md), [Popout submenus](../popouts/submenus.md), [Layer arrangement](../compositor/layer-arrangement.md), [Plan](../plans/menus-rework.md)

A menu with no edge (`EdgeMenusConfig.isFree`). It opens in a window of its own, `FreeMenu`, at the bar widget that opened it, or at its `freeAnchor`. Submenu rows can also open it beside another menu, in that menu's submenu (unchanged, see [Editing and submenus](editing-submenus.md)).

### Opening it
- **As a bar widget's popout.** A widget's `popout.menu` can name a free menu (`EdgeMenusConfig.popoutMenuOf`). Its `PopoutAnchor` opens the menu after the menu's own `open.delay` (`EdgeMenusConfig.popoutDelayOf`; a free menu has no edge to hover). The menu ranks as a bar popout (claim kind `bar`).
- **By a bind, IPC, the launcher or a bar Button.** `EdgeMenuManager.open` / `toggle` / `reveal`, as for every menu. It opens at its `freeAnchor` on its `screen`. A reveal warps the cursor into its box.
- **The layouts editor's "Show on screen".** If an `edge` menu has a Submenu row opening the free menu, the editor opens it there, beside that menu. Otherwise it opens the free menu on its own (`EdgeMenuEditor.canPreview`).

### Where it goes (`FreeMenuPlace`)
- Pure. The host hands it:
  - the screen's size;
  - what is kept clear at each edge: `ScreenEdgeManager.reservedWithMenusOn` plus the compositor's `gapsOut` there;
  - the box (its content plus padding);
  - the opener: `PopoutAnchor.screenRect`, taken as it opens, only when it is on the menu's screen;
  - the `freeAnchor`;
  - the cursor (`CompositorManager.withCursorPos`, asked for as it opens; the claim waits for the answer, `_locating`).
- **With an opener**, the box is centred on the widget along its bar's edge, flush with what is kept clear there, and slides in from that edge.
- **Otherwise** it is centred on the cursor, on the point (`x` / `y` % of the screen), or on the free area. It slides in from the screen edge nearest its centre (`nearestEdge`).
- Either way it is clamped into the free area. A box that is too big keeps its start.
- The host reads the result and never re-derives it. The slide edge is latched once the box shows (`ClosedLatch`), so a growing box doesn't turn round.
- A widget on another screen opens the menu at its anchor on its own screen, as a floating edge menu's `popoutAtWidget` does.

### The window
- **Its own full-screen window.** A `PanelWindow` on layer Top, namespace `axiom-menu`, anchored to every side, with `ExclusionMode.Ignore`.
  - It never resizes: its input mask is the box alone, and that only once the claim is granted.
  - This follows the toasts' detached window, and avoids the growth glitch of a layer window resizing while shown.
- **Its place in the stack.** A `LayerSlot`, `held`. Where layers stack by map order, it is mapped from the start and draws and takes nothing while closed (`idle`), so opening it never puts it after the bars. With layer rules it maps only while open. On Top, the compositor hides it under a fullscreen window.
- **Keyboard.** `OnDemand`: it takes the keyboard when clicked. Escape closes it (`EdgeMenuBody`).
- **Outside clicks.** A `FocusGrab`, only while it is open, unpinned (not `EdgeMenuSync.held`) and `close.onOutsideClick` is on. A click in its submenu is inside it.
- **The box.** A detached `EdgeSurface`. What it meets comes from `SurfaceContext.free()`: nothing (no joins, no flush ends, never straight off an edge). With no bar, its shadow is BarStyle's. A small `shape` object hands that to the surface and the `SubmenuHost`, in the shape an `EdgePlacement` would.
- **Its fill.** The blur window draws it where it backs Top surfaces on the menu's screen, except while it scales: the blur window's copy doesn't scale.
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
- **Pinned, it is an `underlay`** (`PopoutGeometry.isUnderlay`): it never collides, so it never closes anything and nothing opening over it closes it or makes it give way. Its submenu neither. The overlay opening leaves it too (`PopoutGeometry.closedByOverlay`); the overlay draws over it. Only free menus do this: every edge menu, detached ones included, still gives way when covered and comes back ([Popout registry](../popouts/registry.md) › Underlays).
- **What draws on top is the layer, not the rank.** Its window is on Top under every popout: bar and edge popouts are on the Overlay layer, or on Top in namespaces ordered over `axiom-menu` (`tst_LayerStack`'s `test_free_menu_order`).
- **Clicks.** It is no grab partner of the other popouts: a click on it closes an open bar or edge popout, as any outside click does. It takes the keyboard only when clicked (`OnDemand`).

### Pinning
- `EdgeMenuManager.canPin` takes a free menu in its own window (its `EdgeMenuBody` isn't a submenu's), so the `pinButton` and QuickActions' `pin` work on it. Shown in another menu's submenu it has no pin.
- Pins are saved in `ui/edgemenus.json`, as for every menu, and a pinned free menu opens again when qs starts (at its `freeAnchor`).
- On Top, a pinned one hides under a fullscreen window and comes back after it (the compositor's doing; a live check).
- Dragging a pinned one to move it is later work ([plan](../plans/menus-rework.md)).

### Sharing with the edge hosts
- **`EdgeMenuSync`.** It follows `EdgeMenuManager` and reports a self-close. Its `triggerWindow` is optional: a free menu has no hover strip. It reports no frame (`placementOf` is null for a free menu).
- **`EdgeMenuBody`.** Its `edge` is `""` for a free menu or a submenu: the pin sits at the top right and growing modules grow downward. `GridPlacement.menuFillsEdge` is false for a free menu, whatever its kept `length`.
- **Layer stack.** `axiom-menu` has order 7, beside the integrated menus (the two never meet), under the popouts that slide out from under the bars, and below the Overlay layer (popouts, the overlay). It is in `blurBacked` and `blurChrome`.

### Testing
- `tst_PopoutGeometry` (`test_underlay`, `test_free_not_underlay`, `test_closed_by_overlay`), `tst_FreeMenuPlace`, the `test_free` row of `tst_SurfaceContext`, `tst_LayerStack` (`test_free_menu_order`, `test_sequence_free_menu_held`) and `tst_LayerArrange` (`test_full_screen_ignore`).
- On screen: a nested niri (`scripts/dev/nested.sh niri`) with a free menu in its config.
  - Open it by IPC (`edgeMenu open <id>`).
  - Open it as a widget's popout through a temporary IPC hook that calls `EdgeMenuManager.open(id, anchor, "bar")` with the widget's `PopoutAnchor`.
  - Pinned (`edgeMenu pin <id>`), open another popout over it and check `popouts list` shows both `open`, the menu `underlay`.
  - Screenshot with `WAYLAND_DISPLAY=<nested> grim`.
- Fullscreen hiding and the blur on each compositor are live checks ([live-checks](../live-checks.md)).
