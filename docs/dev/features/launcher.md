# Launcher

> **Files:** `services/ui/LauncherManager.qml`, `services/ui/LauncherCommands.qml`, `services/ui/LauncherConfigBrowser.qml`, `components/surfaces/launcher/Launcher.qml`, `components/surfaces/launcher/LauncherPanel.qml`, `components/surfaces/launcher/LauncherRow.qml`, `components/views/Settings/LauncherPlace.qml`
> **Config:** `Launcher.*` (reader `LauncherConfig`)
> **Related:** [Launcher providers](launcher-providers.md), [Saved configs](../core/saved-configs-sharing.md), [Edge attach](../popouts/edge-attach.md), [Dock](dock.md), [OSD](osd.md)

This doc covers the app launcher: how search text becomes rows, how the window is placed, how input is routed to providers, and how `/` commands and `/config` work. The providers (calculator, clipboard, emoji) are in [launcher-providers.md](launcher-providers.md).

### Model and UI
- `LauncherManager` turns the search text into rows. The UI only draws them.
- `LauncherPanel` holds the field, the list and the hint. It has no box of its own.
- `open(text)` searches first, so instances on other monitors show the same text. The panel created on opening then doesn't search again.
- `reverse` puts the field at the bottom and lays the list out bottom to top.

### Placement
`Launcher.qml` places the panel the way a dock or OSD is placed (`edge`, `position` along it, `detached`), with one difference: detached, it is not held a gap in px off the edge but a `distance` (0–50%) across the free screen.
- **Detached:** a `FloatingPopout`.
  - It claims `launcher:<screen>` as the attached one does, so it closes the popouts it covers ([Registry](../popouts/registry.md)).
  - Its fraction and its align across are both that distance, measured from the far side on the bottom or right edge. 0% sits against its margin; 50% is centred.
  - Its margins are where a detached dock or OSD with an automatic gap sits (`ScreenEdgeManager.detachedGaps`, per side; `Launcher._marginOn`).
  - `maxContentHeight` keeps it from moving, and `growUp` keeps a reversed field in place.
- **Attached:** an `EdgePopout` at `position` on its edge.
  - On a side edge its height runs along the edge, so the panel holds its tallest (`LauncherPanel.holdHeight`, the blocks against the field) instead of the window keeping room across (`maxContentDepth`).
- **Shared:** both hosts have the same API (`show`/`hide`/`isOpen`/`contentItem`/`window`). Only the host in use is created, through `LazyLoader`s.
- **Settings card:** its top is `LauncherPlace` (the section's `x-intro`), a `ScreenSpotPicker` with presets (Top, Upper, Center, Bottom, Left, Right) over the place fields.

### Motion
- As matches come and go, the list's frame (`LauncherPanel.listFrame`) glides to its rows' height (animFast). The list keeps its target height, clipped meanwhile.
- Both hosts follow the panel as drawn. `FloatingPopout.animateHeight` is off, so its box doesn't chase it.
- Rows are reused across keystrokes, so nothing is created per keystroke. A row whose result changes (`kind` + `title`) dips its content and brings it back (animFast) rather than cross-fading its text.

### Row shape
Every provider returns the same row shape:
`{ kind, image, glyph, title, usage, subtitle, hint, complete, run(shift) }`
- What `run` returns decides what happens next:
  - true closes the launcher;
  - false keeps it open, and the rows are rebuilt with the selection kept;
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

- **No prefix:** the text searches apps and windows.
  - Apps are scored, plus frecency from `usage` `{id: {count, last}}` in `state/launcher.json`.
  - Windows come from `CompositorManager.windows`.
- **Extra rows:** a calculator row is added when the text is plain math, and a web row goes last.
- **Toggles:** each provider has a `Launcher` config toggle (`LauncherConfig`).

### Commands
- Commands live in `services/ui/LauncherCommands.qml`, a plain list of entries:
  `{ name, aliases, glyph, description(), usage, needsArg, confirm, available(), status(), options(arg), run(arg, value) }`
- A new shell feature gets a command by adding an entry that calls its service.
- `options` supplies argument completions.
- `confirm` (destructive session actions) asks for a second Enter.

### /config
- Its rows and what they do are `services/ui/LauncherConfigBrowser.qml` (`options(arg)`, `run(value)`): not a singleton, `LauncherCommands` holds one for its `config` entry.
- `/config` sets any setting by dotted path (`/config Appearance.font.size 14`). It saves at once through `SettingsManager.commitValue`.
- It also holds `save` / `restore` for snapshots, `example` for the example setups, and `community <search>` for the [community setups](community-setups.md) (with their thumbnails, applied without a wallpaper), as on the settings page ([saved configs](../core/saved-configs-sharing.md)):
  - `save` suggests only `SavedConfigsManager.active`, saying whether it is `modified`. Another snapshot is replaced only by typing its name.
  - `restore` lists the active snapshot first.
  - There is no delete, since a row runs without a confirm.
- It works inside the options contract: each option's title is the whole argument, so matching and Tab work unchanged.
- It offers `SettingsManager.settingPaths` only: the settings page's fields, minus `x-applyOnSave` ones and anything under `_blockedPrefixes` (`Bars.items`, `Overlay.items`, `EdgeMenus`). It can never edit bars, overlay pages or edge menus. (Rule: AGENTS.md › UI conventions.)
- Values are parsed and checked by `SettingsManager.parseValue`. Choices come from `SettingsManager.optionsFor`, shared with `SchemaField`.
- Once a setting is typed, its last row is **Show in settings** (while a settings card shows it) (`{ show: key }`): it opens the settings page on that setting (`SettingsManager.openSetting`) after the launcher closes.

### IPC and pages
- **IPC target** `appLauncher`: `open` / `close` / `toggle` / `search <text>`.
- **Opening a page:** `ShellManager.openOverlayPage(type)` opens the target overlay on a page. It takes a view type or a view's name.

### Testing
- `axiom ipc appLauncher search "<text>"`, then a `grim` screenshot.
- The launcher takes keyboard focus, so anything the user types meanwhile leaks into the field.
