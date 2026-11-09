# Menus rework

> **Issue:** [Menus rework](../issues.md#menus-rework)
> **Status:** decided: placement split, free menus, transparent menus, shortcuts, rename with aliases (2026-11-09)

### Problem
An edge menu's `mode` (`floating | integrated | submenu`, `qml/config/schema/definitions/layout/EdgeMenu.yaml`) answers two questions at once: where the menu lives, and what opens it. So:
- `submenu` really means "a menu with no home", but it is named after one of the things that opens it.
- A menu wanted only as a bar widget's popout still needs an edge, a screen, an offset and hover settings it never uses.
- `EdgeMenusConfig.popoutMenuOf` can never open a submenu menu.

The goal (maintainer, 2026-11-09) is one multipurpose **Menus** concept: a `placement` of `edge | strip | free`; a `free` menu with its own window, which can be pinned over windows and stays under the popouts opened over it; an optional transparent background, so the cards read as separate tiles; shortcuts that create a menu from the place that opens it; and the section renamed `EdgeMenus` → `Menus`.

### Options
#### A. Split `mode` into `placement`, give free menus a host (chosen)
`placement: edge | strip | free` says where a menu lives; what opens it (hover, a widget, a bind, a Submenu row) stays separate. A `free` menu gets its own window and placement helper, so a widget popout, a bind and a Submenu row can all open it. Costs a migration (v103) and a rename migration (v104); every read of `mode` changes.
#### B. Keep `mode`, add a fourth value for popout-only menus
No migration, but the mixed meaning stays and grows: each opener would need its own value, and `submenu` menus still couldn't be widget popouts.

### Recommendation
A, in six stages, one PR each. The maintainer's decisions (2026-11-09):
- "Rename with aliases: `edgeMenu` keeps working for IPC, the CLI and binds; it is the last stage."
- "Pinned edge menus: only `free` menus stay visible under popouts. Every edge menu, detached ones included, keeps today's rule: it hides when covered and comes back afterwards."

### Items
1. **`mode` → `placement`, behaviour unchanged.** `EdgeMenu.yaml`'s `mode` becomes `placement` (`edge | strip | free`, default `edge`), its `x-showIf` rules follow; migration v103 maps `floating→edge`, `integrated→strip`, `submenu→free`. `isSubmenu` → `EdgeMenusConfig.isFree`; a `free` menu behaves exactly as `submenu` did (no host, opened only by Submenu rows). The popout claim kind `"submenu"` (`PopoutGeometry`, `SubPopout`, `PopoutClaim`) is unrelated and stays.
2. **The free-menu window.** `surfaces/edgemenu/FreeMenu.qml` (a `PopoutWrapperBase` in its own full-screen `PanelWindow`, masked to its box, layer Top, namespace `axiom-menu`, `LayerSlot` held, keyboard on demand, `FocusGrab` only unpinned with `close.onOutsideClick`, hosting a `SubmenuHost`); a pure `methods/FreeMenuPlace.qml` with its test (the opener's rect and bar edge, `freeAnchor`, the box, screen and reserved zones in; the clamped origin and slide direction out); schema `freeAnchor` (`centre | cursor | point`, x/y %) and `freeAnimation` (`fade | scale | slide`); `popoutMenuOf` opens free menus at the widget; binds and IPC at `freeAnchor`; a `PopoutClaim` keyed `"menu:"+id`; `EdgeMenuSync` with an optional trigger; a `LayerStack` entry with its tests, goldens and blur lists; a new free-menus page in the edge menus docs.
3. **Pinned free menus stay under popouts.** `PopoutGeometry.resolve`: a pinned free claim (`underlay`) never collides, with `tst_PopoutGeometry` rows; popouts draw above `axiom-menu`; a click on the menu closes an open popout and then reaches it; `EdgeMenuManager.canPin` allows free hosts. Dragging a pinned free menu is being specified again and moves to a later stage (2026-11-10).
4. **Transparent background.** `background: panel | none`, for `free` and `edge` (`none` forces detached, through a new detachedOf in the reader), never `strip`; with `none` only the cards draw, each with its shadow and blur piece; a shared `hosts/popout/CardMask.qml` masks input to the cards (`FreeMenu` and `EdgePopout`); crossing a gap closes only after `close.delay`, floored at about 150 ms.
5. **Creation shortcuts.** `EdgeMenuEditor.addMenu(purpose)` seeds `edge`, `popout`, `submenu` or `key` menus; Layouts' "New menu" offers the four; the Submenu module's inspector gets "New submenu…"; the bar editor's popout menu combo gets "New menu…" through a new newMenuFor(widget) in OverlayManager, saving the new menu at once.
6. **Rename `EdgeMenus` → `Menus`, with aliases.** Migration v104 (the section, keybind and Button `action: edgeMenu` → `menu`); `sections/Menus.yaml`; `EdgeMenusConfig` → `MenusConfig`, `EdgeMenuManager` → `MenuManager`, the host kind `edgeMenu` → `menu`, `surfaces/edgemenu` → `surfaces/menu`; IPC `menu` with `edgeMenu` forwarding, CLI `axiom menu` with `edge-menu` kept, the action table accepting `edgeMenu`; `ui/edgemenus.json` → `ui/menus.json`, read from the old name once; the edge menus docs to a menus folder.
