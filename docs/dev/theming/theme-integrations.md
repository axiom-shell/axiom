# Theme integrations

> **Files:** `services/core/ThemeManager.qml`, `services/ui/IntegrationHookupManager.qml`, `config/ThemeIntegrations.qml`, `scripts/theme_*.sh`, `scripts/lib/theme_env.sh`, `scripts/integration_hookup.py`, `scripts/templates/`, `components/forms/IntegrationHookup.qml`, `tests/scripts/test_scripts.py`
> **Config:** `ThemeIntegrations.*`
> **Related:** [Themes](themes.md), [Schema annotations](../core/schema-annotations.md), [Hyprland config modes](../hyprland/config-modes.md)

How axiom themes other apps: one script per app writing its own `axiom.*` file, and the hookup that makes the app load it. (Rule: AGENTS.md › Config, Theme.)

### Running the integrations (ThemeManager)
- `themeIntegrations()` runs one `scripts/theme_<key>.sh` per switched-on `ThemeIntegrations` switch.
- `integrations` is the schema's `ThemeIntegrations` boolean keys, in schema order.
- `integrationTitle(key)`: the key's schema title (untranslated).
- `integrationCommands(key)`: the commands any of which shows the app is installed (used by the onboarder). Defaults to `[key]`; exceptions are listed in `_integrationCommands` (e.g. `qt` → `qt6ct`/`qt5ct`, `gtk` → none, every desktop has it).
- A failure, or a `Warning:` line on stderr, is logged.
- When they run:
  - when the active theme's name or contents change;
  - for one integration, as soon as its switch turns on (`_enabledIntegrations` compared against those of the last full run, `_themed`);
  - nothing until the first full run, so loading the config doesn't run them twice.
- Each switch is hooked into its app by `IntegrationHookupManager` (see Hookup below).

### Scripts (`scripts/theme_*.sh`)
- Shared helpers in `scripts/lib/theme_env.sh`:
  - dependency checks;
  - `load_theme`: one jq pass filling what a theme leaves out, as `Theme` does;
  - `export_theme_colors`: every semantic color as `UPPER_SNAKE`, plus `ANSI_0`–`ANSI_15`;
  - `render_template` / `write_atomic`.
  - They fork as little as they can (`snake_upper` in pure bash, one `jq` run per `floor_colors`, one subshell per `map_vars`): every integration runs on each theme change, and the tests run each one on every theme.
- Each script writes only its own `axiom.*` file, under `$XDG_CONFIG_HOME` (as the apps read it).
- A missing main config may be created with the hookup (cava's config, GTK's `gtk.css`). One that exists is never touched by a script.
- Zathura reloads through D-Bus (`SourceConfig` on each `org.pwmt.zathura.PID-*` name).

### Qt and KDE apps
- `theme_qt.sh` writes qt5ct's / qt6ct's `colors/axiom.conf` (a QPalette per state; for each tool installed, if any) and the KDE color scheme `$XDG_DATA_HOME/color-schemes/Axiom.colors` (`templates/qt_template.colors`, colors as `r,g,b`). The switch counts as installed with qt*ct or a common KDE app (`ThemeManager._integrationCommands`).
- Qt apps load qt*ct only with `QT_QPA_PLATFORMTHEME`: a managed compositor config sets it to `qt5ct` while the switch is on (`render.SessionEnv`; qt6ct's plugin answers to `qt5ct` too). `ThemeIntegrations.qt` is in `CompositorConfigManager._inputs`, so switching it rewrites the file. The session's own `Session.env` wins; apps started before the next login (qs's children included) keep the old environment.
- KDE apps (KColorScheme) read most of their colors from `kdeglobals`' `[Colors:*]`, `[ColorEffects:*]` and `[WM]` groups, a copy of the chosen scheme that Plasma keeps. The hookup's third target sets `ColorScheme=Axiom` in its `[General]`; from then on `theme_qt.sh` keeps those groups a copy of `Axiom.colors` on every theme change, replacing only the keys the scheme sets (others, like `[WM] activeFont`, stay), and emits `org.kde.KGlobalSettings.notifyChange` (palette) so running KDE apps re-read it. With any other `ColorScheme` it leaves `kdeglobals` alone. This is the second exception to "only Apply edits a user's config": a file KDE's tools write, after the user opted in.
- That copy reaches only apps reading KColorScheme straight (System Settings). Apps with a color scheme menu (KColorSchemeManager: Okular, Dolphin, Kate, Gwenview) take the scheme named by `[UiSettings] ColorScheme` in their own rc, which falls back to `kdeglobals`'. With none they use the platform theme's (only `QT_QPA_PLATFORMTHEME=kde`, or the portal under `XDG_CURRENT_DESKTOP=KDE`, has one; qt5ct and qt6ct don't), else BreezeLight / BreezeDark, hard-coded (KF 6.31's `kcolorschememanager.cpp`). So the hookup's fourth target sets `ColorScheme=Axiom` in `kdeglobals`' `[UiSettings]` too, in effect for every app whose own menu is left at Default. An app that picked another scheme in its menu keeps it: `theme_qt.sh` warns, naming its rc, and changes nothing.
  - Both `kdeglobals` targets go without `accept`: it would match the line in the other group (an `accept` is checked against the whole file).
  - Such apps load the scheme file at start: a theme change reaches them when they restart (the `notifyChange` reaches only apps on the `kde` platform theme).
  - A Flatpak KDE app doesn't see `~/.local/share/color-schemes`, so it doesn't find `Axiom`, and gets the `kdeglobals` copy only where its sandbox shares that file.

### ncspot (an exception)
- ncspot can't include a file, so `theme_ncspot.sh` writes `$XDG_STATE_HOME/axiom/ncspot-theme.toml`.
- It copies that between the two marker lines its Apply put in `config.toml`'s `[theme]` (`x-hookupNote` says so).
- It leaves out keys the user sets in `[theme]` outside the markers. With no markers it only warns.
- It edits the file a symlink points at (only a warning when the user can't write it, e.g. a `/nix/store` link), rewrites only on a change, and sends `reload` to ncspot's socket.

### Neovim
- No line to add: colorschemes come from plugins, often loaded lazily after init.lua.
- `theme_nvim.sh` writes `$XDG_STATE_HOME/axiom/nvim-theme.json` and calls `require("axiom_theme").reload()` in each running instance.
- `scripts/templates/nvim/axiom_theme.lua` is that module (copied into the user's config by Apply):
  - `M.map` maps every shipped theme's file stem to that theme's usual colorscheme plugin;
  - `setup({ map, fallback })` merges the user's entries over it;
  - any other theme (or one whose plugin lazy.nvim doesn't know) is built from its base16 palette: mini.base16 when installed, else plain highlight groups;
  - then the theme's accent is applied Material-style (`apply_accents`: keywords, titles, the cursor line number, and selection/search/menu backgrounds blended from it), so a wallpaper theme's seed color leads.
- The JSON carries:
  - `colors` (base16);
  - `semantic` (resolved hex);
  - `text` (accent and accentAlt floored to readable contrast against the background).

### Hookup (loading the file from the app's config)
- Each switch's `x-hookup` lists targets:
  - `{ file, text, place, … }`: something Apply can do;
  - `{ text, where }`: something to copy by hand. Examples: wezterm.lua, k9s's YAML, VS Code's and Zed's settings.json, Vesktop's Themes tab.
- Vesktop: Vencord keeps its enabled themes in a JSON array, and reloads `axiom.theme.css` live through its watch on the themes folder. The Flatpak Vesktop's folder is under `~/.var/app/dev.vencord.Vesktop/config/vesktop`.
- `x-hookupNote` says what's peculiar (Alacritty's import order, lazygit's `LG_CONFIG_FILE`, Neovim).

### integration_hookup.py
- `scripts/integration_hookup.py status|apply <key>` (stdlib Python) does the work.
- `place`:
  - `end`: read last, so it wins;
  - `start`: CSS `@import` must come first;
  - `top`: before the first `[section]` (TOML top-level keys, foot's main section);
  - `section`: inside `[section]`, added when missing;
  - `shellrc`: `$SHELL`'s rc; fish gets `conf.d/axiom.fish` with `set -gx`;
  - `copy`: Neovim's module, never overwriting.
- A line already setting the same key is:
  - commented out (`replace: comment`, the default);
  - left beside it (`keep`);
  - or blocks the target (`conflict`).
- `accept`: a regex for an equivalent line that already counts as done.
- `requires`: skips a target without its command.
- `perProfile` targets:
  - repeated for every browser profile listed by the profiles.ini files in the integration's `x-profiles` (Firefox and its forks, native and Flatpak);
  - skipped as `profiles` when there are none;
  - the target's `file` is relative to the profile.
- `integration_hookup.py profiles <key>` prints those profiles. That's how `theme_firefox.sh` finds where to write `chrome/axiom.css` (imported atop `userChrome.css`, with `toolkit.legacyUserProfileCustomizations.stylesheets` in `user.js`; the browser reads it at startup).
- Apply's safety:
  - backs each changed file up beside the real file (`<name>.axiom-bak-<time>`);
  - follows a symlink and keeps it (so a dotfiles repo's file is edited);
  - never writes a file (or a directory) the user can't: such a target is skipped as `readonly`. With `wrapLink` (GTK 4's `gtk.css`, which nwg-look and others link to a theme's file under `/usr/share/themes`), Apply instead replaces the link with a file holding `wrapLink` (`{link}` = the file it pointed at) then the text, and keeps the link as the backup;
  - writes atomically;
  - never deletes a line;
  - does nothing for a target already done.
- `--targets JSON` passes the targets instead of a schema key, with `title` (naming a target above its path) and `note` (replacing the line about where it goes). Used for the compositor's include and autostart lines (CompositorConfigManager; see [Config modes](../compositor/config-modes.md)).

### IntegrationHookupManager and the UI
- `IntegrationHookupManager` runs the script; nothing is polled:
  - `check(key)` → `status[key]`;
  - `apply(key)` → `results[key]`, then checks again, and runs the integration for the current theme when Apply changed something.
- `forms/IntegrationHookup` shows it under a switched-on integration:
  - the status;
  - per target, the text with a copy button and an outline of what Apply will do (backup, link, where it goes, lines commented out);
  - then Apply.
- `SettingsField` adds it under any field with `x-hookup`.
- In settings they are their own category, one folding card per app (`x-card`'s `perField` on `ThemeIntegrations`).
- The onboarder's Integrations page lists the switched-on ones under "Finish setting up".
- Only Apply, on the user's click, edits a user's config.

### Adding an integration
- A `scripts/theme_<key>.sh` script (plus a template in `scripts/templates/` if it renders one).
- A schema boolean under `ThemeIntegrations` with its `x-hookup` (and `x-hookupNote` if needed). `ThemeManager.integrations` picks it up from the schema; there is no hand-kept list.
- A property in `config/ThemeIntegrations.qml` (ThemeManager reads `ThemeIntegrations[key]`).
- An entry in `ThemeManager._integrationCommands` only if the app's binary isn't named `<key>`.

### Testing
- `tests/scripts/test_scripts.py` renders every theme through every script and parses each output as its format, and runs every hookup on empty configs.
- Never apply a hookup to the real configs: run `integration_hookup.py` with a scratch `HOME`/`XDG_CONFIG_HOME` (AGENTS.md › Never, while testing).
