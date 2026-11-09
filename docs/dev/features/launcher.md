# Launcher

> **Files:** `qml/services/ui/LauncherManager.qml`, `qml/services/ui/LauncherCommands.qml`, `qml/services/ui/LauncherConfigBrowser.qml`, `qml/services/ui/LauncherFiles.qml`, `qml/components/surfaces/launcher/Launcher.qml`, `qml/components/surfaces/launcher/LauncherPanel.qml`, `qml/components/surfaces/launcher/LauncherRow.qml`, `qml/components/views/Settings/LauncherPlace.qml`
> **Config:** `Launcher.*` (reader `LauncherConfig`)
> **Related:** [Launcher providers](launcher-providers.md), [File search](file-search.md), [Saved configs](../core/saved-configs-sharing.md), [Edge attach](../popouts/edge-attach.md), [Dock](dock.md), [OSD](osd.md)

This doc covers the app launcher: how search text becomes rows, how the window is placed, how input is routed to providers, and how `/` commands and `/config` work. The providers (calculator, clipboard, emoji) are in [launcher-providers.md](launcher-providers.md), the files (`~`) in [file-search.md](file-search.md).

### Model and UI
- `LauncherManager` turns the search text into rows. The UI only draws them.
- `LauncherPanel` holds the field, the list and the hint. It has no box of its own.
- `open(text)` searches first, so instances on other monitors show the same text. The panel created on opening then doesn't search again.
- `reverse` puts the field at the bottom and lays the list out bottom to top.

### Placement
`Launcher.qml` places the panel in one `EdgePopout`, the way every detached surface is placed (an OSD, a dock, a floating edge menu, the window switcher): `edge`, `position` along it, `detached`, and when detached a `distance` (0–50%) across the free screen and an `animation` ([Held off an edge](../popouts/held-off-edge.md)).
- **Detached** (`held`): its gaps are `ScreenEdgeManager.heldGaps`, the automatic gaps with the one across its edge pushed in by `distance` of the room left. 0% lines it up with the window border, 50% centres it. Its depth across is the panel's tallest (`maxContentDepth`), so it doesn't move as results come and go.
  - `animation` Slide slides it in from off the screen (under the bars where it can); Fade fades it in where it sits.
- **Attached:** it grows out of the border or bar at `position` on its edge.
- **Both:** it claims `launcher:<screen>`, so it closes the popouts it covers ([Registry](../popouts/registry.md)). On a side edge its height runs along the edge, so the panel holds its tallest (`LauncherPanel.holdHeight`, the blocks against the field) instead of the window keeping room across (`maxContentDepth`); on the top or bottom edge the box grows from that edge, so it holds it too when the field is at its other end (reversed under the top edge, not reversed over the bottom one), and the field stays put.
- **Settings card:** its top is `LauncherPlace` (the section's `x-intro`, a `PlaceIntro`): the `ScreenSpotPicker` every placed surface has, its nine spots (the centre, each edge's middle, the corners) and a drag (at an edge it attaches, elsewhere it detaches at that distance), over the place fields.

### Motion
- As matches come and go, the list's frame (`LauncherPanel.listFrame`) glides to its rows' height (animFast). The list keeps its target height, clipped meanwhile.
- The box follows the panel as drawn.
- Rows are reused across keystrokes, so nothing is created per keystroke. A row whose result changes (`kind` + `title`) dips its content and brings it back (animFast) rather than cross-fading its text.

### Row shape
Every provider returns the same row shape:
`{ kind, image, glyph, title, usage, subtitle, hint, complete, run(shift), crop, copy(), key }`
- `crop`: `image` is a picture that fills its tile (an option's wallpaper or setup thumbnail, a copied image); an icon keeps its shape.
- `copy()`, when a row has one: <kbd>Ctrl</kbd>+<kbd>C</kbd> with nothing selected in the field runs it and closes the launcher (`LauncherManager.copy`; a file's path). Otherwise Ctrl+C copies the field's selection as usual.
- `key`, when a row has one, names what it shows (a file row's path): rows rebuilt for the same text keep the row of the selected key selected wherever it moved (`LauncherPanel._syncRows`); a row without one, or one gone, keeps the selection's place (clamped), whose row's key it then follows. New text starts at the top.
- A file row also has `thumb` (the file) and `mtime`: `LauncherRow` asks `FileSearchManager` for its thumbnail while it shows the row and draws it cropped in place of the type's icon once it lands.
- What `run` returns decides what happens next:
  - true closes the launcher;
  - false keeps it open, and the rows are rebuilt with the selection kept (by `key`, else by place);
  - a string is searched for instead.
- Tab puts `complete` into the field.

### Routing
The first character picks the provider:

| Prefix | Provider |
|---|---|
| `/` | commands |
| `=` | calculator |
| `>` | run |
| `?` | web |
| `@` | chat |
| `:` | clipboard history (ClipboardManager) |
| `;` | emoji (EmojiManager) |
| `~` | files (`LauncherFiles`, FileSearchManager; [file search](file-search.md)) |

- **No prefix:** the text searches apps and windows.
  - Apps are scored, plus frecency from `usage` `{id: {count, last}}` in `state/launcher.json`, as `Search.useBonus` (the one bonus apps, commands and emoji add).
  - Windows come from `CompositorManager.windows`.
- **Extra rows:** a calculator row is added when the text is plain math, the best `Launcher.providers.files.inSearch` files (from two characters; `LauncherFiles.mainRows`) follow the apps and windows, and a web row goes last. The files land after the rest: `LauncherManager` keeps the calculator, app and window rows of the text (`_mainRows`) and only adds the files and the web row again when they do (`_setMain`), so a keystroke searches the apps once.
- **Toggles:** each provider has a `Launcher` config toggle (`LauncherConfig`).

### Commands
- Commands live in `qml/services/ui/LauncherCommands.qml`, a plain list of entries:
  `{ name, aliases, glyph, description(), usage, needsArg, confirm, available(), status(), options(arg), run(arg, value) }`
- A new shell feature gets a command by adding an entry that calls its service. A command that runs one of the shell's actions (a toggle, a session action, opening a surface) is built by `_action(name, id, aliases, description, call)` or, with `[on | off]` (the action's open / close call), `_switch`: its glyph, status, availability and confirm are the action's, and it runs through `ActionsManager.run` ([Actions](../core/actions.md)).
- `options` supplies argument completions.
- `confirm` asks for a second Enter (`LauncherManager._gate`, a `ConfirmGate`): the destructive session actions, `/clear` and `/update` installing (a getter, true only while an update is available).

### /config
- Its rows and what they do are `qml/services/ui/LauncherConfigBrowser.qml` (`options(arg)`, `run(value)`): not a singleton, `LauncherCommands` holds one for its `config` entry.
- `/config` sets any setting by dotted path (`/config Appearance.font.size 14`). It saves at once through `SettingsManager.commitValue`.
- It also holds `save` / `restore` for snapshots, `example` for the example setups, and `community <search>` for the [community setups](community-setups.md) (with their thumbnails, applied without a wallpaper), as on the settings page ([saved configs](../core/saved-configs-sharing.md)):
  - `save` suggests only `SavedConfigsManager.active`, saying whether it is `modified`. Another snapshot is replaced only by typing its name.
  - `restore` lists the active snapshot first.
  - There is no delete, since a row runs without a confirm.
- It works inside the options contract: each option's title is the whole argument, so matching and Tab work unchanged.
- It offers `SettingsManager.settingPaths` only: the settings page's fields, minus anything under `_blockedPrefixes` (`Bars.items`, `Overlay.items`, `EdgeMenus`). It can never edit bars, overlay pages or edge menus. (Rule: `qml/services/AGENTS.md`, Launcher.)
- A takeover setting (`x-applyOnSave` or `x-takeover`, `SchemaLayout.waitsForUser`) is `openOnly`: typed, it offers only **Show in settings**, and `commitValue` refuses it, so it changes only on its own card.
- Values are parsed and checked by `SettingsManager.parseValue`. Choices come from `SettingsManager.optionsFor`, shared with `SchemaField`.
- Once a setting is typed, its last row is **Show in settings** (while a settings card shows it) (`{ show: key }`): it opens the settings page on that setting (`SettingsManager.openSetting`) after the launcher closes.

### IPC and pages
- **IPC target** `appLauncher`: `open` / `close` / `toggle` / `search <text>`, and `clipboard` / `emoji` / `calculator` (opened on `:`, `;`, `=`; the keybind actions of those names) and `files` (opened on `~`, the recent files; the keybind action `fileSearch`).
- **Open or closed:** each `Launcher` sets `LauncherManager.shown` (the instances open and close together). File results follow the index only while it's shown, and closing it forgets the last answers, so it opens to fresh ones.
- **Opening a page:** `ShellManager.openOverlayPage(type)` opens the target overlay on a page. It takes a view type or a view's name.

### Testing
- `axiom ipc appLauncher search "<text>"`, then a `grim` screenshot.
- The launcher takes keyboard focus, so anything the user types meanwhile leaks into the field.
