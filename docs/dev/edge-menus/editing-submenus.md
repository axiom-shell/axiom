# Edge menus: editing and submenus

> **Files:** `services/ui/EdgeMenuEditor.qml`, `services/ui/EdgeMenuManager.qml`, `config/EdgeMenusConfig.qml`, `components/views/Layouts/MenuTarget.qml`, `components/views/Layouts/MenuOpening.qml`, `components/views/Layouts/OpenerButtons.qml`, `components/content/Submenu/Submenu.qml`, `components/content/Submenu/MenuSubmenu.qml`, `services/ui/GridEditor.qml`
> **Config:** `EdgeMenus.items[]` (`mode: "submenu"`, `offset`, `gridOffset`, `modules[]` with `Submenu` modules' `menu`, `openOnHover`)
> **Related:** [Overview](overview.md), [Hosts](hosts.md), [Layouts editor](../overlay/layouts-editor.md), [Grid canvas](../overlay/grid-canvas.md), [Popout submenus](../popouts/submenus.md), [Editors pattern](../core/editors-pattern.md)

How edge menus are edited on the Layouts page (draft, field groups, previewing, openers, moving along the edge), and how one menu opens another as a submenu.

### Draft
- Editing happens on the Layouts page (see [Layouts editor](../overlay/layouts-editor.md)).
- The draft lives in `EdgeMenuEditor`, which `OverlayManager` holds as `menus` (not a singleton; `EdgeMenuManager` keeps only the running menus' state): `ConfigDraft { path: ["EdgeMenus"] }`, plus `layout`, the selected menu's `GridEditor` with host `edgeMenu`.
- While dirty it shows live on the running menus through its `EdgeMenus` preview (`ConfigManager.setPreview`), as the bar editor's does.

### Field groups
- The menu's fields come in `x-group`s: General, Opening, Placement, Style, Closing, Advanced (the read-only `id`).
- The Opening group leads with `MenuOpening`:
  - **"Show on screen"**: sets `previewing` to the selected menu (following the selection and id renames) and opens it.
    - `isHeld(id)` (pinned or previewing) makes a menu ignore `closeOnLeave` and outside clicks.
    - The page's `onDestruction` stops it.
  - **What else opens the menu** (`OverlayManager.menus.references(id)`):
    - bar Buttons and widgets opening it as their menu popout (`EdgeMenusConfig.menusOpenedBy`, which the bar inspector's link to the layouts editor reads too, `OverlayManager.openedBy`: a Button's click action first, then its menu popout, passing over one that's gone), in the bar editor's draft or saved bars;
    - binds in the keybind editor's draft or `KeybindsConfig.binds`.
  - **Buttons that add an opener**, drawn by `OpenerButtons` (shared with the page's Opening group):
    - a bar Button: `addBarButton` → `BarManager.addWidgetTo`, into the bar editor's draft, then the bar editor on that bar;
    - a keybind: `addKeybind` → `KeybindManager.editor.addAndRecord`, then the Keybinds page's editor recording its key.
- A new menu (`addMenu`) opens on hover and starts previewing.
- Beside "Show on screen", "Show other menus" draws the others on the grid.

### The canvas never moves modules on screen
- The canvas's lattice is the menu's (its cells past the lattice along the edge tinted, `latticeSpan`), so it never moves when modules do.
- Edits never move modules on the screen:
  - `GridEditor.shifted` hands `_keepPlace` the shift `normalize` took off and the bounds before the edit;
  - the menu's `offset` follows, so its modules keep their cells;
  - a module dropped left of the others lands where it was dropped.

### Moving along the edge
- The arrows under the canvas title are `EditTarget`'s nudge fields, from `MenuTarget`: left/right on a top or bottom edge, up/down on a side.
- They step `offset` a cell at a time within `GridPlacement.offsetRange` (`nudgeSelected(step)`; `centreSelected()` recentres), saying where it is: Centred, n cells from the centre, at an end.
- The Grid stepper beside them moves the lattice up to half a cell either way (`setGridOffset`, `gridOffsetLimit`).
- A menu taking its whole edge has no place along it, and no arrows.

### Submenus: the Submenu module
- `content/Submenu`: icon, label, an arrow pointing where it opens; `openOnHover`, else a click.
- In a floating menu it opens another menu (`menu`) in the menu's `SubPopout` beside it, as `content/parts/MenuSubmenu`:
  - that menu's modules on a grid at the card size of the opening menu's screen and its own `moduleScale`;
  - their `host` is that menu's with `submenu: true` (no pin).
- In an integrated menu (no `SubPopout`) the row is dimmed and inert.
- How the `SubPopout` itself is placed and joined: see [Popout submenus](../popouts/submenus.md).

### Submenus: `mode: "submenu"` menus
- `EdgeMenusConfig.isSubmenu`. It has no host of its own (`EdgeMenu` loads none) and no place on an edge.
- Its edge, placement, style colours, opening and closing fields hide (`x-showIf`), and `placementOf` is null.
- The layouts editor draws just its grid (`MenuTarget`).
- Any other menu can be opened as a submenu too.
- `references(id)` lists the Submenu modules opening a menu; one opening the menu it's in is a problem.
- "Show on screen" on a submenu menu opens the first enabled floating menu with a Submenu module opening it (`submenuParentOf`, `previewParent`, held as the preview is). That menu's first such row opens it and holds it (`content/Submenu.previewed`).
- A bar widget's `popout.menu` never opens a submenu menu (`popoutMenuOf`).
