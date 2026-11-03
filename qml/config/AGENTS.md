# Config (`config/`)

Reader singletons (`<Section>.qml` / `<Section>Config.qml`), `json/config.schema.json` (the single source of truth, built from its YAML source `schema/` by `scripts/generate.sh` or `axiom schema build`, never committed: edit the YAML), `json/theme-defaults.json`, `themes/`, `i18n/`. The live config and state are in the XDG folders, never here (`docs/dev/core/config-manager.md` › Where files live). Docs: `docs/dev/core/config-readers.md`, `config-manager.md`, `schema-annotations.md`. Every setting, its reader member and its users: `docs/dev/config/<Section>.md` (generated).

**Recipe:** `docs/recipes/setting.md` / `docs/recipes/config-section.md` / `docs/recipes/migration.md`; verify with `scripts/dev/verify.sh`.

- **A reader**: `pragma Singleton`, `import QtQuick`, `import qs.services.core`, `QtObject { id: root; readonly property var _c: ConfigManager.live.<Section>; readonly property <type> x: _c.x … }`. Copy `PolkitConfig.qml` or `BatteryConfig.qml`.
- Readers read only the data owners (`ConfigManager`, `ThemeManager`, `I18n`) and each other. **No `??` fallbacks**: every default is filled at load. Readers read `ConfigManager.live` (the config with editors' unsaved previews laid over it), never `ConfigManager.config`, except a reader exposing the saved config (`BarsConfig.savedBars`).
- **A new setting** = a schema property with a `default` (plus `title`, `description`, `x-group`, in `x-order` if the section has one) + a reader property + `scripts/check_i18n.py --fill`. Purely additive keys need no migration.
- **A new section** = a root `properties.<Section>` with `x-category` (from the root's `x-categories`), `title`, `description`, `additionalProperties: false`, `x-order`, + a new reader. Unknown sections are pruned at load.
- **Renaming or reshaping a key**: edit the schema first, then a format-2 step (`docs/recipes/migration.md`).
- `x-scope`: a setting in a look section that names a monitor, path, account or command needs `machine`/`personal`.
- After changing the schema or a reader, run `scripts/generate.sh` (or verify.sh): it rebuilds the schema JSON, then the reference docs from it (`scripts/gen_docs.py` alone reads the old schema).
- Edit `~/.config/axiom/config.json` and `i18n/*.json` atomically (temp file + rename): they're watched.
