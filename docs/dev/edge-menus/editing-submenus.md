# Edge menus: editing and submenus

> **Files:** `qml/services/ui/EdgeMenuEditor.qml`, `qml/services/ui/EdgeMenuManager.qml`, `qml/config/EdgeMenusConfig.qml`, `qml/components/views/Layouts/MenuTarget.qml`, `qml/components/views/Layouts/MenuOpening.qml`, `qml/components/views/Layouts/OpenerButtons.qml`, `qml/components/views/Layouts/MenusSection.qml`, `qml/components/methods/MenuSeeds.qml`, `qml/components/content/Submenu/Submenu.qml`, `qml/components/content/Submenu/MenuSubmenu.qml`, `qml/services/ui/GridEditor.qml`
> **Config:** `EdgeMenus.items[]` (`placement: "free"`, `offset`, `gridOffset`, `modules[]` with `Submenu` modules' `menu`, `openOnHover`)
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
- A new menu (`addMenu`) is selected and starts previewing; what it starts as depends on what it's for (below).
- Beside "Show on screen", "Show other menus" draws the others on the grid.

### Creating a menu from what opens it
- **What it starts as** is `MenuSeeds.seed(purpose, id, name)` (pure, `tst_MenuSeeds`), over the `EdgeMenu` schema's defaults (`ConfigManager.withDefaults`):

  | Purpose | Seed |
  |---|---|
  | `edge` (the default: `addMenu()`) | `placement: edge`, `open.onHover: true` |
  | `popout` | `placement: free` |
  | `submenu` | `placement: free` |
  | `key` | `placement: free`, `freeAnchor.at: centre` |
- **Layouts' New menu** (`MenusSection`) opens a `StyledContextMenu` of the four purposes, then `addMenu(purpose)`.
  - `edge`, `popout` and `submenu` add the menu to the draft, unsaved.
  - `key` saves it at once (`addSavedMenu`), since a keybind may only open a saved menu (`isSaved`), then runs `addKeybind` (the Keybinds page recording its key).
- **A Submenu module's New submenu…** (a link under its `menu` field in `EditorInspector`, through `OptionsGroup.fieldAction`): `addSubmenu(moduleIndex)` adds a free menu to the same draft, sets the module's `menu` to it, then selects it and holds it open beside its parent (selecting it clears the parent's undo history, as any change of menu does: the `GridEditor`'s `scopeKey`). Everything stays in one draft, so nothing points at an unsaved menu from another editor.
- **The bar editor's New menu…** (a link under each edge menu picker in `WidgetInspector`: a widget's `popout.menu`, a Button's click `menu`): `OverlayManager.newMenuFor(zone, index, path)`.
  - It saves a new `popout` menu at once (`addSavedMenu` → `_commitNew`: the saved config plus that one item, through `ConfigManager.commit`). The menu draft takes it as saved (`ConfigDraft.adopt`), so it doesn't show as unsaved and a later save of the draft keeps it once.
  - It sets the field in the bar draft (`BarManager.updateWidgetProperty`, undoable; a nested field as its whole object), then opens the menu in Layouts as `editOpenedBy` does (`followLink`).
  - So the bar draft never points at an unsaved menu.
- The pickers keep listing every menu.
- The links are `SettingsLink`s with a `run` function; a form draws one under a field when its `fieldAction` hook (`SchemaPropertiesForm`) gives one.

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
- A menu taking its whole edge (`GridPlacement.menuFillsEdge`: an integrated menu always) has no place along it, and no arrows. A whole-edge floating menu keeps a gap before its modules along the edge through edits (the layouts editor's `hold`, `GridPlacement.menuKeepsLead`); an integrated menu's are normalised to its start as a content-length menu's are.

### Submenus: the Submenu module
- `content/Submenu`: icon, label, an arrow pointing where it opens; `openOnHover`, else a click.
- In a floating menu it opens another menu (`menu`) in the menu's `SubPopout` beside it, as `content/Submenu/MenuSubmenu`:
  - that menu's `EdgeMenuBody` (`submenu` set): its modules on a grid at the card size of the opening menu's screen and its own `moduleScale`;
  - their `host` is that menu's with `submenu: true` (no pin).
- In an integrated menu (no `SubPopout`) the row is dimmed and inert.
- How the `SubPopout` itself is placed and joined: see [Popout submenus](../popouts/submenus.md).

### Submenus: `placement: "free"` menus
- `EdgeMenusConfig.isFree`. It has no place on an edge; its own window is `FreeMenu` ([Free menus](free-menus.md)).
- Its edge, length, offsets and hover opening hide (`x-showIf`); its monitor, pin, colours, open delay, closing, `freeAnchor` and `freeAnimation` show. `placementOf` is null.
- The layouts editor draws just its grid (`MenuTarget`).
- Any other menu can be opened as a submenu too.
- `references(id)` lists the Submenu modules opening a menu; one opening the menu it's in is a problem.
- "Show on screen" on a free menu opens the first enabled `edge` menu with a Submenu module opening it (`submenuParentOf`, `previewParent`, held as the preview is). That menu's first such row opens it and holds it (`content/Submenu.previewed`). With no such menu, the free menu opens on its own, at its `freeAnchor`.
- A bar widget's `popout.menu` can open a free menu, at the widget (`popoutMenuOf`), and the Opening group offers a bar button and a keybind for it as for any menu (`OpenerButtons`).
