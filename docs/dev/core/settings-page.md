# Settings page

> **Files:** `components/views/Settings/Settings.qml`, `components/methods/SchemaLayout.qml`, `components/methods/ColumnSplit.qml`, `components/views/Settings/` (`SettingsGroupCard`, `EntryListCard`, `FoldingCard`, `SettingsSidebar`, `SettingsContent`), `components/forms/`, `components/reusable/ScrollMemory.qml`, `services/ui/SettingsManager.qml`
> **Config:** every section with settings (`x-settings` not false); fold state in `~/.local/state/axiom/ui/settings.json`
> **Related:** [Schema annotations](schema-annotations.md), [Editors pattern](editors-pattern.md), [Shared UI pieces](shared-ui-pieces.md)

How the schema becomes the settings page: layout, cards, folding, sidebar and search.

### From schema to rows
- `methods/SchemaLayout` turns the schema into categories → groups → rows.
- The cards are built from the schema, the category and the search only. What a card's showing depends on config (`x-showIf`) reaches the page as strings (`Settings._categoriesKey`, `SettingsContent._shownKey`), so they notify only when the answer changes: a new array on every edit rebuilds every card, flashing the page.
- Only this page builds its own rows. Flat objects (array items, widget/module options, a bar's fields) render through `forms/SchemaPropertiesForm`.
- Streamed (`StreamedLoader`, [streamed building](streamed-building.md)): the sidebar, and each card of a category, on opening the page and on switching category (`always`), so a category shows at once and its cards fill in, top to bottom. Search results and Changed from default build at once (`listing`), so typing doesn't fade them in again. The columns settle as the cards arrive (the 150 ms quiet spell below). `SchemaPropertiesForm` streams its fields the same way wherever it's used.
- An `array` of objects renders as an add/remove/reorder list (`SchemaObjectArray`, items `SchemaArrayItem`).
- Text and number boxes (`forms/SchemaTextField`, `SchemaNumberField`'s value box) show their edit as unsaved on the first keystroke and apply it only on Enter (Ctrl+Enter when multiline), focus loss, teardown or Save; a suggestion click or a folder picked with Browse (`x-control: "folder"`, [File picker](file-picker.md)) commits at once. Each live apply re-evaluates the readers (~35 ms of JS before layout), and half-typed values had side effects: a font re-shaped every text, a notes folder ran `find` on `/`, a widget's label command ran per keystroke.
  - Every page: the box holding typed text registers with `EditsManager.holdTyping`, which shows Save and Discard in its window (`SaveResetActions`); Save commits it first (`EditsManager.commitTyping`), Discard drops it.
  - This page also puts each keystroke in its draft (`valueTyped` → the form's `typed` → `SettingsManager.setDraftValue`), so the card's unsaved dot shows too; `_merged` diffs afresh, since Save's commit lands in place.

### Cards
- Generated cards are `settings/SettingsGroupCard`.
- A section with `x-cardPerField` (Theme integrations) makes a card per field, after one with the section's description; its switches are relabelled "Enabled" (`row.label`), the card carrying the field's title and description.
- The Dock and OSD list cards are `EntryListCard`s:
  - entries as tabs
  - a screen picker with presets: by default an edge's middle or the bottom edge's ends, with `spotOf` reading `edge`/`position`
  - Show/Duplicate/Delete
  - the entry's form
  - `entryContent` for extras such as the dock's pinned apps.
- Both sit on `FoldingCard`: a fold header (section line, heading, unsaved dot, chevron, `headerExtras`) and a `FoldingColumn` body.
- Status cards (Hyprland, Idle, self-update, chat providers, onboarding) are `FieldGroup`s with a `StatusChip` in `headerExtras`.

### Discarding
- Three sizes: the page header's Discard (every unsaved edit, `SettingsManager.resetChanges`), a generated card's Discard (shown while it has any: its rows only), and a field's unsaved dot (click it: that edit only). The last two go through `SettingsManager.discard(paths)`, dropping text typed in that card or field (`EditsManager.discardTypingIn`). The list cards (docks, OSDs, calendar accounts) have only the page's.
- A field's small reset button is different: it sets the schema default (an edit, which Discard undoes). The dot and reset sit right after the field's label, on its line (`FieldHeader.trailing`).

### Folding
- Clicking a card's header folds it (`SettingsManager.collapsed`, by group key, saved to `~/.local/state/axiom/ui/settings.json`). Search results never fold.

### Columns
- Cards fill two newspaper columns in order: the first k on the left, the rest on the right. `methods/ColumnSplit` picks k from the cards' measured heights so both columns end as close together as they can.
- A wide card (`x-cardWide` on a hand-built card, `x-wide` on a field of a generated one: [Schema annotations](schema-annotations.md)) spans both columns and cuts the cards into runs, each split on its own; it starts below the taller column of the run before it (`ColumnSplit.runs` / `splits` / `place`).
  - Wide cards ahead of every narrow card stay at the top; any later one goes to the bottom (`SchemaLayout.categoryGroups`), so a wide card never cuts the columns partway down. The sidebar lists the cards in that order.
  - A narrow card alone in its run (between wide ones, or a category's only card) spans both columns too, rather than leave half the page empty.
- Cards follow their heights live (a folding card moves the ones below it), but the splits only change while a block is settling: after it's built (a new category or search), resized, or after Fold all. They are fixed once no height has changed for 150 ms (a literal: `animNormal` is 0 with motion off, which would fix them before cards load), so folding one card never moves cards across columns.

### Sidebar and jumping
- The sidebar is `SettingsSidebar`: a `TitledCard` of `ListEntryRow`s, with search in its header.
- It lists the selected category's shown cards (`SettingsContent.shownGroups`, one per title) under its row.
  - They sit in a `FoldingColumn` that holds the links it opened with while it folds shut (by then `cardLinks` is the next category's).
- Clicking a card link calls `SettingsManager.jumpTo(key)`, which unfolds the card, keeps the jump as `pendingJump` and emits `jumpRequested`.
  - The content makes the jump once the card is laid out (`SettingsContent._takeJump`): at once, after the unfold animation, or when its block settles (the page or category was just built). A jump made before the page exists still lands.
  - It scrolls to the card (`TitledCard.scrollTo`) and outlines it in the accent for a moment (`FlashOutline`); a jump to a setting (`row`) centres and outlines that row instead (`SettingsGroupCard.rowItem`).
- The sidebar ends with **Changed from default** (`SettingsManager.changedOnly`): every setting whose draft value differs from its schema default (`nonDefaultPaths`, against `defaults`, limited to settings rows in the sections the page shows), from every category, listed like search results (`SettingsContent.listing`).
  - The set is taken when the list is asked for (`SettingsManager.showChanged`, into `changedSet`; clicking it again retakes it), not followed, so a row put back to its default stays until the list is asked for again, and edits don't rebuild the cards. A search narrows it further.

### Scroll memory
- Each category keeps where it was scrolled to (`TitledCard.scrollKey` `"Settings/<category>"`, `reusable/ScrollMemory`), across category switches and the overlay closing; search and the changed list start at the top. The sidebar keeps its own.
- A jump cancels a restore still waiting for the page to grow.

### Transitions and search
- A new category, or entering/leaving search, fades the content in, sliding from the side of the sidebar it was picked from (`_pageIndex`).
- Search results are grouped by category (`blocks`): a heading with the category's icon, then its own two columns.

### Opening it from elsewhere
- `SettingsManager.openSetting(path, link)` opens the page on the card showing a setting, object or section (`"Appearance.font.size"`, `"Calendar"`), found by `SchemaLayout.locate` (cached per path in `SettingsManager.locate` until the schema or the sections shown change), and jumps to it. So callers don't depend on category names or card keys.
  - `link` true: followed from another overlay page (`ShellManager.followLink`), which the navigator then offers to go back to. Services opening it from outside (a notification, the launcher) leave it off.
  - In the schema, `x-link` puts such links under fields and on widget/module types (`SettingsLink`, `FieldLinks`: [Schema annotations](schema-annotations.md)); `x-links` puts page links in a category's header.
- The launcher's `/config <setting>` lists **Show in settings** last, which calls `openSetting`.
- A category has no IPC; for testing use a temporary `IpcTarget` (AGENTS.md › Running / reloading).
