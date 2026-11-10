# Adding a config section

A section is a top-level group in config.json (`Battery`, `Polkit`, `Notes`), with a page or card of its own in Settings. You add it as a YAML file in the schema plus a small reader singleton, so the rest of the shell reads typed values instead of raw config. At the end the section has defaults, a settings page, and a reader other code can bind to. For one more key in a section that exists, see [setting](setting.md).

**Copy from:** `qml/config/schema/sections/Polkit.yaml` with `qml/config/PolkitConfig.qml` (the smallest pair), `qml/config/schema/sections/Battery.yaml` with `qml/config/BatteryConfig.qml` (several keys with units and limits), `qml/config/NotesConfig.qml` (derived values).
**Background:** [config-readers](../dev/core/config-readers.md), [config-manager](../dev/core/config-manager.md), [schema-annotations](../dev/core/schema-annotations.md), [settings-page](../dev/core/settings-page.md)

## Files
1. `qml/config/schema/sections/<Section>.yaml`, and its name in `qml/config/schema/index.yaml`'s `sections` list (the order there is the order in the config). The section is an object with `x-category`, `title`, `description`, `additionalProperties: false` and `properties`, each property with a `default`.
2. `qml/config/<Section>.qml`, or `qml/config/<Section>Config.qml` when `<Section>` is also a type name (a bar widget, module, view or Quickshell type), as `BatteryConfig`, `OSDConfig` and `LauncherConfig` are.
3. The service and UI that use it.

Translation keys for the titles and descriptions are added by the pre-commit hook.

## Steps
1. Write the section YAML, starting from `Polkit.yaml`.
   - `x-category` is the `name` of one of the root's `x-categories` in `index.yaml` (General, Look & Feel, Compositor, Workspaces, Overlay & Popouts, Dock, OSD, Launcher, Notifications, Screen & Power, Calendar, Modules, Theme integrations, System, Development).
   - `x-scope` (`look`, `personal`, `commands`) is only for a section that should travel with examples and exports. Otherwise it inherits the root's `machine`.
   - A section that takes something over on this PC (a system agent, a daemon) marks that setting `x-takeover: true`.
2. Write the reader as `PolkitConfig.qml` does: `pragma Singleton`, a `QtObject`, `import qs.services.core` for `ConfigManager`, and `readonly property var _c: ConfigManager.live.<Section>`. Then one `readonly property` per key that is used, as `_c.<key>`, with no `??` fallback (defaults are always filled). A value derived from a key is its own property (`NotesConfig.directory`).
3. Use it: services read it to act and UI binds to it.
4. A hand-built settings card is only for what the generated form can't express: [settings-card](settings-card.md).

## Watch out for
- **Unknown sections are pruned on load**, with a warning, so a key missing from the schema vanishes from the user's config on the next save.
- **Reader naming.** The name must not collide with a type its users can see (bar widgets, content, views, Quickshell types); `check_structure` reports two same-named types in one file's scope.
- **Layering.** Readers read only `ConfigManager`, `ThemeManager`, `I18n` and other readers, never a service with side effects. They read `ConfigManager.live`, not `.config`, so an editor's unsaved preview shows through ([config-readers](../dev/core/config-readers.md)).
- **Reloads.** A new singleton is picked up on reload. A log error like `module "qs.config" … not a type` means the file isn't where the module expects it (`scripts/log.sh`).
- **Schema before config.** The running axiom validates config.json against the schema it loaded at start ([testing](../dev/testing.md) › Reloads and logs), so confirm it has the new schema before writing the new section into `~/.config/axiom/config.json`.
- **No version bump** for a new section: defaults fill it in.
- **Takeovers** need the user's go-ahead before you turn one on in the live config.

## Check it
- `scripts/dev/verify.sh`
- `scripts/run_tests.sh Config`: every default validates.
- `scripts/check_i18n.py`
- To see its settings: `scripts/dev/shot.sh page Settings`.

## Docs to update
- The feature's doc in `docs/dev/features/` (a new one, with the `> **Files:** / **Config:** / **Related:**` header, if the feature is new) and its line in `docs/dev/README.md`.
- A line for the reader under Readers in [config-readers](../dev/core/config-readers.md). The generated `docs/dev/config/` updates itself.
