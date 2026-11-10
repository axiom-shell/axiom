# Editors pattern

> **Files:** `qml/services/core/ConfigDraft.qml`, `qml/services/ui/EditsManager.qml`, `qml/components/views/base/BaseView.qml`, `qml/components/reusable/DragLayer.qml`; editor managers `qml/services/ui/{SettingsManager,BarManager,OverlayManager}.qml`, `qml/services/ui/EdgeMenuEditor.qml`, `qml/services/apps/CustomWidgetsEditor.qml`, `qml/services/compositor/{KeybindEditor,MonitorManager}.qml`, `qml/services/ui/ScreenLayoutEditor.qml`
> **Config:** whichever path the editor drafts; layout prefs in `~/.local/state/axiom/ui/editors.json`
> **Related:** [Config manager](config-manager.md), [Bar editor](../bar/bar-editor.md), [Layouts editor](../overlay/layouts-editor.md), [Grid canvas](../overlay/grid-canvas.md), [Monitors](../hyprland/monitors.md), [Keybinds](../hyprland/keybinds.md), [Shared UI pieces](shared-ui-pieces.md)

The settings, bar, layouts, keybinds and monitors editors share one shape; a new editor follows it. (Rule: AGENTS.md › Services, "Editors".)

### Draft
- The manager owns a `ConfigDraft` of its config path.
  - An editor that is one part of a page's manager is a non-singleton the manager holds, named `*Editor`: the layouts editor's edge menus are `OverlayManager.menus` (`EdgeMenuEditor`), the Keybinds page's binds `KeybindManager.editor` (`KeybindEditor`, beside the page's view state `KeybindManager.page`), its screen layouts `ScreenLayoutEditor`s (`DesktopManager.editor`, …).
- Mutate `draft.local` in place, then `changed()`. It re-clones next tick so bindings see it; `isDirty` compares the data whatever its key order (`Utils.deepEqual`).
- Editors (the settings page too) show unsaved edits live through `ConfigManager.setPreview`, never by changing `ConfigManager.config`.
- Save merges onto the latest config (`commit`, which may refuse: the draft stays dirty; a save axiom refuses later makes it dirty again through `ConfigManager.saveRefused`, and its `refused` signal has the editor preview the edits again). Discard (shown only while dirty) reloads.
- Typed text in a text or number box reaches the draft only on Enter, focus loss or Save, but shows Save at once: the box holds `EditsManager.typingField`, `SaveResetActions` (and `saveAll()` / `discardAll()`) commit or drop it first. Half-typed commands and paths never reach the preview.
- An item another editor's shortcut saves at once into a list section (the bar editor's New menu…: the saved config plus that item) joins the draft through `ConfigDraft.adopt(item)`, added to both its saved and its local copy, so it shows saved and a later save keeps it once ([editing and submenus](../edge-menus/editing-submenus.md) › Creating a menu from what opens it).
- `ensureLoaded()` on page open reloads only a clean draft. Settings and Keybinds use `ConfigDraft.loadIfStale()`, which also skips one already holding the current config, since pages are rebuilt on every open ([streamed building](streamed-building.md) › Editors reopening).

### Selection
- Lives in the manager (`selectedBarIndex`, `selectedViewIndex`, `selectedMenuIndex`, `selectedProfile`, `KeybindManager.editor.selectedIndex`, …).
- Changes through `select*()`, which clears or fixes what hangs off it.
- Add/remove/move functions keep it on the right entry.

### Undo
- An editor that undoes owns an `EditHistory` (`qml/services/ui/EditHistory`): `snapshot` / `restore` hooks over what its edits change (with the selection), `record(fieldKey)` before each edit (the same key as the step before joins it: typing, a stepper), or `take()` then `push(snap)` once an edit turns out to change something; `undo` / `redo`, `canUndo` / `canRedo`, `clear()` when the draft reloads; 50 steps. `GridEditor` (the layouts editor, the desktop, lock screen and custom widget grids) and `BarManager` use one; their buttons are `UndoRedoButtons`.

### Page
- A `BaseView` with sizes `pageHeight`, `cardPageWidth`, `sideWidth`, and `editorWidth` for the main area beside it.
- A `TitledCard` on the left holds, in order:
  1. A list of `ListEntryRow`s (icon, name, badges, unsaved dot from `…Changed(index)`, `RowAction`s) and an `AddEntryButton`.
  2. The selected entry's fields: `FieldGroup`s of `SchemaPropertiesForm`, grouped by `x-group`.
  3. "Can't save yet" (`IssueList`) when `problems` block Save.
- Save/Discard are page-wide, so they sit top-right like Settings: on the right-hand top card (`SectionsBoard`'s header, or `GridCanvas`'s through `LayoutsEditorLayout`). The left panel has `showActions: false`.

### Unsaved reminders (`EditsManager`)
- Drafts survive leaving a page or closing the overlay (bar and edge menu edits stay live through previews), so nothing blocks closing.
- `EditsManager.unsaved` lists the pages (view types) with dirty drafts.
  - The navigator dots their tabs.
  - While another page has some, it shows Save all / Discard all after its arrows (`saveAll()` / `discardAll()`).
  - Both skip `separate` pages: Monitors, which applies with a keep/revert step.
- A new editor adds its manager to both lists.
- `EditsManager` also keeps how the editors lay themselves out, past their pages (`state/editors.json`): `libraryGrouped` (both libraries) and the Keybinds editor's folded sections.
- And, in memory, where each panel was scrolled to (`scrollOf` / `rememberScroll`): a page's `TitledCard` takes a `scrollKey`, an inspector's ScrollView a `reusable/ScrollMemory` keyed by its selection, so they come back where they were when the overlay reopens.

### Text fields
- Fields bound to draft values follow the push pattern ([qml-pitfalls](qml-pitfalls.md)).
  - Set the text on selection change, and on draft change unless focused.
  - Write on `textEdited` (`LayoutsPanel`, `Monitors`), or on focus loss only if `typed` (`BindInspector`, `StyledComboEntry`).

### Drag
- A `reusable/DragLayer` subclass covers the page and draws the ghost.
  - `BarDragLayer`: targets are the `SectionLane`s, plus a `TrashTarget` away from the bar's edge that takes a `move` and removes the widget. Payloads are `{ kind: "move" | "add", zone, index, type, compact }`.
  - `GridDragLayer`: see [Grid canvas](../overlay/grid-canvas.md).
- Draggables are `DragArea`s (`dragLayer`, `payload`) or `DragChip`s. A board of chips that wrap (the bar editor's `Flow` lanes) finds its drop index on both axes.

### Inspector
- `InspectorHeader` + a `KeyedLoader` keyed on the selection.
  - With a selection it builds an `OptionsGroup` (widget/module `properties`).
  - With nothing selected, a library of `DragChip`s in a `TypeLibrary`.
