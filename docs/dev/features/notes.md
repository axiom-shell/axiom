# Notes

> **Files:** `services/apps/NotesManager.qml`, `config/NotesConfig.qml`, `components/content/Notes/Notes.qml`, `components/content/parts/notes/NoteEditor.qml`, `components/content/parts/notes/NoteBlock.qml`, `components/content/parts/notes/NoteBrowser.qml`, `components/methods/NoteMarkdown.qml`
> **Config:** `Notes.*` (reader `NotesConfig`)
> **Related:** [Launcher](launcher.md), [Edge menus](../edge-menus/overview.md), [Writing modules](../overlay/writing-modules.md)

Notes are Markdown files edited in place by the Notes overlay / edge-menu module, with shared documents, a block editor, a file browser and search.

### Storage
- Notes are Markdown files in `NotesConfig.directory` (the `Notes.directory` setting).
  - Empty means `Paths.defaultNotesPath` (`~/.local/share/axiom/notes/`).
  - A linked folder is never created.
- Paths are relative to that folder. `clean()` refuses any path that leaves it.
- `allNotes` (from a `find`) feeds the `notes` `x-options`.

### Shared documents
- `acquire(path)` returns a shared, reference-counted document:
  - `text`;
  - `edit(text)`, which saves 600 ms later;
  - `flush()`.
- Modules showing the same note therefore stay in sync.
- `release(path)` flushes.
- A document is read at once and saved and watched through axiom (`FileManager.write` / `watch`; a save makes the note's missing folders). A change on disk reloads it, unless it has edits waiting, in which case the edits win; its own saves don't count as changes.

### File operations
- `createNote` / `createFolder` / `rename` / `trash` run argv processes.
  - Trash uses `gio trash`, falling back to `rm` behind a confirm.
- They emit `moved` / `removed` for the modules showing those notes.

### The editor (`parts/notes/NoteEditor`)
**Blocks:**
- Blocks come from `methods/NoteMarkdown`.
  - It is lossless: `serialize(parse(t)) === t`.
  - Edits touch only their own lines.
- A block is either:
  - a paragraph, split at blank lines (the blank lines stay with the paragraph above; a code fence is never split); or
  - a task line with a checkbox.

**Re-parsing:**
- Blocks are modelled by count, and re-read in place only on structural edits (`needsReparse`). Structural edits are:
  - Enter;
  - Backspace / Delete across blocks;
  - toggles and the toolbar;
  - typing `- [ ] `, or typing text after a blank line.
- Never on every keystroke.
- Every structural edit re-parses (`_normalize`), so the blocks are always what `parse()` would give.

**`NoteBlock`:**
- It shows its Markdown rendered (`Text.MarkdownText`), unless it's focused or holds the find match.
- Its clickable parts are `MouseArea`s. These accept the press, so the editor's background `MouseArea` (which focuses the note's end) never sees it.
  - This matters because inside a `Flickable` an exclusive-grab `TapHandler` gets cancelled, and a passive one lets the press through.

**Scrolling:**
- `ensureVisible(block, pos)` keeps the cursor (or a find match) in view after the blocks are laid out (`Qt.callLater`, then the column's `forceLayout()`): a structural edit reloads every block and adds new ones at the end, whose `y` is stale until then.
- A `ScrollMemory` keyed by the note's path keeps where each note was left (`EditsManager`, in memory), so reopening it comes back there; a reload from disk keeps the place, and so does a rename (the key is the path the note was opened at, set when the note changes, not bound to it). A jump to a line or a match cancels the restore.

**Find:** Ctrl+F finds within the note (`NoteEditor.find` / `endFind`).

### Browser and search
- `NoteBrowser` walks the folder with a `FolderListModel`.
- Its search field lists `NotesManager.search(query, cb)` results:
  - name matches first;
  - then `grep -F` line matches (0-based).

### Opening a note from elsewhere
- Launcher `/notes` searches too.
- A result opens through `requestOpen(path, line, place)`:
  - on the overlay page that has a Notes module;
  - else in an edge menu that has one.
- The module whose `placeKey` matches shows it: `openRequested`, or `takeReveal` if the module loads within 5 s.

### Per-module state
- The last note per place (`overlay`, `edgeMenu:<id>`, `desktop:<screen>`) is kept in `~/.local/state/axiom/ui/notes-modules.json`.
- `lockNote` pins a module to its `note`.

### Lifecycle
- Created from `shell.qml`'s `_services`.
