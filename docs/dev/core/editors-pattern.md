# Editors pattern

> **Files:** `qml/services/core/ConfigDraft.qml`, `qml/services/ui/EditsManager.qml`, `qml/components/views/base/BaseView.qml`, `qml/components/reusable/DragLayer.qml`; editor managers `qml/services/ui/{SettingsManager,BarManager,OverlayManager}.qml`, `qml/services/ui/MenuEditor.qml`, `qml/services/apps/CustomWidgetsEditor.qml`, `qml/services/compositor/{KeybindEditor,MonitorManager,WindowRulesEditor}.qml`, `qml/services/ui/ScreenLayoutEditor.qml`
> **Config:** whichever path the editor drafts; layout prefs in `~/.local/state/axiom/ui/editors.json`
> **Related:** [Config manager](config-manager.md), [Bar editor](../bar/bar-editor.md), [Layouts editor](../overlay/layouts-editor.md), [Grid canvas](../overlay/grid-canvas.md), [Monitors](../hyprland/monitors.md), [Keybinds](../hyprland/keybinds.md), [Shared UI pieces](shared-ui-pieces.md)

The settings, bar, layouts, keybinds and monitors editors share one shape; a new editor follows it.

### Draft
- The manager owns a `ConfigDraft` of its config path.
  - An editor that is one part of a page's manager is a non-singleton the manager holds, named `*Editor`: the layouts editor's menus are `OverlayManager.menus` (`MenuEditor`), the Keybinds page's binds `KeybindManager.editor` (`KeybindEditor`, beside the page's view state `KeybindManager.page`), its screen layouts `ScreenLayoutEditor`s (`DesktopManager.editor`, …).
- Mutate `draft.local` in place, then `changed()`. It re-clones next tick so bindings see it; `isDirty` compares the data whatever its key order (`Utils.deepEqual`).
- Editors (the settings page too) show unsaved edits live through `ConfigManager.setPreview`, never by changing `ConfigManager.config`.
- Save merges onto the latest config (`commit`, which may refuse: the draft stays dirty; a save axiom refuses later makes it dirty again through `ConfigManager.saveRefused`, and its `refused` signal has the editor preview the edits again). Discard (shown only while dirty) reloads.
- Typed text in a text or number box reaches the draft only on Enter, focus loss or Save, but shows Save at once: the box holds `EditsManager.typingField`, `SaveResetActions` (and `saveAll()` / `discardAll()`) commit or drop it first. Half-typed commands and paths never reach the preview.
- An item another editor's shortcut saves at once into a list section (the bar editor's New menu…: the saved config plus that item) joins the draft through `ConfigDraft.adopt(item)`, added to both its saved and its local copy, so it shows saved and a later save keeps it once ([editing and submenus](../menus/editing-submenus.md) › Creating a menu from what opens it).
- `ensureLoaded()` on page open reloads only a clean draft. Settings and Keybinds use `ConfigDraft.loadIfStale()`, which also skips one already holding the current config, since pages are rebuilt on every open ([streamed building](streamed-building.md) › Editors reopening).

### Selection
- Lives in the manager (`selectedBarIndex`, `selectedViewIndex`, `selectedMenuIndex`, `selectedProfile`, `KeybindManager.editor.selectedIndex`, …).
- Changes through `select*()`, which clears or fixes what hangs off it.
- Add/remove/move functions keep it on the right entry.

### Undo
- An editor that undoes owns an `EditHistory` (`qml/services/ui/EditHistory`): `snapshot` / `restore` hooks over what its edits change (with the selection), `record(fieldKey)` before each edit (the same key as the step before joins it: typing, a stepper), or `take()` then `push(snap)` once an edit turns out to change something; `undo` / `redo`, `canUndo` / `canRedo`, `clear()` when the draft reloads; 50 steps. `GridEditor` (the layouts editor, the desktop, lock screen and custom widget grids) and `BarManager` use one; their buttons are `UndoRedoButtons`. A `GridEditor` clears its history when its `historyKey` changes (`scopeKey` unless set: the custom widgets editor sets the definition's id, so one history spans a definition's screens and its snapshots carry the whole definition).

### Page
One shape and one vocabulary for every tool page ([recipe](../../recipes/tool-page.md)): `[ListPane] [WorkArea over Inspector | Inspector]`, built on `views/base/`.
- **Pieces.** A `BaseView` (`pageHeight`, `cardPageWidth`, `sideWidth`, `editorWidth`; `pageWidth` = side + editor + gap, `inspectorWidth`, `listWidth`: every tool page is `pageWidth` wide in the overlay, so switching pages never changes the box). Each pane is a `ToolPane` (a `TitledCard`: title = the kind of pane, never the selection's name; fixed slots in this order: header, `pinned`, tabs, `toolbar`, scrolling body, `footer`). A `ToolBar` holds search, controls and a count; a `ListSection` titles a group of rows (collapsible, with a hint line); a `WorkArea` holds the canvas with its undo, tools, status line (the idle hint above the status row) and Save; `GroupColumns` flows an inspector's `FieldGroup`s into columns like a Settings card, `Style.cardGap` apart down and across; a box of cards that scrolls (a `TitledCard`'s body, an inspector's own box) puts them in a `CardScroll`, so every box has the settings page's gutter and gap; an `InspectorHeader` names the selection and carries the standard actions.
- **Select** a row (the accent container): the inspector shows it; The inspector's close clears it, and Escape on a row does too where the list opts in (`escapeClears`, for a list that can have nothing selected); a list that always has a selection leaves Escape to the host. List rows take keyboard focus (Up/Down move, Enter selects, Delete runs the row's remove unless the page blocks it, Tab goes through the row's own controls (`leading`, then its actions), then out of the list).
- **Edit** in the inspector: `FieldGroup`s of `SchemaPropertiesForm`, grouped by `x-group`. Each group is the settings page's card (`FieldGroup`: outlined surface box, the title, description and chevron at the top, rows inside the card's padding; the fold is the card's own and never saved; a card with no title has no header). Inside a card a row is indented only under the row its value depends on, a tree of any depth from the schema's conditions (`RowTree`); extra options are a fold row inside the card (`FoldFormRow`), as the login screen card's Settings fold. Content that isn't rows (a list, preview, notice) is a card too. A card whose rows are all hidden hides.
- **Add** with an `AddEntryButton` under the list. **Remove** with the row's × (`RowAction`, quiet, red on hover) and the inspector header's remove (`danger`). **Reorder** by drag, said once in the `ListSection`'s hint.
- **Save/Discard** are page-wide and always in the header of the top-right pane (the work area, or the inspector where there is none); undo and redo come first among the work area's tools, at the right of its header before Save (`CardHeader.trailingTools`). The bar editor saves in its Widgets board (top right), though most of what it saves (the bar's settings) is edited in the left pane: the board's status line says "Saves this bar: its settings and its widgets" and the left pane's tabs holding unsaved fields carry a dot (`ToolPane.tabMarked`, `BarManager.changedTabs`).
- **Search** in the `ToolBar`, with a count; nothing found shows the `"results"` empty state with a Clear action. Help is the work area's status line while nothing is selected, with a "?" for the long form.
- **Empty states** differ by words and action, not only by icon: `"none"` (the page's icon, "No … yet", how to add), `"select"` ("Select a … to edit it") and `"results"` ("Nothing matches", Clear).
- "Can't save yet" (`IssueList`) shows when `problems` block Save.
- With a `WorkArea` the inspector is hidden while nothing is selected (the bar editor's widget inspector; the layouts editor's, which then holds the module library), the status line carrying the instruction.
- Pane geometry is in whole pixels. The bar, layouts and keybinds editors are on this; the pages not yet converted keep their own panes until then.

### Unsaved reminders (`EditsManager`)
- Drafts survive leaving a page or closing the overlay (bar and menu edits stay live through previews), so nothing blocks closing.
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
