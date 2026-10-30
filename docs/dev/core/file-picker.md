# File picker

> **Files:** `services/apps/FilePickerManager.qml`, `backend/internal/filepicker/filepicker.go`, `backend/internal/daemon/tools.go`, `components/forms/SchemaTextField.qml`, `components/forms/SchemaField.qml`
> **Config:** none of its own; `x-control: "folder"` on a string setting adds its Browse button
> **Related:** [Schema annotations](schema-annotations.md), [Saved configs and sharing](saved-configs-sharing.md), [Shell manager and screen targeting](shell-manager-targeting.md)

The desktop's own file picker, for a file or a folder. Axiom draws no picker of its own.

### The daemon
- `filepicker.pick` (`{ title, start, folder, filter }` → `{ path }`, `""` when cancelled; `backend/internal/filepicker`, registered in `daemon/tools.go`) shows a picker and answers when it closes.
- It tries xdg-desktop-portal's FileChooser (`OpenFile`, with `directory` for a folder and `filters` for `"NAME:GLOB"`, GLOB split on spaces into one pattern each: zenity and kdialog take the spaces as they are) on a session bus connection of its own (`internal/dbus`). Without a bus, a portal, or a FileChooser backend (xdg-desktop-portal-hyprland has none; the GTK or KDE portal provides it), it falls back to `zenity`, then `kdialog`, run as the shell's commands are (`command.Run`, the shell's environment). With none, it's `unavailable`.
- It subscribes to the portal's `Response` signals by interface before calling, and takes the one on the handle `OpenFile` returns, so a quick answer isn't missed and a portal older than `handle_token` (answering on a path of its own) still works.
- A `start` that doesn't exist opens home.
- A folder needs FileChooser version 3+ (`directory`); an older portal would hand back a file, so it falls back too.
- When the call ends before the picker does (the shell reloaded, the daemon re-execs), the portal's picker is closed (`Request.Close`); a zenity or kdialog stays open, its answer going nowhere.
- Tests: `filepicker_test.go`, on a fake portal on `dbustest`'s bus and fake fallbacks.

### The service
- `FilePickerManager.pick(owner, title, options, onPicked, onFailed)`. Options: `folder`, `start` (`~` works), `filter` (`"NAME:GLOB"`), and `shortenHome` (hand back `~/…`, which keeps machine-scoped paths readable).
- One picker at a time: `pick` returns false while one is open, and `running` says so.
- `forget(owner)` drops the callbacks of an owner going away; what's picked then goes nowhere.
- The overlay is stepped aside while the picker is open (`SurfaceManager.beginStepAside("filePicker")`): the picker is an ordinary window, under the Overlay layer. It ends when `filepicker.pick` answers, whatever the answer, so a picker that never starts doesn't leave the overlay hidden. Any error (no picker, no axiom) calls `onFailed` and is logged.
- Nothing runs in greeter mode (`Paths.greeter`).

### Callers
- Config import: `SavedConfigsManager.browseImport()`, with a `JSON:*.json` filter.
- VPN import: `VpnManager.pickImport()` (`*.conf *.ovpn`), and a CA certificate in the Wi-Fi menu's `WifiJoinForm`.
- Folder settings: `SchemaField` passes `x-control: "folder"` to `SchemaTextField` as `browse`. Its folder button opens the picker in the current folder and commits the path picked at once, as a picked suggestion does. The path comes back as `~/…`: a reader of a `folder` setting expands it (`Paths.expandHome`; axiom's `system` topic does for disk usage). When no picker could be shown, the field says so; typing a path still works.
