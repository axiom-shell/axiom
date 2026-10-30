# Saved configs, examples, import and export

> **Files:** `services/core/SavedConfigsManager.qml`, `components/views/Settings/SavedConfigsCard.qml`, `services/apps/FilePickerManager.qml`, `backend/internal/saved/saved.go`, `backend/internal/share/share.go`, `backend/internal/daemon/sharing.go`, `backend/internal/store/store.go`, `examples/*.json`
> **Config:** whole config, filtered by `x-scope`; snapshots in `~/.config/axiom/saved/`; `~/.local/state/axiom/ui/savedconfigs.json`
> **Related:** [Schema annotations](schema-annotations.md), [Config manager](config-manager.md), [Launcher](../features/launcher.md) (`/config` save/restore), [Shell manager](shell-manager-targeting.md)

Snapshots of the config, the shipped example setups, and sharing a config through export/import. All of them carry only what `x-scope` says (snapshots also the `x-snapshot` wallpaper setup), so loading one never changes another machine setting, and never an `x-takeover` one. axiom does the work (`saved.*` and `share.*` methods, package `saved` over the pure `share`); `SavedConfigsManager` calls it and keeps what the settings page shows. Tests: `go test ./internal/share ./internal/saved` (the format-1 cases are the shared fixtures recorded from the JS `ConfigExamples`).

### Where it shows
- The Maintenance category's own card `SavedConfigsCard` (its `x-categories` `card`, wide, last).
- It shows `SavedConfigsManager`'s snapshots in `~/.config/axiom/saved/`.
- Below them: sharing (Share: Export, Import…) and the example setups in `examples/` (`SavedConfigsManager.examples`).
- The onboarder's Look page shows the examples too, as cards that apply on a click ([Onboarding](../features/onboarding.md)). `share.examples` gives each `{ name, title, description, theme, screenBorder, bars: [{ location, background }], docks: [{ edge }] }`: the shown bars and docks read from the example loaded as applying takes it, for the card's drawn preview.
- The launcher's `/config` can also save and restore snapshots: see [Launcher](../features/launcher.md).

### What a shared file carries: `x-scope`
Inherited down the schema; the root is `machine`.

| Scope | What | Export / import | Snapshot |
|---|---|---|---|
| `look` | the layout and style sections, the theme, font, shape and motion, the launcher's and notifications' look, each surface's Module size (`moduleScale`: a ratio over the card size), compositor animations and decoration, cursor theme, the theme schedule | always | ✅ |
| `personal` | how big the UI is (`Widget.scale`, `cardSize`, `density`: a shared look keeps its proportions at your size), the workspace layout and strips (`Workspaces`: the onboarder offers the examples after its Workspaces step, so one mustn't undo that pick), preferences (notification, idle, night light, input, window behaviour, launcher search, chat, calendar, notes), `Keybinds.binds`, `Apps.pinned`, a dock's own `pinned`, Favourites' apps, OSD app bars | its own switch, off by default | ✅ |
| `commands` | anything that runs as you: every command field, `Apps` terminal/file manager/browser, `Updates` terminal and upgrade, idle listeners, exec and raw binds | its own switch, off by default, warned | ✅ |
| `machine` | monitor names, wallpapers, accounts, paths, hardware, services, takeovers, and every section not marked | never | wallpaper setup only (`x-snapshot`) |

- `x-scopeIf: { when, scope }` on an array's items gives an item its own scope by what it holds (`when` as `x-showIf`, over the item's keys): an `exec`/`raw` bind is `commands`, an `app` OSD bar `personal`. Such an item is left out where its scope isn't carried, and applying keeps the user's own after the file's.
- `x-monitorRef` (`"off"` | `"drop"`) on the monitor names of a per-monitor part (a `ScreenTarget`'s `names`: bars, docks, OSDs, edge menus; a monitor's own desktop, a workspace strip): an export writes each monitor by its place (`#1` leftmost, `#2`, …, `@primary`, `*` for all: the daemon's own outputs by place, `wayland/outputs`, never sent by the shell; until it knows them, monitor fields are left as they are), and applying puts it on the user's monitor in that place. With no monitor there, the part is turned off (`off`) or left out (`drop`), so nothing piles up on the primary. One monitor to two adds nothing: what shows everywhere is `mode: all`.

### What travels (`share`, pure)
Walks a value along the schema.
- `Pick(schema, config, carry, monitors)`: keeps the carried leaves (`carry`: none, `personal`, `commands`, or both), writing monitors by place when given them (a value already a place stays one).
- `Dropped(schema, config, carry, monitors)`: what that pick leaves out, `{ path, scope }` at the highest place (`takeover` for an `x-takeover` setting); given a sparse config, so defaults aren't listed.
- `Apply(schema, current, example, carry, monitors)`: takes the example's carried parts.
  - An array is taken outright, so nothing of the old layout stays.
  - Inside the carried parts it keeps the user's other values from the same item: by `id` (every collection item has one), then `name`; anything else by position (machine values only); else the default. Position matching is machine-only because a personal value such as a command must not land on another button.
  - A setting that serves every widget or module of a feature (accounts, a helper, a location) belongs in the feature's top-level section (`Weather`, `ClaudeUsage`, `Updates`, …, in the Modules category), not in each widget's `properties`: sections are matched by name, so it never depends on where the widget sits.
- `Sparse(schema, config)`: drops what loading fills back in.
- `KeepTakeovers(config, current, paths)`: puts back the current value of every `x-takeover` setting (`TakeoverPaths`: `Compositor.mode`, `Lockscreen.mode`, `Greeter.enabled`, `Idle.enabled`, `Polkit.enabled`). The store applies it to every whole replacement (`Store.Replace`) unless the write is a takeover card's: a snapshot, the defaults, an example, an import. Those settings take something over (hyprland.lua, the session's locker, hypridle, the polkit agent, greetd), so only their own cards switch them. The store also makes a takeover's section the replacement lacks (a saved look), and, over a file that didn't load at the start, keeps the values that file held rather than the defaults it runs on; the write is then checked like any other, so a takeover that still changes is refused. A reload of the file edited from outside keeps them the same way (`Store.holdTakeovers`, [ConfigManager](config-manager.md)).
- `Snapshot(schema, config)`: what a saved snapshot holds: the pick with both scopes, plus the `x-snapshot` settings (`SnapshotPaths`): the wallpapers, wallpaper folder and mode, rotation and light/dark wallpapers. These are machine settings, but a snapshot restores on the PC it was saved on.
- `KeepMovedKeys(config, held, current, version)`: `movedKeys` (generated once from the JS list, in format 2's paths) are the settings that became part of a shared file at a format-1 version (v58, v63: the window look out of the managed Hyprland settings; v71: the settings moved out of `machine`). For a file older than that, each one the file doesn't hold (`held`: converted, not filled) keeps the running config's value instead of its default.
- `SnapshotFiles(schema, config)` and `WithSnapshot(schema, config, saved, existing)`: restore the `x-snapshot` settings; a `file://` URL comes back only while its file exists, and a wallpaper is never blanked (otherwise the current one stays).

### The file format
`{ "format": 2, "version": …, "meta": { "title", "description", "source"? }, …the sparse pick }`. Saved snapshots, exports and examples are one format, so any of them can be shared or imported as it is. A format-1 file (`_example` header, no `format`) is read too: it's converted as config.json would be (`saved.load`: the pipeline, then `KeepMovedKeys`).

### Loading an example or import
- `applyExample(name)`, `confirmImport(personal, commands)` and `applyShared(name, path, title, snapshot)` (a [community setup](../features/community-setups.md), personal parts and commands always off, no confirm row) call `share.example` / `share.import` / `share.applyShared`, which (`Service.apply`, one at a time):
  1. Load the file (`saved.load`), refusing one that isn't a valid config.
  2. Save the running config as `before-<name>`.
  3. Replace the config with `share.Apply` (takeovers kept).
  4. Save the result as its own snapshot and make it active: `example-<name>`, `import-<title>`, or the shared file's (`community-<id>`). The saved configs list then shows it as Current, with Overwrite and the unsaved dot; the prefixes keep it from replacing one of the user's snapshots. Its `meta.source` names what was applied, which `activeSource` gives while it's the active one ("" once the user saves over it, or for one they saved). Restore defaults (`share.defaults`) saves none.
- The manager then signals `applied(name)`, or `applyFailed(name)` (`status` says why: `_refusal` reads axiom's error, e.g. a file from a newer axiom, or a broken config.json while no takeovers are kept: the store refuses every replace until it's fixed by hand, or deleted and axiom restarted (deleting it alone leaves them unknown); `restore` reads it too).
- `browseImport()` opens the desktop's file picker for a JSON file ([File picker](file-picker.md)). `openImport(path)` reads it (`share.open`) as `importing`, with title and description from its header, for the page's confirm row. It offers a switch for its personal parts (`hasPersonal`) and one for its commands (`hasCommands`) only when it holds them; both start off.

### Saving and restoring a snapshot
- `save(name)` (`saved.save`) writes `~/.config/axiom/saved/<name>.json`: the envelope plus `Sparse(Snapshot(config))`.
- `restore(name)` (`saved.restore`) loads the file, checks which of its `SnapshotFiles` exist, and replaces the config with `WithSnapshot(Apply(current, saved, everything), saved, existing)`. Monitors, accounts, theme integrations and other machine settings stay as they are. No backup is made.
- `restoreDefaults()` applies the schema defaults like an example (with personal parts and commands), after a `before-defaults` backup.

### Export
- `exportConfig(personal, commands, places)` (`share.export`) writes `~/axiom-[<active>-]<date>-<time>.json`, with monitors by place unless `places` is false.
- Contents: the envelope plus the sparse pick. It applies as the whole pick would.
- `axiom config share FILE [--places]` (`saved.Share`, offline) prints a shared file of any version as Export would write it again, plus `dropped`: the community setups' CI ([community setups](../features/community-setups.md)). With `--places` and no monitors, places stay and connector names are dropped.

### Adding an example setup
- Build the setup in the shell, then Settings → Maintenance → Share → Export, with both switches off unless the example needs a command. It writes `~/axiom-<name>-<date>-<time>.json`, holding only the look (`x-scope`) minus defaults.
- Move it to `examples/<name>.json` and fill in its `meta`: `{ "title": "…", "description": "…" }`.
- Wallpapers, accounts and paths are `machine` scope, so they're never in an export, and monitors only by place: don't add them by hand.

### Snapshot rows
- `active` is the one last saved or restored, kept in `ui/savedconfigs.json` and pushed as `saved.state`. Only its row offers Overwrite.
- `modified` dots it: the running config's `Snapshot` differs from the saved file's (`Service.Changed`, on every config change). A machine-only change leaves it off, and so does anything that changes on its own (rotation, light/dark wallpapers and schedule), which never writes the config.
