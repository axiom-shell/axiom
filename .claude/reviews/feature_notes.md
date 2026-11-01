# feature:notes
reviewed: f8e13e3 2026-11-01  (full)

The shared-document and lossless-Markdown core holds; the bugs sit on rare paths: a rename with a dot drops the extension, a `#` in a folder name breaks the browser, a changed notes folder keeps the old note's text and saves it there, a missing linked folder is created by typing, and two toolbar edits skip the re-parse. Deletion pass: 22 lines (19 net).

## Open findings
- Major: [Renaming a note whose new name holds a dot drops its extension and hides it](../../docs/dev/issues.md#renaming-a-note-whose-new-name-holds-a-dot-drops-its-extension-and-hides-it)
- Major: [A folder name holding `#` or `?` opens the wrong folder in the note list](../../docs/dev/issues.md#a-folder-name-holding--or--opens-the-wrong-folder-in-the-note-list)
- Major: [A changed notes folder keeps showing the old folder's note and saves it into the new one](../../docs/dev/issues.md#a-changed-notes-folder-keeps-showing-the-old-folders-note-and-saves-it-into-the-new-one)
- Major: [Typing in a note creates a linked notes folder that doesn't exist](../../docs/dev/issues.md#typing-in-a-note-creates-a-linked-notes-folder-that-doesnt-exist)
- Major: [Two toolbar edits skip the re-parse, so the editor's blocks aren't what parse() gives](../../docs/dev/issues.md#two-toolbar-edits-skip-the-re-parse-so-the-editors-blocks-arent-what-parse-gives)
- Cleanup: [Notes documents count a revision nothing reads](../../docs/dev/issues.md#notes-documents-count-a-revision-nothing-reads)
- Cleanup: [NotesConfig expands ~ by hand where Paths.expandHome does it](../../docs/dev/issues.md#notesconfig-expands--by-hand-where-pathsexpandhome-does-it)
- Cleanup: [NoteMarkdown's reparse repeats _normalize](../../docs/dev/issues.md#notemarkdowns-reparse-repeats-_normalize)
- Minor: The completed-items button drops the module's showCompleted setting (`components/content/Notes/Notes.qml:232`): after one click, the setting's changes are ignored until the module reloads.
- Minor: The Toolbar setting's description (`components/content/Notes/schema.yaml` `showToolbar`) names only the checklist and bullet buttons, not find and completed items.
- Minor: `refreshList` sets `directoryMissing` before its stale-folder guard (`services/apps/NotesManager.qml:302`).

## Contract
Holds: paths relative and `clean()` refusing absolute, `.` and `..`; shared reference-counted documents (`acquire`/`release` flushing; 600 ms save; disk changes reload unless dirty, own writes not counted, through `FileManager.write`/`watch`); argv processes for create, rename and trash, `gio trash` with an always-asked `rm -rf` fallback; `moved`/`removed` followed by the module; the lossless round trip (tests); re-parse on Enter, Backspace/Delete across blocks, toggles and typed `- [ ] ` / text after a blank line (`needsReparse`), never per keystroke; NoteBlock rendered unless focused or holding the match, MouseAreas over TapHandlers; `ensureVisible` via `Qt.callLater` + `forceLayout`; ScrollMemory keyed by the opened path, cancelled by a jump; Ctrl+F find; search name matches then `grep -F` lines (0-based), the query passed as an argument; launcher `/notes` via `requestOpen` (an overlay page first, then an edge menu) with `takeReveal` within 5 s; the last note per place in the `notes-modules` state; `lockNote`; created from `shell.qml`'s `_services`. Not true: "Every structural edit re-parses" and "A linked folder is never created" (both filed above).

## Coverage
Read deeply: services/apps/NotesManager.qml, config/NotesConfig.qml, components/content/Notes/Notes.qml, components/content/parts/notes/NoteEditor.qml, NoteBlock.qml, NoteBrowser.qml, components/methods/NoteMarkdown.qml, components/content/Notes/schema.yaml, config/schema/sections/Notes.yaml · Outlined: tests/tst_NoteMarkdown.qml, services/ui/LauncherCommands.qml (the `/notes` command), services/core/FileManager.qml (write, read), backend/internal/rpc/rpc.go (call ordering) · Skipped: nothing. Checked and fine: a rename or trash racing its own flush (file.write and exec.run run concurrently in the daemon, but a flush only carries edits under 600 ms old, quicker than reaching the rename field); the search's hidden-file filtering; `_create`'s numbering script.

## History
- 2026-11-01 full: 11 findings (5 Major, 3 Cleanups, 3 Minor); recorded
