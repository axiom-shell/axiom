# Edge menus: overview, fields and state

> **Files:** `qml/services/ui/EdgeMenuManager.qml`, `qml/config/EdgeMenusConfig.qml`, `qml/shell/EdgeMenus.qml`, `qml/components/surfaces/edgemenu/`, `qml/components/content/QuickActions/QuickActions.qml`
> **Config:** `EdgeMenus.items[]` (→ `definitions.EdgeMenu` in the schema)
> **Related:** [Hosts](hosts.md), [Free menus](free-menus.md), [Editing and submenus](editing-submenus.md), [Pages and grid](../overlay/pages-and-grid.md), [Popout registry](../popouts/registry.md), [Held off an edge](../popouts/held-off-edge.md)

Menus that pop out of a screen edge, holding overlay modules. This doc lists an entry's fields, the open/pinned state in `EdgeMenuManager`, pinning and how modules learn their host. How the two edge hosts (placements `edge` and `strip`) draw is in [Hosts](hosts.md), the `free` placement's window in [Free menus](free-menus.md), editing in [Editing and submenus](editing-submenus.md).

### The section
- `EdgeMenus` is an array like `Bars`.
- `x-settings: false`, and blocked from `/config`: the layouts editor owns it.
- Escape closes a focused menu (`EdgeMenuBody`), and the `edgeMenu` bind action toggles one by id.

### An entry's fields
- `id`, `name`, `monitor`, `edge`, `placement` (`edge` | `strip` | `free`; until config v103 `mode`: `floating` | `integrated` | `submenu`).
- Free menus: `freeAnchor` and `freeAnimation` ([Free menus](free-menus.md)); their edge, length, offsets and hover opening hide.
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
  - `backgroundColor` / `borderColor`, read through `EdgeMenusConfig.colorsOf`;
  - floating: `detached` / `distance` / `animation` (see [Held off an edge](../popouts/held-off-edge.md));
  - integrated: `frame`.
- Opening: `open.onHover`, `open.delay`. The hover strip is `ScreenEdge.triggerSize` deep and as long as the menu, worked out from config alone so it's the same open or closed (`EdgeMenuSync.triggerLength`, the whole room along the edge for a whole-edge menu).
- Closing: `closeOnLeave`, `closeDelay`, `closeOnOutsideClick`.
- `modules`: placed as on a Custom page.

### State (`EdgeMenuManager`)
- Holds which menus are open and pinned, in a `PersistentProperties`, so a reload doesn't reflow windows.
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
- A pinned edge or strip menu still gives way when covered and comes back. Only a pinned free menu stays visible under the popouts opened over it, closing none of them ([Free menus](free-menus.md) › Its claim).

### Hosts seen by modules
- Modules learn where they're shown from `host`: `{ kind: "overlay" }` or `{ kind: "edgeMenu", id, bare }`, on `Card` / `Panel`, passed down `ModuleGrid` → `OverlaySlot`.
- `x-hosts` on a module definition limits where it may go:
  - `OverlayConfig.modulesFor(host)` feeds the library;
  - `GridEditor.problemsFor` flags a misplaced module.
