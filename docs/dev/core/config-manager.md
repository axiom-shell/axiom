# ConfigManager, drafts and previews

> **Files:** `services/core/ConfigManager.qml`, `services/core/ConfigDraft.qml`, `services/core/BackendManager.qml`, `components/methods/DataDirs.qml`, `components/methods/SchemaValidation.qml`, `services/ui/SettingsManager.qml`, `backend/internal/store/store.go`, `backend/internal/config/load.go`
> **Config:** all of `~/.config/axiom/config.json`
> **Related:** [Config readers](config-readers.md), [Schema annotations](schema-annotations.md), [Editors pattern](editors-pattern.md), [Saved configs and sharing](saved-configs-sharing.md), [Secrets](secrets.md)

The owner of the runtime config: how it is loaded, written, drafted and previewed. Read before writing config from anywhere.

### Owned by axiom
The binary is the shell's parent (`axiom run`) and owns config.json ([The axiom binary](../backend/README.md)); the shell never reads or writes the file.
- **Loading:** at its start axiom loads config.json (converting an older file, below), writes the result as a snapshot and hands the shell its path (`$AXIOM_CONFIG`) and the schema it built (`$AXIOM_SCHEMA`). `ConfigManager` parses both at creation, so `config` is ready, migrated and filled before any reader binds.
- **Changes:** axiom watches the file. An outside edit that loads is pushed (`config.changed`), replacing `config`; one that doesn't sets `savesBlocked` (`config.state`) and the shell keeps the last good config. An outside edit never changes an `x-takeover` setting (`Store.holdTakeovers`): the value in effect stays, the change is logged as ignored (daemon log, per key) and the file is written back with the held value, so a hand edit, a sync tool or a backup copied over config.json can't release a managed compositor config; only the setting's own card changes it. `schema.changed` (dev mode, after a YAML edit; pushed before the `config.changed` of the config loaded through it) reads the schema again, and `BackendManager` says its hash in the next hello. A refused hello (the binary and the files disagree) fails every queued call and those after it, rather than holding them; a dropped connection fails the calls in flight and queued, which are never sent after all.
- **Writing:** every write path (`saveConfig`, `commit`, `setTheme`, `setWallpaper(s)`) validates here, applies the result at once and sends it (`config.replace`); axiom writes it, and if it refuses, the running config is read back from it (`hardResetConfig`). `restoreConfig(object, done)` hands a whole config of any version to axiom (`config.restore`), which loads it as it loads the file and keeps the `x-takeover` settings as they are.
- **First run:** axiom found no config.json and wrote the defaults. It says so in its hello, and `firstRun` is acknowledged (`config.ackFirstRun`) so a QML reload doesn't start the onboarding again.
- **Without axiom** (`qs` started by hand): `available` is false, there is no config, and `shell.qml` shows only a notice with the start line. The greeter (`greeter`) runs read-only on the config `axiom greeter` made from its bundle.

### What it owns
- `_config`: the config as axiom has it, plus edits applied but not yet answered.
- `_configSchema`: `$AXIOM_SCHEMA`, else the tree's `config/json/config.schema.json` (built from `config/schema/`, never committed).
- The active theme's data belongs to ThemeManager, not here.

### Where files live
The repo (`Paths.axiomPath`) is read-only to the shell: a package installs it where it can't write (`/usr/share/axiom`, [packaging.md](../packaging.md)). Everything axiom writes is in the XDG folders, resolved once by `DataDirs.xdg` (each `$XDG_*_HOME` when absolute, else its default) and handed out by `ConfigManager.dataDirs` and `Paths`:

| What | Where | `Paths` |
|---|---|---|
| config.json, `saved/` | `$XDG_CONFIG_HOME/axiom/` | `userConfigPath` |
| `StateManager` files (launcher, look, editors, onboarding, settings, clipboard pins, …) | `$XDG_STATE_HOME/axiom/ui/` (0700) | `statePath` |
| Secrets, chats, notification history, calendar cache, generated hypridle/Hyprland configs, integration outputs | `$XDG_STATE_HOME/axiom/` | `userStatePath` |
| Themes generated from the wallpaper (`generated/<name>`) | `$XDG_STATE_HOME/axiom/themes/` | `generatedThemesPath`, `themeFile(name)` |
| Palettes community setups brought (`community/<id>`) | `$XDG_DATA_HOME/axiom/themes/` | `communityThemesPath`, `themeFile(name)` |
| The default notes folder | `$XDG_DATA_HOME/axiom/notes/` | `defaultNotesPath` |
| What can be downloaded again (the [community setups](../features/community-setups.md) catalog, thumbnails, screenshots) | `$XDG_CACHE_HOME/axiom/` | `communityCachePath` (`community/`) |

- Files under `userStatePath` keep their names: users' own configs point at several (the Hyprland include, the fzf/nvim/ncspot outputs).
- The greeter has its own folders (`Paths.greeterDir`) and reads none of these.
- **Data others installed** (Wayland sessions, Hyprland's example config and wallpapers, cursor themes) is looked up in `Paths.dataSearchDirs` (`DataDirs.searchDirs`: `$XDG_DATA_HOME`, then `$XDG_DATA_DIRS`, else `/usr/local/share:/usr/share`), never at a fixed `/usr/share` path: NixOS keeps nothing there. The binary's takeover (`compositor/takeover`, Hyprland's example) does the same.

### Load pipeline
In axiom (`config.Pipeline.Load`), for config.json, saved configs and imports alike:
1. Parse (a byte-order mark is ignored).
2. A format-1 file (no `format`): the frozen v1–v75 migrations (`backend/internal/migrate/legacy/`, the shell's JS migrations run as they were), then the conversion to format 2 (`migrate/convert`). The file as it was is kept once as `config.format1.json`. This path stays only until format 1 is retired.
3. Format-2 steps by `version`.
4. Unknown keys are dropped (logged as warnings), defaults filled, the result validated. A file that fails runs nothing: axiom runs on the defaults and blocks saves until it's fixed, but its `x-takeover` settings stay the file's (unknown when it isn't JSON), so the compositor's mode isn't changed by it ([Config modes](../compositor/config-modes.md#leaving-a-mode)).

`axiom config validate [FILE]` runs the same, read-only.

### New entries
Editors create new entries at their definition's defaults with `withDefaults(value, "Bar" | "BarWidget" | "EdgeMenu" | "OverlayView" | "OverlayModule")`.

### Writes
(Rule: AGENTS.md › Services, "Config writes".)
- All writes go through `setTheme()` / `setWallpaper(s)()` / `saveConfig()` / `commit(object)`, or `SettingsManager.setValue(path, value)` from settings UI.
- They validate against the schema here first: `commit(object)` (the draft services) fills defaults, and returns false, changing nothing, if rejected, so drafts stay dirty. Every save sends `takeover: true` but `commit(object, false)`, which keeps the `x-takeover` settings as axiom has them (a save that changes none).
- Never mutate `ConfigManager.config` fields from UI code and expect persistence.

### ConfigDraft
- The editor services each hold a `ConfigDraft` (`services/core/ConfigDraft.qml`): SettingsManager, BarManager, OverlayManager (and its `EdgeMenuEditor`), KeybindManager, MonitorManager, plus the `ScreenLayoutEditor` drafts of the desktop, lock screen and greeter layouts.
- A draft is a working copy of one config path:
  - `changed()` after in-place edits
  - `save()` merges onto the latest config via `commit`.
  - `load()` starts over from the config; `loadIfStale()` only when it holds no unsaved edits and is empty or the config isn't the object it was loaded from (every change makes a new one).
- Shape of an editor built on it: [Editors pattern](editors-pattern.md).

### Previews
- `ConfigManager.previews` (`setPreview(section, value)` / `clearPreview(section)`) holds unsaved edits shown live without being part of `config`, so other saves and axiom's pushes don't touch them.
- Example: BarManager previews `Bars` while dirty, and `ScreenEdgeManager.bars` reads `previews.Bars ?? config.Bars`.
- Readers that show previews read `previews.X ?? config.X` (`DesktopConfig`, `EdgeMenusConfig`).
