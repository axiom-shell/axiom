# ConfigManager, drafts and previews

> **Files:** `qml/config/schema/`, `backend/internal/schema/yamlsrc/`, `backend/internal/migrate/legacy/`, `qml/services/core/ConfigManager.qml`, `qml/services/core/ConfigDraft.qml`, `qml/services/core/BackendManager.qml`, `qml/components/methods/DataDirs.qml`, `qml/components/methods/SchemaValidation.qml`, `qml/services/ui/SettingsManager.qml`, `backend/internal/store/store.go`, `backend/internal/config/load.go`
> **Config:** all of `~/.config/axiom/config.json`
> **Related:** [Config readers](config-readers.md), [Schema annotations](schema-annotations.md), [Editors pattern](editors-pattern.md), [Saved configs and sharing](saved-configs-sharing.md), [Secrets](secrets.md)

The owner of the runtime config: how it is loaded, written, drafted and previewed.

### Owned by axiom
The binary is the shell's parent (`axiom run`) and owns config.json ([The axiom binary](../backend/README.md)); the shell never reads or writes the file.
- **Loading:** at its start axiom loads config.json (converting an older file, below), writes the result as a snapshot and hands the shell its path (`$AXIOM_CONFIG`) and the schema it built (`$AXIOM_SCHEMA`). `ConfigManager` parses both at creation, so `config` is ready, migrated and filled before any reader binds.
- **Changes:** axiom watches the file. An outside edit that loads is pushed (`config.changed`, carrying the ops from the revision before: `Store`'s `Event.Changes`, `config.Diff`), applied to `config` (`ConfigOps.apply`) when it follows the revision the shell has, else (one missed, a re-exec) the config is read again (`config.get`), except from a re-exec'd axiom running on the defaults (an older dev build refusing a newer file): the config read before is kept (after a QML reload, the snapshot, which such a re-exec doesn't rewrite), pushes not applied to it, until `config.state` says axiom left the defaults (a fix, a restore) and it is read again (`_kept`); one that doesn't sets `savesBlocked` (`config.state`) and the shell keeps the last good config. An outside edit never changes an `x-takeover` setting (`Store.holdTakeovers`): the value in effect stays, the change is logged as ignored (daemon log, per key) and the file is written back with the held value, so a hand edit, a sync tool or a backup copied over config.json can't release a managed compositor config; only the setting's own card changes it. `schema.changed` (dev mode, after a YAML edit; pushed before the `config.changed` of the config loaded through it) reads the schema again, and `BackendManager` says its hash in the next hello. A refused hello (the binary and the files disagree) fails every queued call and those after it, rather than holding them; a dropped connection fails the calls in flight and queued, which are never sent after all.
- **Writing:** every write path (`commit`, `setTheme`, `setWallpaper(s)`) fills defaults here, applies the result at once and sends what differs from the running config as path ops (`config.set`, built by `ConfigOps.diff`: a set per changed value, a list whole, a delete per key gone), so a save writes only what it changed; axiom validates and writes it, and if it refuses (logged with its issues; also when the file holds an outside edit not read yet, which axiom reads as it refuses), the running config is read back from it (`hardResetConfig`) and `saveRefused(refused)` follows: a `ConfigDraft` whose `saved` is what was refused sets `saved` from the config read back, so its edits show unsaved again, and live again (its `refused` signal: the editor previews them as it did before the save). The shell doesn't validate first, so axiom's is the one answer. Its own save comes back as a push, already applied.
- **Migrated:** a load that migrated the file says so in the store's state (`State.migrated`: `{ from, to, changes }`, the changes English as logged), in the hello and `config.state`; `ConfigManager.migrated` holds it, and `SettingsManager` notes it once per version, silently ([Notifications](../features/notifications.md) › What the shell sends).
- **First run:** axiom found no config.json and wrote the defaults. It says so in its hello, and `firstRun` is acknowledged (`config.ackFirstRun`) so a QML reload doesn't start the onboarding again.
- **The dev config:** while dev mode runs its dev tree, the daemon's store runs on `$XDG_CONFIG_HOME/axiom/dev/config.json`, a copy of live made the first time, which the install never reads ([The axiom binary](../backend/README.md) › Dev mode). The shell sees no difference: `$AXIOM_CONFIG`, the pushes and every write go to whichever config the daemon runs on. Takeover settings stay live's (one per machine: a change in dev is written to live too). `ConfigManager.configDir` stays the live folder, as it only feeds the shared `saved/`; the dev config's own path is `DevManager.configPath`. Settings › Development shows how dev and live differ and copies settings either way (`DevManager.diff` / `copy` / `pull`).
- **Without axiom** (`qs` started by hand): `available` is false, there is no config, and `qml/shell.qml` shows only a notice with the start line. The greeter (`greeter`) runs read-only on the config `axiom greeter` made from its bundle.

### What it owns
- `_config` (`config`): the config as axiom has it, plus saves applied but not yet answered; never an unsaved edit.
- `live`: `config` with the previews laid over it (`ConfigOps.apply` of `ConfigOps.previewOps`, copying only the objects along each path), what readers read.
- `_configSchema`: `$AXIOM_SCHEMA`, else the tree's `qml/config/json/config.schema.json` (built from `qml/config/schema/`, never committed).
- The active theme's data belongs to ThemeManager, not here.

### Where files live
The tree (`Paths.treePath`; `Paths.axiomPath` is its `qml/`) is read-only to the shell: a package installs it where it can't write (`/usr/share/axiom-shell`, [packaging.md](../packaging.md)). Everything axiom writes is in the XDG folders, resolved once by `DataDirs.xdg` (each `$XDG_*_HOME` when absolute, else its default) and handed out by `ConfigManager.dataDirs` and `Paths`:

| What | Where | `Paths` |
|---|---|---|
| config.json, `saved/` | `$XDG_CONFIG_HOME/axiom/` | `userConfigPath` |
| The dev config (dev mode only; `saved/` stays shared) | `$XDG_CONFIG_HOME/axiom/dev/config.json` | `DevManager.configPath` |
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
3. Format-2 steps by `version`, which must be an integer from 76 to the current one: without it every step would run again, so a format-2 file missing it (or holding a string, or a format-1 number) fails, step 4's way. A migrated config.json is kept once as it was, as `config.v<version>.json`.
4. Unknown keys are dropped (logged as warnings), defaults filled, the result validated. A file that fails runs nothing: axiom runs on the defaults and blocks saves until it's fixed, but its `x-takeover` settings stay the file's (when it isn't JSON, the ones last in effect, which the store keeps in its state folder), so the compositor's mode isn't changed by it ([Config modes](../compositor/config-modes.md#leaving-a-mode)).

`axiom config validate [FILE]` runs the same, read-only.

### The shape of config.json (format 2)
One set of rules the schema follows everywhere it fits:
- **One definition per concept.** A concept used in two places is one `definitions/` entry (`ScreenTarget`, `Blur`, `Shadow`, `Timing`, `ItemId`, …), reused by `$ref`, with sibling overrides where one use differs.
- **Related keys are an object, not a prefix:** `blur: { size, passes, … }`, with a family's on/off switch as its `enabled`; a bar widget's `popout: { enabled, menu }`.
- **Collections are `<Section>.items`.** Every list of user-made things sits beside its section's settings, and every item (also every bar widget and module) has a required, stable `id`, unique in its list. Ids are what editors, path ops (`{id}` selectors), previews and import matching use; position never identifies anything.
- **One way to inherit.** A value an item may take from its section is `null` by default (inherit); the key is still filled, and readers resolve it in one place (`item.style.x ?? section.style.x`).
- **One unit per kind.** Durations are integer milliseconds; `x-unit` is the unit a form shows and types in, and the form and CLI convert. No key names its unit. Enum values are lowerCamel.
- **One screen-targeting shape,** `ScreenTarget` (`{ mode: inherit | primary | focused | all | named, names }`), for everything that picks monitors. `names` is `machine` scope, `mode` is look.
- **No UI or fetched state in config.** What the user didn't choose (a calendar's server name or colour) lives in state files.
- **Annotations are grouped by subject:** `x-compositor: { hyprland, sway, niri }`, `x-card: { file, title, wide, folds, perField }`, and one condition grammar for `x-showIf`, `x-enabledIf`, `x-enumShowIf` and `x-scopeIf`, implemented once in Go (`schema.Holds`) and once in `SchemaLayout` (`showIfHolds`), with shared fixtures ([Schema annotations](schema-annotations.md)).
- **The envelope** is `{ "$schema", "format": 2, "version": N, … }`. `version` is the only migration counter (it continues from 76); `format` names the file's grammar, so a reader refuses a format it doesn't know instead of guessing from a number. Saved and exported files add `meta: { title, description, source }`.

**Types live in folders.** A bar widget, overlay module or view type is a folder `<root>/<Type>/` holding `<Type>.qml` (its root object), `schema.yaml` (its definition) and its private parts. The roots are `qml/components/bar/widgets`, `qml/components/content` and `qml/components/views`; shared bases (`BarWidget`, `BaseView`, …) sit in a `base/` folder beside them. The folder name is the type const, the one place a type's name is written; `Paths.widgetUrl` / `contentUrl` / `viewUrl` build the paths. Popout-only content has no `schema.yaml`. A feature's shared settings (`Weather.location`, used by the widget, module and popout) stay a section in `qml/config/schema/sections/`: a type folder never declares a section.

**What the builder supplies.** `axiom schema build` finds every `schema.yaml` under the three roots (`index.yaml` lists no type definitions) and expands it over its kind's base in `qml/config/schema/definitions/kinds/` (`WidgetBase`, `ModuleBase`, `ViewBase`, …), which adds `type: object`, `additionalProperties: false`, `required`, the type const and `id`, and the kind's common keys (a widget's `visible`, `layout`, `popout` and colour fields; a module's `place` and hosts). A `schema.yaml` writes only what is particular to its type (`label`, `icon`, `group`, `settings`, and the base's parts switched on by name such as `popout`, `colors`, `appearance`); the recipes show the files: [bar widget](../../recipes/bar-widget.md), [overlay module](../../recipes/overlay-module.md), [overlay view](../../recipes/overlay-view.md). Format 1 files are converted once by `migrate/convert` ([migration recipe](../../recipes/migration.md)).

### New entries
Editors create new entries at their definition's defaults with `withDefaults(value, "Bar" | "BarWidget" | "Menu" | "OverlayView" | "OverlayModule")`.

### Writes
- Config is only written through `setTheme()` / `setWallpaper(s)()` / `commit(object)`, or `SettingsManager.setValue(path, value)` from settings UI.
- `commit(object)` (the draft services) fills defaults and returns false, changing nothing, only while saves can't be made (`savesBlocked`, the greeter, no axiom), so drafts stay dirty; it doesn't validate (axiom does, above). A save sends `takeover` only from a takeover setting's own control: `commit(object, takeover)` defaults to false, so axiom keeps the `x-takeover` settings as it has them, and `SettingsManager`'s `commitValues` and `saveChanges` pass true only when they write one (`_takesOver`); `commitValue` (the launcher's `/config`) refuses one. So a save made from a config predating a takeover write of axiom's can't put the stale value back.
- Mutating `ConfigManager.config` fields from UI code never persists.

### ConfigDraft
- The editor services each hold a `ConfigDraft` (`qml/services/core/ConfigDraft.qml`): SettingsManager, BarManager, OverlayManager (and its `MenuEditor`), KeybindManager (its `KeybindEditor`), MonitorManager, plus the `ScreenLayoutEditor` drafts of the desktop, lock screen and greeter layouts.
- A draft is a working copy of one config path:
  - `changed()` after in-place edits
  - `save()` merges onto the latest config via `commit`.
  - `load()` starts over from the config; `loadIfStale()` only when it holds no unsaved edits and is empty or the config isn't the object it was loaded from (every change makes a new one).
- Shape of an editor built on it: [Editors pattern](editors-pattern.md).

### Previews
- `ConfigManager.previews` (`setPreview(path, value)` / `clearPreview(path)` / `setPreviews({ path: value })`, undefined clearing one) holds unsaved edits by dotted key path, shown live without being part of `config`, so other saves and axiom's pushes don't touch them, and a save (which starts from `config`) never carries another page's unsaved edit.
- An editor previews its whole section (BarManager previews `Bars` while dirty); the settings page previews each setting it changed (`SettingsManager._previewOf`, cleared when the draft loads again on Save or Reset) except takeover settings (`x-applyOnSave` or `x-takeover`, `SchemaLayout.waitsForUser`), which wait for Save because their effect is a takeover. A deeper path shows through a section laid over it.
- Readers read `ConfigManager.live`; only a reader exposing the saved config reads `config` (`BarsConfig.savedBars`).
