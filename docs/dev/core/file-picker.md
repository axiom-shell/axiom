# File picker

> **Files:** `services/apps/FilePickerManager.qml`, `scripts/pick_path.py`, `components/forms/SchemaTextField.qml`, `components/forms/SchemaField.qml`
> **Config:** none of its own; `x-control: "folder"` on a string setting adds its Browse button
> **Related:** [Schema annotations](schema-annotations.md), [Saved configs and sharing](saved-configs-sharing.md), [Shell manager and screen targeting](shell-manager-targeting.md)

The desktop's own file picker, for a file or a folder. Axiom draws no picker of its own.

### The script
- `scripts/pick_path.py [--folder] [--filter NAME:GLOB] TITLE [START]` prints the chosen path.
- Tries xdg-desktop-portal's FileChooser (`OpenFile`, with `directory` for `--folder`) through python-gobject first. Without python-gobject, a portal, or a FileChooser backend (xdg-desktop-portal-hyprland has none; the GTK or KDE portal provides it), it falls back to `zenity`, then `kdialog`.
- A `START` that doesn't exist opens home.
- `--folder` needs FileChooser version 3+ (`directory`); an older portal would hand back a file, so it falls back too.
- Exits 1 when cancelled, 2 when no picker could be shown.
- Tests: `tests/scripts/test_scripts.py` `PickPath` (the fallbacks, stubbed).

### The service
- `FilePickerManager.pick(owner, title, options, onPicked, onFailed)`. Options: `folder`, `start` (`~` works), `filter` (`"NAME:GLOB"`), and `shortenHome` (hand back `~/…`, which keeps machine-scoped paths readable).
- One picker at a time: `pick` returns false while one is open, and `running` says so.
- `forget(owner)` drops the callbacks of an owner going away; what's picked then goes nowhere.
- The overlay is stepped aside while the picker is open (`ShellManager.beginStepAside("filePicker")`): the picker is an ordinary window, under the Overlay layer. It ends in `onRunningChanged`, so a picker that never starts doesn't leave the overlay hidden.
- Nothing runs in greeter mode (`Paths.greeter`).

### Callers
- Config import: `SavedConfigsManager.browseImport()`, with a `JSON:*.json` filter.
- Folder settings: `SchemaField` passes `x-control: "folder"` to `SchemaTextField` as `browse`. Its folder button opens the picker in the current folder and commits the path picked at once, as a picked suggestion does. The path comes back as `~/…`: a reader of a `folder` setting expands it (`Paths.expandHome`; axiom's `system` topic does for disk usage). When no picker could be shown, the field says so; typing a path still works.
