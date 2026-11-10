# Menus: editing and submenus

> **Files:** `qml/services/ui/MenuEditor.qml`, `qml/services/ui/MenuManager.qml`, `qml/config/MenusConfig.qml`, `qml/components/views/Layouts/MenuTarget.qml`, `qml/components/views/Layouts/MenuOpening.qml`, `qml/components/views/Layouts/OpenerButtons.qml`, `qml/components/views/Layouts/MenusSection.qml`, `qml/components/methods/MenuSeeds.qml`, `qml/components/content/Submenu/Submenu.qml`, `qml/components/content/Submenu/MenuSubmenu.qml`, `qml/services/ui/GridEditor.qml`
> **Config:** `Menus.items[]` (`placement: "free"`, `offset`, `gridOffset`, `modules[]` with `Submenu` modules' `menu`, `openOnHover`)
> **Related:** [Overview](overview.md), [Hosts](hosts.md), [Layouts editor](../overlay/layouts-editor.md), [Grid canvas](../overlay/grid-canvas.md), [Popout submenus](../popouts/submenus.md), [Editors pattern](../core/editors-pattern.md)

How edge menus are edited on the Layouts page (draft, field groups, previewing, openers, moving along the edge), and how one menu opens another as a submenu.

### Draft
- Editing happens on the Layouts page (see [Layouts editor](../overlay/layouts-editor.md)).
- The draft lives in `MenuEditor`, which `OverlayManager` holds as `menus` (not a singleton; `MenuManager` keeps only the running menus' state): `ConfigDraft { path: ["Menus"] }`, plus `layout`, the selected menu's `GridEditor` with host `menu`.
- While dirty it shows live on the running menus through its `Menus` preview (`ConfigManager.setPreview`), as the bar editor's does.

### Field groups
- The menu's fields come in `x-group`s: General, Opening, Placement, Style, Behaviour, Closing, Advanced (the read-only `id`), in the order their first field comes in the schema (`SchemaLayout.objectGroups`). Behaviour holds what the menu's buttons and header do (decided 2026-11-10, review round 2): `pinButton`, `closeButton`, `popOutButton` and `draggable`, so `draggable` sits beside the `popOutButton` it shows with.
- The Opening group leads with `MenuOpening`:
  - **"Show on screen"**: sets `previewing` to the selected menu (following the selection and id renames) and opens it.
    - `isHeld(id)` (pinned or previewing) makes a menu ignore `closeOnLeave` and outside clicks.
    - The page's `onDestruction` stops it.
  - **What else opens the menu** (`OverlayManager.menus.references(id)`):
    - bar Buttons and widgets opening it as their menu popout (`MenusConfig.menusOpenedBy`, which the bar inspector's link to the layouts editor reads too, `OverlayManager.openedBy`: a Button's click action first, then its menu popout, passing over one that's gone), in the bar editor's draft or saved bars;
    - binds in the keybind editor's draft or `KeybindsConfig.binds`.
  - **Buttons that add an opener**, drawn by `OpenerButtons` (shared with the page's Opening group):
    - a bar Button: `addBarButton` → `BarManager.addWidgetTo`, into the bar editor's draft, then the bar editor on that bar;
    - a keybind: `addKeybind` → `KeybindManager.editor.addAndRecord`, then the Keybinds page's editor recording its key.
- A new menu (`addMenu`) is selected and starts previewing; what it starts as depends on what it's for (below).
- Beside "Show on screen", "Show other menus" draws the others on the grid.

### Creating a menu from what opens it
- **What it starts as** is `MenuSeeds.seed(purpose, id, name)` (pure, `tst_MenuSeeds`), over the `Menu` schema's defaults (`ConfigManager.withDefaults`):

  | Purpose | Seed |
  |---|---|
  | `edge` (the default: `addMenu()`) | `placement: edge`, `open.onHover: true` |
  | `popout` | `placement: free`, `animation: fade`, `closeButton: true` |
  | `submenu` | `placement: free`, `animation: fade`, `closeButton: true` |
  | `free` | `placement: free`, `animation: fade`, `closeButton: true`, `freeAnchor.at: centre`, `close.onLeave: false`, `close.onOutsideClick: false` (opened by a bind with the pointer elsewhere, it stays until its close button, Escape or its bind closes it, and never holds the keyboard) |
- **Free menus start with a close button and without Close on outside click** (decided 2026-11-10: "go ahead with the default change. No option 1, it can take the keyboard immediatly"): `close.onOutsideClick` holds the keyboard while the menu is open (its `FocusGrab`, [Free menus](free-menus.md) › The window), so the windows behind couldn't be typed in. Only the seeds changed: the schema defaults (both off) and existing menus are as they were, and an edge menu's outside click closes it as before.
- **Layouts' New menu** (`MenusSection`) opens a `StyledContextMenu` of the four purposes, then `addMenu(purpose)`.
  - Each adds the menu to the draft, unsaved. `free` (Free, a floating menu) replaced "Opened by a keybind" (decided 2026-11-10: "opened by a keybind option needs to be replaced by free when adding new menus"): no keybind is recorded; once saved, a bind is added from its Opening section as for any menu.
- **A Submenu module's New submenu…** (a link under its `menu` field in `EditorInspector`, through `OptionsGroup.fieldAction`): `addSubmenu(moduleIndex)` adds a free menu to the same draft, sets the module's `menu` to it, then selects it and holds it open beside its parent (selecting it clears the parent's undo history, as any change of menu does: the `GridEditor`'s `scopeKey`). Everything stays in one draft, so nothing points at an unsaved menu from another editor.
- **The bar editor's New menu…** (a link under each edge menu picker in `WidgetInspector`: a widget's `popout.menu`, a Button's click `menu`): `OverlayManager.newMenuFor(zone, index, path)`.
  - It saves a new `popout` menu at once (`addSavedMenu` → `_commitNew`: the saved config plus that one item, through `ConfigManager.commit`). The menu draft takes it as saved (`ConfigDraft.adopt`), so it doesn't show as unsaved and a later save of the draft keeps it once.
  - It sets the field in the bar draft (`BarManager.updateWidgetProperty`, undoable; a nested field as its whole object), then opens the menu in Layouts as `editOpenedBy` does (`followLink`).
  - So the bar draft never points at an unsaved menu.
- **The pickers** (`x-options: menus`: a widget's `popout.menu`, a Button's click `menu`, a Submenu module's `menu`) label each menu by its name and placement ("Tools · Free", `SchemaField.optionLabels` with `MenusConfig.placementLabels`); the stored value is the id (decided 2026-11-10, review round 2: "Label + omit unusable").
  - A widget's `popout.menu` offers only `edge` and `free` menus (`x-menuPlacements: [edge, free]`, `MenusConfig.offeredIn`): a strip pushes the bars and windows inwards, so opened by hovering a widget it moves the bars as the pointer rests ("Bars must not move/redraw when making an action", review round 1), and on its edge takes the widget from under the pointer (`popoutMenuOf` would still open one). A menu it already names stays listed.
  - A Button's click `menu` offers every placement: a click toggles a strip as a bind does. A Submenu module's `menu` too: it shows any menu's modules in its submenu.
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
  - that menu's `MenuBody` (`submenu` set): its modules on a grid at the card size of the opening menu's screen and its own `moduleScale`;
  - their `host` is that menu's with `submenu: true` (no pin).
- In an integrated menu (no `SubPopout`) the row is dimmed and inert.
- How the `SubPopout` itself is placed and joined: see [Popout submenus](../popouts/submenus.md).

### Submenus: `placement: "free"` menus
- `MenusConfig.isFree`. It has no place on an edge; its own window is `FreeMenu` ([Free menus](free-menus.md)).
- Its edge, length, offsets and hover opening hide (`x-showIf`); its monitor (unless it opens at the cursor), pin and close buttons, colours, closing, `freeAnchor` and `animation` (with Scale) show. `placementOf` is null.
- The layouts editor draws just its grid (`MenuTarget`).
- Any other menu can be opened as a submenu too.
- `references(id)` lists the Submenu modules opening a menu; one opening the menu it's in is a problem.
- "Show on screen" on a free menu opens the first enabled `edge` menu with a Submenu module opening it (`submenuParentOf`, `previewParent`, held as the preview is). That menu's first such row opens it and holds it (`content/Submenu.previewed`). With no such menu, the free menu opens on its own, at its `freeAnchor`.
- A bar widget's `popout.menu` can open a free menu, at the widget (`popoutMenuOf`), and the Opening group offers a bar button and a keybind for it as for any menu (`OpenerButtons`).
