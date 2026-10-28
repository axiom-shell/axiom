# Recipe: a new setting in an existing section

> **Use when:** adding one config key to a section that already exists (`Battery`, `Launcher`, `Appearance`, …). For a new section see [config-section](config-section.md); renaming or reshaping an existing key needs a [migration](migration.md).
> **Copy from:** `config/schema/sections/Battery.yaml` (small section, `x-order`, `x-unit`, min/max) with `config/BatteryConfig.qml` (the reader)
> **Docs:** [schema-annotations](../dev/core/schema-annotations.md), [config-readers](../dev/core/config-readers.md), generated reference `docs/dev/config/<Section>.md`

## Files to touch
1. `config/schema/sections/<Section>.yaml` → `properties.<key>`: the setting, with a `default`. Add the key to the section's `x-order` if it has one.
2. `config/<Section>.qml` or `config/<Section>Config.qml` (find it in the table in `docs/dev/config/README.md`): one `readonly property <type> <name>: _c.<key>`.
3. The consumer (service or UI) reads `<Reader>.<name>`, never `ConfigManager.config`.
4. `config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys, empty, to every language and the template (the title and description are translation keys).

## Skeleton
```json
"lowThreshold": {
  "type": "integer",
  "title": "Low at",
  "description": "One sentence on what it does, in the user's terms.",
  "x-unit": "%",
  "default": 20,
  "minimum": 0,
  "maximum": 100
}
```
```qml
  // Percentages at or below which the battery is low / critical
  readonly property int lowThreshold: _c.lowThreshold
```

## Steps
1. Find the section and its reader: `grep -n 'Section.someKey' docs/dev/config/<Section>.md` shows how its siblings are declared and read.
2. Add the schema entry. Required: `type`, `default`, `title`. Usual: `description`, and `x-group` when the section's other keys have one (it picks the settings card).
3. Add the key to the section's `x-order`, if it has one, in the position the user should see it.
4. Pick annotations from [schema-annotations](../dev/core/schema-annotations.md), e.g. `x-showIf`, `x-unit`, `x-options`, `x-control`, `x-beside`, `x-applyOnSave`. Prefer an annotation to special-casing in QML.
5. Add the reader property: plain `_c.<key>`, no `??` fallback (the default is always filled). A derived value is its own property next to it, e.g. `wallpaperPath: Paths.expandHome(_c.wallpaperFolder)`.
6. Use it from the consumer.

## Gotchas
- **`x-scope`:** a key inside a `look`-scoped section that names a monitor, path or account needs `"x-scope": "machine"`, and one that runs something `"commands"`. Otherwise examples, imports and exports carry it to other PCs.
- **`x-takeover: true`** is for settings that take something over on this PC (locker, idle, polkit, Hyprland mode, greeter). Loading or importing a config never changes those.
- **Paths:** a folder setting gets `"x-control": "folder"` (a Browse button; [File picker](../dev/core/file-picker.md)). It may hold `~`, so expand it with `Paths.expandHome` before it reaches a process or a file read (AGENTS.md › Config).
- **Ordering:** QML sees schema objects as maps with sorted keys. `x-order` puts its keys first, and unlisted keys follow alphabetically, so list a new key where it belongs.
- **No migration needed:** a purely additive key fills its default on load. In a section format 1 already had, list it in `addedSinceV1` (`backend/internal/migrate/convert/convert_test.go`), or the check that format 1's defaults convert to the current ones fails.
- **Wrong default type:** a default that doesn't validate (wrong type, outside min/max) makes the whole config fall back to defaults. `tst_Config` catches it.
- **Drafts:** readers read `ConfigManager.live`, so an editor's unsaved preview of the setting shows through them with nothing more to do.
- **Live config:** the running axiom validates against the schema it loaded at its start (`AGENTS.md` › Running / reloading). Confirm it has the new schema before relying on the new key in `~/.config/axiom/config.json`.

## Verify
- `scripts/dev/verify.sh`: formats changed QML in place, runs `check_structure`, regenerates docs, runs related tests, shows the shell's log since the reload.
- `scripts/run_tests.sh Config`: the defaults are a valid config.
- `scripts/check_i18n.py`
- To see it on its settings card: `scripts/dev/shot.sh page Settings`.

## Docs to update
- The feature's doc in `docs/dev/` if the setting changes how the feature works. The generated `docs/dev/config/<Section>.md` updates itself.
- `docs/features.md` / `docs/configuration.md` if it's a user-facing capability worth mentioning.
