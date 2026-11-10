# Adding a setting

A setting is one key in a config section that already exists (`Battery`, `Launcher`, `Appearance`, …). You declare it once in the section's YAML schema, which gives it a default, validation and a row on the settings page, and add one reader property so code can use it. For a new section see [config-section](config-section.md); renaming or reshaping an existing key needs a [migration](migration.md).

**Copy from:** `qml/config/schema/sections/Battery.yaml` (a small section: `x-unit`, minimum and maximum) with `qml/config/BatteryConfig.qml` (the reader).
**Background:** [schema-annotations](../dev/core/schema-annotations.md), [config-readers](../dev/core/config-readers.md), generated reference `docs/dev/config/<Section>.md`

## Files
1. `qml/config/schema/sections/<Section>.yaml` → `properties.<key>`: the setting, with a `default`. If the section lists an explicit `x-order`, add the key there too.
2. The section's reader, `qml/config/<Section>.qml` or `qml/config/<Section>Config.qml` (the table in `docs/dev/config/README.md` lists them): one `readonly property <type> <name>: _c.<key>`.
3. The consumer (service or UI) reads `<Reader>.<name>`, never `ConfigManager.config`.

Translation keys for the title and description are added by the pre-commit hook.

## Steps
1. Find the section and reader. `docs/dev/config/<Section>.md` shows how its siblings are declared and read.
2. Add the schema entry, as `lowThreshold` is in `Battery.yaml`:
   ```yaml
   lowThreshold: {type: integer, title: Low at, x-unit: '%', default: 20, minimum: 0, maximum: 100}
   ```
   `type`, `default` and `title` are required; usually add a `description` in the user's terms, and `x-group` when the section's other keys have one (it picks the settings card). Properties show in the order they are written, unless the section has an `x-order`.
3. Pick annotations from [schema-annotations](../dev/core/schema-annotations.md) (`x-showIf`, `x-unit`, `x-options`, `x-control`, `x-beside`, `x-applyOnSave`, …) in preference to special-casing in QML.
4. Add the reader property: plain `_c.<key>`, no `??` fallback (the default is always filled). A derived value is its own property next to it (`NotesConfig.directory` expands a path).
5. Use it from the consumer.

## Watch out for
- **Icons.** A Material Symbols name takes `x-control: icon`: the field searches the bundled icons, and `check_icons.py` checks the default ([icons](../dev/core/icons.md)).
- **Scope.** A key in a `look`-scoped section that names a monitor, path or account needs `x-scope: machine`, and one that runs something `x-scope: commands`. Otherwise examples, imports and exports carry it to other PCs ([saved configs](../dev/core/saved-configs-sharing.md)).
- **Takeovers.** `x-takeover: true` is for settings that take something over on this PC (locker, idle, polkit, compositor mode, greeter). Loading or importing a config never changes them.
- **Paths.** A folder setting takes `x-control: folder` (a Browse button; [file picker](../dev/core/file-picker.md)). It may hold `~`, so expand it with `Paths.expandHome` before it reaches a process or a file read.
- **Key order.** QML sees schema objects as maps with sorted keys, so the order a row appears in comes from `x-order`, which the build writes from the properties' order unless the YAML has one.
- **No migration for an added key**; it fills its default on load. In a section format 1 already had, also list it in `addedSinceV1` (`backend/internal/migrate/convert/convert_test.go`), or the test that format 1's defaults convert to the current ones fails.
- **Defaults must validate.** A default of the wrong type, or outside its minimum and maximum, makes the whole config fall back to defaults. `tst_Config` catches it.
- **Drafts.** Readers read `ConfigManager.live`, so an editor's unsaved preview of the setting shows through them with nothing more to do.
- **Live config.** The running axiom validates against the schema it loaded at start ([testing](../dev/testing.md) › Reloads and logs), so confirm it has the new schema before using the key in `~/.config/axiom/config.json`.

## Check it
- `scripts/dev/verify.sh`: formats changed QML, runs the structure checks, regenerates docs, runs related tests and shows the shell's log since the reload.
- `scripts/run_tests.sh Config`: the defaults are a valid config.
- `scripts/check_i18n.py`
- To see it on its settings card: `scripts/dev/shot.sh page Settings`.

## Docs to update
- The feature's doc in `docs/dev/` if the setting changes how the feature works. The generated `docs/dev/config/<Section>.md` updates itself.
- `docs/features.md` or `docs/configuration.md`, if it is a user-facing capability worth mentioning.
