# Edge menus: overview, fields and state

> **Files:** `services/ui/EdgeMenuManager.qml`, `config/EdgeMenusConfig.qml`, `shell/EdgeMenus.qml`, `components/surfaces/edgemenu/`, `components/content/QuickActions/QuickActions.qml`
> **Config:** `EdgeMenus.items[]` (→ `definitions.EdgeMenu` in the schema)
> **Related:** [Hosts](hosts.md), [Editing and submenus](editing-submenus.md), [Pages and grid](../overlay/pages-and-grid.md), [Popout registry](../popouts/registry.md), [Held off an edge](../popouts/held-off-edge.md)

Menus that pop out of a screen edge, holding overlay modules. This doc lists an entry's fields, the open/pinned state in `EdgeMenuManager`, pinning and how modules learn their host. How the two host modes draw is in [Hosts](hosts.md); editing in [Editing and submenus](editing-submenus.md).

### The section
- `EdgeMenus` is an array like `Bars`.
- `x-settings: false`, and blocked from `/config`: the layouts editor owns it.
- Escape closes a focused menu (`EdgeMenuBody`), and the `edgeMenu` bind action toggles one by id.

### An entry's fields
- `id`, `name`, `monitor`, `edge`, `mode`.
- `offset` / `gridOffset`: where the modules sit along the edge (see [Hosts](hosts.md)).
- `length` (floating menus only: an integrated menu always takes its whole edge, `GridPlacement.menuFillsEdge`, so the setting is hidden for it, `x-showIf: {mode: floating}`):
  - `content`: as long as its modules;
  - `edge`: fitted to the whole edge. Its rows (columns on a top/bottom edge) grow or shrink evenly to take exactly the room (`GridPlacement.trackSizes` with `fit`, down to half a unit, scrolling only past that; `menuOnScreen` draws it the same in the editor). Modules go compact below their minimum.
- `moduleScale`: % of the card size on its screen (`OverlayConfig.cardUnitOn`, from `Widget.cardSize`; the overlay's own Module size doesn't apply).
- `grid.fine`: each unit split in two each way.
  - `cardUnitOf` takes `GridPlacement.fineUnit`, so the places scaled keep their size exactly.
  - The editor's `GridEditor.sizeScale` doubles default sizes.
  - `updateMenuField` rescales the places (`GridPlacement.scalePlace`) and `offset` so modules stay put, as the lock screen's does.
- Style:
  - `padding`, `moduleBorders`, `pinButton`;
  - `backgroundColor` / `borderColor`, read through `EdgeMenusConfig.colorsOf`;
  - floating: `detached` / `gap` (see [Held off an edge](../popouts/held-off-edge.md));
  - integrated: `frame`.
- Opening: `openOnHover`, `openDelay`, `triggerSize`, `triggerLength` (0 is the menu's length: `EdgeMenusConfig.lengthOf` from config until it's loaded).
- Closing: `closeOnLeave`, `closeDelay`, `closeOnOutsideClick`.
- `modules`: placed as on a Custom page.

### State (`EdgeMenuManager`)
- Holds which menus are open and pinned, in a `PersistentProperties`, so a reload doesn't reflow windows.
- Owns the `edgeMenu` IPC target.
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

### Hosts seen by modules
- Modules learn where they're shown from `host`: `{ kind: "overlay" }` or `{ kind: "edgeMenu", id, bare }`, on `Card` / `Panel`, passed down `ModuleGrid` → `OverlaySlot`.
- `x-hosts` on a module definition limits where it may go:
  - `OverlayConfig.modulesFor(host)` feeds the library;
  - `GridEditor.problemsFor` flags a misplaced module.
