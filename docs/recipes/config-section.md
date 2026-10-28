# Recipe: a new config section and its reader

> **Use when:** a feature needs settings of its own that don't belong in an existing section. For one more key in an existing section see [setting](setting.md).
> **Copy from:** `config/PolkitConfig.qml` (minimal reader), `config/NotesConfig.qml` (derived values); schema → `properties.Polkit` (minimal) or `properties.Battery` (with `x-order`)
> **Docs:** [config-readers](../dev/core/config-readers.md), [config-manager](../dev/core/config-manager.md), [schema-annotations](../dev/core/schema-annotations.md), [settings-page](../dev/core/settings-page.md)

## Files to touch
1. `config/schema/sections/<Section>.yaml` (and the name in `config/schema/index.yaml`'s `sections`, where it sits in the order): an object with `x-category`, `title`, `description`, `additionalProperties: false`, `properties` (each with a `default`), optionally `x-order`.
2. `config/<Section>.qml`, or `config/<Section>Config.qml` when `<Section>` is also a type name (a bar widget, module, view or Quickshell type), as with `BatteryConfig`, `OSDConfig`, `LauncherConfig`.
3. The service and UI that use it.
4. `config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys, empty, to every language and the template.

## Skeleton
```json
"Polkit": {
  "type": "object",
  "x-category": "Screen & Power",
  "title": "Authentication prompts",
  "description": "What this section is for, in the user's terms.",
  "additionalProperties": false,
  "x-order": ["enabled"],
  "properties": {
    "enabled": {
      "type": "boolean",
      "title": "Use axiom's prompt",
      "default": false,
      "description": "…"
    }
  }
}
```
```qml
pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Polkit section: whether axiom is the session's polkit
// agent (PolkitManager)
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Polkit

  readonly property bool enabled: _c.enabled
}
```

## Steps
1. **Schema section.**
   - `x-category` must be one of the root's `x-categories`: General, Look & Feel, Hyprland, Workspaces, Overlay & Popouts, Dock & OSD, Launcher, Notifications, Screen & Power, Calendar, Modules, Maintenance.
   - Add `"x-scope": "look"`, `"personal"` or `"commands"` only if the section should travel with examples and exports. Otherwise it inherits the root's `machine`.
2. **Reader.**
   - Imports are only `QtQuick` and `qs.services.core` (for `ConfigManager`), plus other readers if needed.
   - Write one `readonly property` per key that is used, as `_c.<key>`. No `??` fallbacks.
3. **Use it:** services read it to act; UI binds to it.
4. **Hand-built settings UI:** only if the generated form can't express it. Add `x-card: {file: <Name>, title: …}` (`components/views/Settings/<Name>Card.qml`) or `x-intro`.

## Gotchas
- **Sections unknown to the schema are pruned on load**, with a warning. A key missing from the schema vanishes from the user's config on the next save.
- **Reader naming:** the name must not collide with a type the reader's users can see (bar widgets, content, views, Quickshell types). `check_structure.py` reports two same-named types in one file's scope.
- **Hot reload:** a new singleton is picked up on reload (qs 0.3.1). Check `scripts/log.sh` for `module "qs.config" … not a type`-style errors.
- **Schema before config:** the running axiom validates `config.json` against the schema it loaded at its start (`AGENTS.md` › Running / reloading), so confirm it has the new schema before writing the new section into `~/.config/axiom/config.json`.
- **Layering:** readers read only `ConfigManager`, `ThemeManager`, `I18n` and other readers, never a service with side effects.
- **No `version` bump** for a new section: defaults fill it in.
- **Takeovers:** settings that take over something on this PC (a system agent, a daemon) get `x-takeover: true`, and on the live config they need the user's go-ahead before you turn them on.

## Verify
- `scripts/dev/verify.sh`
- `scripts/run_tests.sh Config` (defaults validate; every section has a valid default)
- `scripts/check_i18n.py`
- To see its settings: `scripts/dev/shot.sh page Settings`.

## Docs to update
- The feature's doc in `docs/dev/features/` (create one if new, with the `> **Files:** / **Config:** / **Related:**` header) and its line in `docs/dev/README.md`.
- The table in `docs/dev/core/config-readers.md`. The generated `docs/dev/config/` updates itself.
