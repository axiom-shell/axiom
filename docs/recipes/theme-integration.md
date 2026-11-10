# Adding a theme integration

A theme integration makes another app follow axiom's theme. The daemon writes the app's own `axiom.*` file on every theme change, and a hookup (one click on Apply in Settings → Theme integrations) adds the line to the user's app config that loads it. At the end you have a table entry, usually a template, a schema switch, a reader property and golden test files.

**Copy from:** `alacritty` in `backend/internal/theme/integrations/table.go` with `templates/alacritty.toml` (a rendered template); `zathura` in `backend/internal/theme/effects.go` (telling a running app to reload); `ThemeIntegrations.alacritty` in `qml/config/schema/sections/ThemeIntegrations.yaml` (the switch, its `x-hookup` and `x-hookupNote`).
**Background:** [theme integrations](../dev/theming/theme-integrations.md), [backend](../dev/backend/README.md)

## Files
1. `backend/internal/theme/integrations/templates/<key>.<ext>`: the app's file with `${NAME}` placeholders, if the integration renders one.
2. `backend/internal/theme/integrations/table.go`: `Table["<key>"]`, its files and where they go.
3. `backend/internal/theme/effects.go`: `effects["<key>"]`, only if the app needs telling (a signal, socket or D-Bus call) or a file reshaped for its version.
4. `qml/config/schema/sections/ThemeIntegrations.yaml`: `properties.<key>`, a boolean with `default: false`, `title`, `description` and `x-hookup`. Add `x-hookupNote` for a caveat, and `x-commands` when the app's binary isn't named `<key>` (it decides whether the app counts as installed). `ThemeManager.integrations` is built from these keys, in schema order.
5. `qml/config/ThemeIntegrations.qml`: `readonly property bool <key>: _c.<key>`; `ThemeManager` reads `ThemeIntegrations[key]`.
6. The goldens: `go -C backend test ./internal/theme/integrations -update`.

## Steps
1. Write the template and the table entry. A template can use `${THEME_NAME}`, `${THEME_AUTHOR}`, `${THEME_VARIANT}`, `${COLOR_SCHEME}` (light or dark), `${BASE00}` to `${BASE0F}`, every semantic color in UPPER_SNAKE (`${BACKGROUND_ALT}`) and `${ANSI_0}` to `${ANSI_15}`; a name nothing sets is an error. Options on `tmpl`: `text` (the red-to-info text colors made readable, for apps that draw text in them), `format` (`hex`, `quoted`, `kdeRGB` or your own function) and `extra` (values of its own). Paths start with `{config}`, `{state}` or `{data}`; an app with several config folders uses `Each`, a browser `Profiles`.
2. Add the schema switch with its `x-hookup`. Copy the closest existing entry for the file format; the options (`place`, `section`, `replace`, `accept`) are described in the theme integrations doc, decided in `backend/internal/hookup` and applied to files in `backend/internal/compositor/edit/hookup.go`.
3. Add the reader property.
4. If the app can reload, add an `effects` entry wrapped in `live(…)`, so only the daemon's integrator runs it and no test does.
5. Write the goldens with `-update` and read them.

## Watch out for
- **Only the hookup touches the user's config.** An integration writes only its own `axiom.*` file (`TestOnlyAxiomFiles` checks that every path has an `axiom` part), and only Apply (`hookup.apply`) edits the user's app config, after a backup. ncspot and kdeglobals are the documented exceptions.
- **Version-gated signals:** some apps die of a signal they don't handle yet (Helix before 23.10). Use `signalFrom` with the first version that reloads.
- **Warnings** (`r.warn`) reach the shell log as warnings, so use them only for real problems.
- **Colors stay 6- or 8-digit hex** (`TestEveryThemeRenders` checks it). Convert with a `format`, not inside the template.
- **Never against your real home.** Tests use a scratch home (`scratch` in `backend/internal/theme/integrate_test.go`); don't run an integration or a hookup on your own config.

## Check it
- `go -C backend test ./internal/theme/...`: the goldens, every shipped theme through every integration, the writer in a scratch home, and the table against the schema (`TestTableIsTheSchemas`).
- `go -C backend test ./internal/compositor/edit`: applies every schema hookup to empty configs in a scratch home (`TestEveryHookupApplies`).
- `scripts/dev/verify.sh`: schema, reader, generated docs and the Go checks.

## Docs to update
- [theme integrations](../dev/theming/theme-integrations.md), if the integration needed anything new (a reload, a version gate, a file reshaped).
- The apps table in `docs/features.md` (Theming › Theme integrations).
