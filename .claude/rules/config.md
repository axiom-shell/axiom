---
paths:
  - "qml/config/**"
---

# Config (`qml/config/`)

Readers (`<Section>.qml` / `<Section>Config.qml`), the schema's YAML (`schema/`; the built `json/config.schema.json` is gitignored), `themes/`, `i18n/`. Docs: `docs/dev/core/config-readers.md`, `config-manager.md`, `schema-annotations.md`; per setting, its readers and users: `docs/dev/config/<Section>.md` (generated). Recipes: `/setting`, `/config-section`, `/migration`.

- **A reader** is `pragma Singleton` `QtObject { readonly property var _c: ConfigManager.live.<Section>; readonly property <type> x: _c.x }` (copy `PolkitConfig.qml`). It reads `ConfigManager.live` (saved config plus editors' previews), never `.config`, except a member exposing the saved config by name (`BarsConfig.savedBars`).
- **A new setting**: a property in `schema/sections/<Section>.yaml` with `default`, `title`, `description` (and `x-group` to pick its card), plus a reader property. Additive keys need no migration; renames and reshapes do (schema first, then the step).
- **A new section**: `schema/sections/<Section>.yaml` listed in `schema/index.yaml`, with `x-category`, `title`, `description`, `additionalProperties: false`, plus a reader. Unknown sections are pruned at load.
- `x-scope` is `look`, `personal`, `commands` or `machine` (inherited; the root is `machine`): what a shared config or snapshot carries (`docs/dev/core/saved-configs-sharing.md`). Set it on anything in a `look` or `personal` section that names a monitor, path or account (`machine`) or runs something (`commands`).
- After a schema change, `scripts/generate.sh` (or verify.sh) rebuilds the JSON, then the reference docs; `gen_docs.py` alone reads the stale schema. The live shell keeps its old schema outside dev mode: test schema changes nested or with `axiom config validate`.
- `i18n/*.json` and config.json are watched: rewrite them atomically (temp file + rename).
