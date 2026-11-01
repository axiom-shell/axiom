# Grid canvas, drag layer and GridEditor

> **Files:** `components/views/Layouts/GridCanvas.qml`, `components/views/Layouts/CanvasModule.qml`, `components/views/Layouts/GridDragLayer.qml`, `components/views/Layouts/EntryListTarget.qml`, `components/views/Layouts/EntryListRow.qml`, `components/views/Layouts/EditorInspector.qml`, `components/views/Layouts/ModuleLibrary.qml`, `components/views/Layouts/ModuleChip.qml`, `services/ui/GridEditor.qml`, `components/methods/GridPlacement.qml`
> **Config:** whatever the edit target's draft holds (`Overlay.items[].layout.modules`, `EdgeMenus.items[].layout.modules`, screen layouts' `modules`)
> **Related:** [Layouts editor](layouts-editor.md), [Pages and grid](pages-and-grid.md), [Edge menu editing](../edge-menus/editing-submenus.md), [Growing and expanding](grow-expand.md)

The right side of the layouts editor: `GridCanvas` draws the selected page, menu or screen layout; `GridDragLayer` carries modules and list rows; `services/ui/GridEditor` turns drops, moves and resizes into plans and edits, with undo.

### GridCanvas: drawing
- Draws the selected page or menu at a scale it computes itself (not `Item.scale`).
- A lattice of unit squares (one `Canvas`) with room around the grid (`GridPlacement.canvasExtent`: a unit above/left, three below/right, or one past the screen), scaled to the area (`canvasFit`).
- `CanvasModule` tiles. Lattice squares and modules share `cellRadius`.
- For a menu, its whole screen around it, where the menu really sits on it (`screenBox`: `OverlayManager.menus.screenBoxOf`, `GridPlacement.screenBox` from `placementOf`):
  - a dashed outline, with the units outside it tinted (they'd scroll);
  - the screen edge as a faint accent bar with the menu's part solid;
  - a shaded band along it (`reservedDepth`, `GridPlacement.menuReservedDepth`, with a line where the windows start): the strip an integrated menu reserves, or the bars and border a floating one sits past.
- With "Show other menus" (`OverlayManager.menus.showingOthers`), the other enabled menus on that screen are drawn dimmed where they sit.
  - `ghosts`: `OverlayManager.menus.othersOn`, in screen px through `pxScale`, since their module size can differ.
  - They are not drop targets.
- A header with undo/redo at its left, the module count, a menu's arrows moving it along its edge (see [Edge menu editing](../edge-menus/editing-submenus.md)) and how it fits (per monitor for a page, along the edge for a menu).

### GridCanvas: alignment guides
Always on; all their geometry is `GridPlacement`'s (tested in `tst_GridPlacement`).
- The **frame** a module is aligned against (`GridEditor.guideFrame`, `GridPlacement.guideFrame`): the bounded grid (`GridEditor.area`, a screen layout), else the cover of the *other* modules (a page or a submenu: centred among the rest). An edge menu's is its screen along its edge (`GridEditor.screenBox`, `OverlayManager.menus.screenBoxOf`) and the other modules across it, so what's centred lines up with the screen's centre.
- **Centre cross** (`centreLines`, `centreGuides`): faint dashed accent lines over the tiles (the guides' `Canvas`, so a full page doesn't hide them), through the centre of the frame of every module: the screen's (screen layouts), the page's modules' bounds (what the overlay centres the page on), an edge menu's screen along its edge and its modules across it.
- **Smart guides** while carrying or resizing (`guides`, `alignments`): a line wherever the landing place's start, end or centre on an axis equals another module's (at its previewed place), running over both; stronger where it's centred in the frame. Drawn by the same `Canvas` as the centre cross. The drag layer's `landingMembers` says which previewed places are the ones moving.
- **Margins** on the one selected module, while nothing's carried (`margins`, `canvasMargins`): a line and its length in cards (`GridPlacement.cards`) to each frame side with room, accent where both sides on that axis match. An edge menu's screen side can fall between units: that length is rounded and shown with `≈`.
- The inspector's **Centre horizontally / vertically** buttons (`GridEditor.planCentre` / `centreSelection`, `GridPlacement.centredIn`) centre the module or group in its frame, pushing as a move does. Dimmed (still hoverable, to say why) when it's centred, when there's no room, or when it'd sit between units (an odd difference, where a fine grid helps, or an edge menu's screen centre off its lattice: its grid offset); hidden with no frame.

### GridCanvas: interaction
- Drag a tile to move it: onto a module of the same size to swap, onto others to push them aside.
- Drag any edge or corner to resize from that side (`GridPlacement.resizeFrom`), snapping to units, with a size readout.
- Other tiles slide to where the drop or resize would put them, from the drag layer's `previewPlaces`.
- The landing outline is red only where it can't be made.
- Keyboard, with the canvas focused (a click, a selection):
  - Ctrl+Z; Ctrl+Shift+Z / Ctrl+Y.
  - On the selected module: arrows (`GridEditor.nudge`), Shift+arrows (`grow`, from the bottom right), Delete.
  - Escape deselects; with nothing selected it passes on and closes the overlay.

### Inspector
- Shows the selected module's options (`OptionsGroup`) and its Size (steppers in units, shown as cards: `GridPlacement.cards`).
- Else the `ModuleLibrary`: `ModuleChip`s to drag, or click to add at `firstFree`.
- A group selected shows its count and Remove instead of the library.

### GridDragLayer
- Payloads:
  - `module-add { type, w, h }`: from the library, at the module's default size;
  - `module-move { index, group }`;
  - the lists' `page-move` / `tool-move` / `menu-move`.
- Targets:
  - **The canvas** (`targetKind: "grid"`):
    - `placeAt(point, drag, grab)`, snapped to units. A moved module keeps the unit it was grabbed by under the pointer; a new one is held by its middle.
    - `hoverPlace` changes only when the snapped place does (`GridPlacement.samePlace`, set from each move in `_updatePlace`), so a move within a unit re-plans and redraws nothing: `hoverPlan`, the tiles' rects and the guides all follow it.
    - `hoverPlan` is the editor's plan for a drop there. `shownPlan` is what the canvas shows and the drop applies as is: the hover plan while it's valid (a no-op too, back over the module's own place) or off the grid, else the last valid one of this drag, so a place with no room (pushes only go down: a bounded grid runs out of rows) leaves the tiles still instead of gliding back and forth. The ghost turns red ("Doesn't fit here") only when nothing valid came before.
    - With a tile's `resizePlan` it gives `previewPlaces` / `landingPlace` / `landingValid`.
    - The carried tile (faded, under the landing rectangle) jumps with it; the others glide out of the way (`Glide`, `GridCanvas`).
  - **`EntryListTarget`s** (`"list"`): `takes(drag)`, `indexAt`, `dropRequested`, which reorder their own rows. Each row is an `EntryListRow` carrying its list's `moveKind`.
- A `TrashTarget` at the bottom of the canvas shows while a module is carried. Dropped there, it goes, with its group (required ones stay).
- For a grid of something other than overlay modules (a custom widget's elements, `views/CustomWidgets/ElementEditorLayout`), three hooks name what it holds: `describe(type)` → `{ icon, label }`, `sizeLabel(w, h)` (a tile's size while resized; cards by default) and `countLabel(n)` (the canvas's count and a carried group; modules by default).

### GridEditor (`services/ui/GridEditor`, non-singleton)
The canvas pieces name no service: they edit through `dragLayer.editor`.
- Holds one grid of modules and its `selected` index.
- Edits: `addModule` / `moveModule` / `resizeModule` / `duplicateModule` / `removeModule` / `updateModuleProperty`.
- Checks: `canAdd` / `canMove` / `canResize`, and `problemsFor(modules, name, area)`.
- `factory` (`{ make(type, place), size(type) }`, null for overlay modules) makes and sizes the entries of another kind of grid (a custom widget's elements); a library key `CustomWidget:<id>` adds that custom widget's module (`CustomWidgetsConfig.splitKey`).

### Plans
- Drops, moves and resizes are first a plan: `planAdd` / `planMove` / `planResize` → `{ kind, index, type, place, places, valid, noop }`, made by `applyPlan`.
- A new module dropped on a free cell takes the most of its default size that fits there, down to its `minSize` (`GridPlacement.fitPlace`).
- Otherwise (and for a move or resize onto modules) it pushes what it lands on along `pushDir` (`GridPlacement.push`, cascading):
  - down on a page;
  - along an edge menu's edge: down a side menu, right along a top or bottom one.
  - Refused when that leaves a bounded grid.
- A move exactly onto a same-size module swaps them.

### Group selection
- Several modules selected together (`group`): a box dragged on the canvas background, Shift adding, or Shift/Ctrl+click.
- API: `selectGroup` / `toggleSelected` / `isSelected` / `selection()`.
- They move as one (`planMoveGroup`, `GridPlacement.pushGroup`; the drag's `module-move` payload carries the `group`), nudge with the arrows, and go with `removeSelection`.

### Undo, normalizing and bounded grids
- Every edit snapshots the modules first (plus the owner's `snapshotExtra`: an edge menu's offset) for `undo` / `redo`.
  - 50 deep; typing in one field is one step.
  - Cleared when the scope changes and by the owners' load/reset (`clearHistory`).
- Each edit keeps the selection on its module (or group) and normalizes the grid, so a place left of or above it makes room there.
  - On a `hold` axis a gap before the modules stays and only negative places are shifted back. That is a whole-edge menu's axis along its edge, since it starts at the edge's start whatever its modules reach.
  - `shifted(shift, boundsBefore)` tells the owner; EdgeMenuEditor uses it to keep a menu's modules on their cells.
- With an `area` `{ cols, rows }` the grid is bounded instead:
  - places stay absolute and inside it;
  - new modules go to `GridPlacement.firstFreeIn`;
  - `problemsFor` flags one outside it.
- Required modules (`canRemove`) are never removed or duplicated, and a grid missing one is a problem.

### Owners
- `OverlayManager.layout`, `OverlayManager.menus.layout` and each `ScreenLayoutEditor`'s `layout` (`LockManager.editor`, `GreeterManager.editor`, bounded by the layout's `columns` × `rows`) each own one.
- Each points `modulesOf` at the selected page's or menu's modules, or the lock screen's.
