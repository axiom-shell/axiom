# Editors pattern

> **Files:** `services/core/ConfigDraft.qml`, `services/ui/EditsManager.qml`, `components/views/base/BaseView.qml`, `components/reusable/DragLayer.qml`; editor managers `services/{SettingsManager,BarManager,OverlayManager,EdgeMenuManager,KeybindManager,MonitorManager}.qml`, `services/ui/ScreenLayoutEditor.qml`
> **Config:** whichever path the editor drafts; layout prefs in `~/.local/state/axiom/ui/editors.json`
> **Related:** [Config manager](config-manager.md), [Bar editor](../bar/bar-editor.md), [Layouts editor](../overlay/layouts-editor.md), [Grid canvas](../overlay/grid-canvas.md), [Monitors](../hyprland/monitors.md), [Keybinds](../hyprland/keybinds.md), [Shared UI pieces](shared-ui-pieces.md)

The settings, bar, layouts, keybinds and monitors editors share one shape; a new editor follows it. (Rule: AGENTS.md › Services, "Editors".)

### Draft
- The manager owns a `ConfigDraft` of its config path.
- Mutate `draft.local` in place, then `changed()`. It re-clones next tick so bindings see it; `isDirty` is a JSON compare.
- Structural editors show unsaved edits live through `ConfigManager.setPreview`.
- Save merges onto the latest config (`commit`, which may refuse: the draft stays dirty). Discard (shown only while dirty) reloads.
- Typed text in a text or number box reaches the draft only on Enter, focus loss or Save, but shows Save at once: the box holds `EditsManager.typingField`, `SaveResetActions` (and `saveAll()` / `discardAll()`) commit or drop it first. Half-typed commands and paths never reach the preview.
- `ensureLoaded()` on page open reloads only a clean draft. Settings and Keybinds use `ConfigDraft.loadIfStale()`, which also skips one already holding the current config, since pages are rebuilt on every open ([streamed building](streamed-building.md) › Editors reopening).

### Selection
- Lives in the manager (`selectedBarIndex`, `selectedViewIndex`, `selectedMenuIndex`, `selectedProfile`, `KeybindManager.selectedIndex`, …).
- Changes through `select*()`, which clears or fixes what hangs off it.
- Add/remove/move functions keep it on the right entry.

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
- `EditsManager` also keeps how the editors lay themselves out, past their pages (`state/editors.json`): `libraryGrouped` (both libraries) and `barStacked`.
- And, in memory, where each panel was scrolled to (`scrollOf` / `rememberScroll`): a page's `TitledCard` takes a `scrollKey`, an inspector's ScrollView a `reusable/ScrollMemory` keyed by its selection, so they come back where they were when the overlay reopens.

### Text fields
- Fields bound to draft values follow the push pattern (AGENTS.md › QML pitfalls).
  - Set the text on selection change, and on draft change unless focused.
  - Write on `textEdited` (`LayoutsPanel`, `Monitors`), or on focus loss only if `typed` (`BindInspector`, `StyledComboEntry`).

### Drag
- A `reusable/DragLayer` subclass covers the page and draws the ghost.
  - `BarDragLayer`: targets are the `SectionLane`s, plus a `TrashTarget` away from the bar's edge that takes a `move` and removes the widget. Payloads are `{ kind: "move" | "add", zone, index, type, compact }`.
  - `GridDragLayer`: see [Grid canvas](../overlay/grid-canvas.md).
- Draggables are `DragArea`s (`dragLayer`, `payload`) or `DragChip`s.

### Inspector
- `InspectorHeader` + a `KeyedLoader` keyed on the selection.
  - With a selection it builds an `OptionsGroup` (widget/module `properties`).
  - With nothing selected, a library of `DragChip`s in a `TypeLibrary`.
