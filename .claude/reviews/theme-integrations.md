# theme-integrations
reviewed: c4866c0 2026-11-01  (full)

A sound, well-tested system: table, templates, goldens, schema switches with `x-hookup` and reader properties line up for all 22 integrations, and the writer and the hookup keep their safety promises. Open: ncspot's splice can drop the end of `config.toml` on a rare path, and kitty's live reload only reaches a socket named `/tmp/kitty-*`.

## Open findings
- Major: [ncspot's splice keeps nothing after a begin marker that follows the end marker](../../docs/dev/issues.md#ncspots-splice-keeps-nothing-after-a-begin-marker-that-follows-the-end-marker)
- Major: [Kitty reloads only when its socket is /tmp/kitty-*](../../docs/dev/issues.md#kitty-reloads-only-when-its-socket-is-tmpkitty-)
- Cleanup: "fzf's flags rebuilt in Go where a template does" (fixed, row 20 core-ui-theming-07)
- Cleanup: "Two hand-written cmp.Or in the theme packages" (fixed, row 20 core-ui-theming-01)
- Cleanup: [The onboarder's integration commands are a hand-kept list in ThemeManager](../../docs/dev/issues.md#the-onboarders-integration-commands-are-a-hand-kept-list-in-thememanager)

### A theme name with a quote breaks wezterm's color file
- **Where:** `backend/internal/theme/integrations/templates/wezterm.toml:6`
- **What:** `origin_url = "axiom: ${THEME_NAME}"` puts the name in a TOML string; `clean` only replaces control characters, so a community or hand-made theme named with `"` or `\` writes a file wezterm can't parse (shipped and generated names are safe). Fix: drop `origin_url` (line 1's comment names the theme) or escape it in an `extra`.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the theme-integrations system

### A comment in the daemon's hookup methods stops mid-sentence
- **Where:** `backend/internal/daemon/hookup.go:43`
- **What:** "// The targets asked for, and the profiles.ini files of a browser's" ends there. Fix: finish it ("… of a browser's per-profile targets (the schema's x-profiles)").
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the theme-integrations system

### The Neovim doc says every shipped theme is mapped
- **Where:** `docs/dev/theming/theme-integrations.md` (Neovim)
- **What:** "`M.map` maps every shipped theme's file stem", but `alucard`, `nord-light`, `submarine-sonar` and `submarine-sonar-light` are left to the palette on purpose (`NvimModule`'s exceptions). Fix: "every shipped theme with a colorscheme plugin".
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the theme-integrations system

## Contract
Holds: the daemon writes only axiom's files (plus `IfMissing` main configs, ncspot's block and kdeglobals' groups, the documented exceptions); only Apply on the user's click edits a user's config (`hookup.apply` refused off the shell's connection); reloads are `Live`-only; a missing app doesn't fail its integration; runs join (latest theme per key, panic resets `running`); `accept` errors are `bad_request`; Apply's safety list (one backup per file and Apply, links followed and kept, read-only skipped or wrapped, copy never overwrites, nothing deleted); profiles from `x-profiles`; `ThemeManager._themed` avoids a double run at load and runs a newly switched-on integration alone. Every `Table` key has a schema switch with `x-hookup`, a reader property and goldens (`integrate_test.go` compares table and schema).

## Coverage
Read deeply: `backend/internal/theme/integrations/` (table, merge, profiles, integrations.go 55–239), `backend/internal/theme/integrate.go`, `effects.go`, `backend/internal/hookup/hookup.go`, `backend/internal/compositor/edit/hookup.go`, `backend/internal/daemon/hookup.go`, `theme.go`, `services/ui/IntegrationHookupManager.qml`, `components/forms/IntegrationHookup.qml`, `config/ThemeIntegrations.qml`, ThemeManager's integration parts. · Outlined: `scripts/templates/nvim/axiom_theme.lua`, the schema YAML, templates and tests (by grep). · Skipped: the rest of ThemeManager (the theming system's).

## History
- 2026-11-01 full: 8 findings (2 Major, 3 Cleanup, 3 Minor); recorded
