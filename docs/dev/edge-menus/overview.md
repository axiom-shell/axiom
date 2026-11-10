# Edge menus: overview, fields and state

> **Files:** `qml/services/ui/EdgeMenuManager.qml`, `qml/config/EdgeMenusConfig.qml`, `qml/shell/EdgeMenus.qml`, `qml/components/surfaces/edgemenu/`, `qml/components/surfaces/edgemenu/MenuTile.qml`, `qml/components/methods/MenuTiles.qml`, `tests/tst_MenuTiles.qml`, `qml/components/content/QuickActions/QuickActions.qml`
> **Config:** `EdgeMenus.items[]` (→ `definitions.EdgeMenu` in the schema)
> **Related:** [Hosts](hosts.md), [Free menus](free-menus.md), [Editing and submenus](editing-submenus.md), [Pages and grid](../overlay/pages-and-grid.md), [Popout registry](../popouts/registry.md), [Held off an edge](../popouts/held-off-edge.md)

Menus that pop out of a screen edge, holding overlay modules. This doc lists an entry's fields, the open/pinned state in `EdgeMenuManager`, pinning and how modules learn their host. How the two edge hosts (placements `edge` and `strip`) draw is in [Hosts](hosts.md), the `free` placement's window in [Free menus](free-menus.md), editing in [Editing and submenus](editing-submenus.md).

### The section
- `EdgeMenus` is an array like `Bars`.
- `x-settings: false`, and blocked from `/config`: the layouts editor owns it.
- Escape closes a focused menu (`EdgeMenuBody`), and the `edgeMenu` bind action toggles one by id.

### An entry's fields
- `id`, `name`, `monitor`, `edge`, `placement` (`edge` | `strip` | `free`; until config v103 `mode`: `floating` | `integrated` | `submenu`).
- Free menus: `freeAnchor`, `freeAnimation` and `draggable` ([Free menus](free-menus.md)); their edge, length, offsets and hover opening hide.
- `popOutButton` (`edge` menus only) and, with it on, `draggable`: a pop-out toggle beside the pin ([Free menus](free-menus.md) › A popped-out edge menu).
- `offset` / `gridOffset`: where the modules sit along the edge (see [Hosts](hosts.md)).
- `length` (`edge` menus only: a `strip` menu always takes its whole edge, `GridPlacement.menuFillsEdge`, so the setting is hidden for it, `x-showIf: {placement: edge}`):
  - `content`: as long as its modules;
  - `edge`: fitted to the whole edge. Its rows (columns on a top/bottom edge) grow or shrink evenly to take exactly the room (`GridPlacement.trackSizes` with `fit`, down to half a unit, scrolling only past that; `menuOnScreen` draws it the same in the editor). Modules go compact below their minimum.
- `moduleScale`: % of the card size on its screen (`OverlayConfig.cardUnitOn`, from `Widget.cardSize`; the overlay's own Module size doesn't apply), shrunk where the menu would be deeper than its screen (`EdgeMenusConfig.scaleOf`).
- `grid.fine`: each unit split in two each way.
  - `cardUnitOf` takes `GridPlacement.fineUnit`, so the places scaled keep their size exactly.
  - The editor's `GridEditor.sizeScale` doubles default sizes.
  - `updateMenuField` rescales the places (`GridPlacement.scalePlace`) and `offset` so modules stay put, as the lock screen's does.
- Style:
  - `moduleBorders`, `pinButton` (the padding is `Popouts.padding`);
  - `background` (`panel` | `none`; `edge` and `free` menus only, never a strip): `none` draws the menu as tiles (Tiles, below);
  - `backgroundColor` / `borderColor`, read through `EdgeMenusConfig.colorsOf` (a tiled menu has no border: the setting hides);
  - floating: `detached` / `distance` / `animation` (see [Held off an edge](../popouts/held-off-edge.md)), read through `EdgeMenusConfig.detachedOf`: a tiled edge menu is always held off its edge, so `detached` hides and `distance` and `animation` show;
  - integrated: `frame`.
- Opening: `open.onHover`, `open.delay`. The hover strip is `ScreenEdge.triggerSize` deep and as long as the menu, worked out from config alone so it's the same open or closed (`EdgeMenuSync.triggerLength`, the whole room along the edge for a whole-edge menu).
- Closing: `closeOnLeave`, `closeDelay`, `closeOnOutsideClick`.
- `modules`: placed as on a Custom page.

### State (`EdgeMenuManager`)
- Holds which menus are open and pinned, in a `PersistentProperties`, so a reload doesn't reflow windows.
- Holds which edge menus are popped out (`poppedOut`, runtime only: a reload docks them, closed) and the free menus' session spots (`positions`, in `$XDG_RUNTIME_DIR`, gone at logout; `resetPosition`). See [Free menus](free-menus.md).
- Owns the `edgeMenu` IPC target. Its `open` and `toggle` reveal a closed menu (`reveal`: the cursor moves into it), so one that closes on leave stays up when a bind or script opens it.
- The layouts editor's draft of the menus is not here: `OverlayManager.menus` (`EdgeMenuEditor`, [Editing and submenus](editing-submenus.md)).
- The menus follow it and report back when they close by themselves.
- They work over the overlay:
  - their windows and hover strips are its grab partners (`EdgeMenuSync`'s `window` and `triggerWindow`);
  - a floating one draws over it and, while it's open on its screen, takes no focus grab of its own (`grabEnabled`), which would clear the overlay's and close it.
- An open floating menu closes what it covers below it and gives way to what's above (PopoutManager; see [Popout registry](../popouts/registry.md)). Pinned, it ranks lowest; pinned or previewing, it comes back once uncovered. Opened on hover as a bar widget's popout (its `PopoutAnchor`, a `Button`'s `popout.menu` included), it ranks as a bar popout, so a neighbouring widget's popout replaces it. With `popoutAtWidget` it then opens at that widget, as a bar popout does, rather than at its layout place.
- A bar `Button` with `action: "edgeMenu"` and `menu: <id>` toggles one on a click, passing itself as the anchor, so a floating menu stays open while the button is hovered. Its `hoverActivate` never runs this action: a menu on hover is its `popout` (`enabled`, `menu`).

### Pin
- `pinButton` puts a pin on the menu, and QuickActions has a `pin` action. Both toggle `EdgeMenuManager.pinned[id]`.
- While pinned, a menu ignores `closeOnLeave` and outside clicks.

### Pop out
- `popOutButton` (an `edge` menu's) puts a pop-out toggle beside the pin. It lifts the open menu into the free host where its box is, held open as if pinned (an underlay), with a close button.
- Every close docks it, closed: the close button, the toggle, a bind or bar Button toggle, `edgeMenu close`, Escape. While it's out, opening it and hovering its edge do nothing.
- Nothing of it is kept: a reload docks it, closed. A fullscreen window only hides it. Details: [Free menus](free-menus.md) › A popped-out edge menu.
- A pinned edge or strip menu still gives way when covered and comes back. Only a pinned free menu stays visible under the popouts opened over it, closing none of them ([Free menus](free-menus.md) › Its claim).

### Tiles (`background: none`)
- `EdgeMenusConfig.tiledOf` (`MenuTiles.tiled`): `none` on an `edge` or `free` menu. A strip always draws its frame. A free menu shown in another menu's submenu draws its submenu's box as before.
- **No box.** The host's surface is `hollow` (`AttachedSurface.hollow`): no fill, stroke or shadow of its own, and no `BlurShape`, but its room for a shadow is kept. A tiled edge menu is held off its edge (`EdgeMenusConfig.detachedOf`, `MenuTiles.detached`), so it never joins a bar or the border and `BarEnds` has no corner to draw for it.
- **A tile under each card** (`MenuTile`, built by `EdgeMenuBody` only with `layout.moduleBorders` on: a bare module has no card to sit on). It is the card's rect (`ModuleGrid.cardRects`; under an expanded detail the tiles stay under the dimmed cards, the detail's own box over them), at the card's drawn radius, in the menu's `backgroundColor`, with the shadow the box would cast. So a card looks as it does on a panel; only the gaps between cards are clear.
  - Drawn outside the body's scrolling view, so its shadow isn't cut there: scrolled and cut to the view (`MenuTiles.shown`), its growing eased as the card's slot is.
  - Backed by the blur window (the host's `tiles.backed`), it's a `BlurShape` (`kind: "rect"`) at its place on the screen, which fills it, blurs behind it and casts its shadow (on niri, one blur region piece per card). Otherwise it fills itself, with an `OutsideShadow`.
  - The host hands the body `tiles`: whether it's backed or solid, its screen, the body's top-left on the screen as drawn (slid: `AttachedSurface.slideX` / `slideY`), its window on the screen, its layer, how far it has faded in and the shadow's look.
- **The gaps are the menu's** (decided 2026-11-10: "It should just reserve the mouse"). Its input is its whole box, as with a panel: the pointer over a gap is over the menu (it keeps it open, `close.delay` as set), and a click there is inside it, never an outside click and never reaching what's behind. The tiles are drawing only.
- Tests: `tst_MenuTiles`.

### Hosts seen by modules
- Modules learn where they're shown from `host`: `{ kind: "overlay" }` or `{ kind: "edgeMenu", id, bare }`, on `Card` / `Panel`, passed down `ModuleGrid` → `OverlaySlot`.
- `x-hosts` on a module definition limits where it may go:
  - `OverlayConfig.modulesFor(host)` feeds the library;
  - `GridEditor.problemsFor` flags a misplaced module.
