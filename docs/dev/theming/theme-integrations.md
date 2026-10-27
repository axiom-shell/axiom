# Theme integrations

> **Files:** `services/core/ThemeManager.qml`, `services/ui/IntegrationHookupManager.qml`, `config/ThemeIntegrations.qml`, `backend/internal/theme/integrations/`, `backend/internal/theme/integrate.go`, `backend/internal/theme/effects.go`, `backend/internal/daemon/theme.go`, `scripts/integration_hookup.py`, `scripts/templates/nvim/`, `components/forms/IntegrationHookup.qml`, `tests/scripts/test_scripts.py`
> **Config:** `ThemeIntegrations.*`
> **Related:** [Themes](themes.md), [Schema annotations](../core/schema-annotations.md), [Hyprland config modes](../hyprland/config-modes.md)

How axiom themes other apps: the daemon writes each app's own `axiom.*` file, and the hookup makes the app load it. (Rule: AGENTS.md › Config, Theme.)

### Running the integrations (ThemeManager)
- `themeIntegrations()` asks the daemon's `theme.integrate` (`{ theme, keys }`: the theme file, the switched-on `ThemeIntegrations` keys to run) and logs each integration's `error` or `warnings` as a warning.
- `integrations` is the schema's `ThemeIntegrations` boolean keys, in schema order.
- `integrationTitle(key)`: the key's schema title (untranslated).
- `integrationCommands(key)`: the commands any of which shows the app is installed (used by the onboarder). Defaults to `[key]`; exceptions are listed in `_integrationCommands` (e.g. `qt` → `qt6ct`/`qt5ct`, `gtk` → none, every desktop has it).
- When they run:
  - when the active theme's name or contents change;
  - for one integration, as soon as its switch turns on (`_enabledIntegrations` compared against those of the last full run, `_themed`);
  - nothing until the first full run, so loading the config doesn't run them twice.
- A call while a run is going joins it: its keys run after, for the theme asked last (so a quick light-dark-light never ends on the middle one), and it gets an empty `results` back. Each theme file is read once per run.
- Each switch is hooked into its app by `IntegrationHookupManager` (see Hookup below).

### The renderer and the writer (`backend/internal/theme`)
- `theme/integrations` (pure) is the table: per key, the files written (`{config}`, `{state}`, `{data}` are the `$XDG_*_HOME`s, as the apps read them), each a template from its `templates/` (embedded) or built in Go (fzf's flags, Neovim's JSON, qt*ct's palette rows).
  - A template's `${NAME}`s: `THEME_NAME`, `THEME_AUTHOR`, `THEME_VARIANT`, `COLOR_SCHEME` (light/dark), `BASE00`–`BASE0F`, every semantic color as `UPPER_SNAKE` (`backgroundAlt`: `BACKGROUND_ALT`), `ANSI_0`–`ANSI_15`, plus an entry's own (cava's gradient, VS Code's `UI_THEME`). A name nothing sets fails the render; a `.json` template gets its values JSON-escaped.
  - What a theme leaves out comes from `theme-defaults.json`, as `Theme` does.
  - The ANSI palette's chromatic colors (and bright black, dimmer) are floored to readable contrast against the background (`palette.Readable`: the OKLCH hue kept, lightness moved only as far as needed); `text: true` entries floor the semantic colors terminal apps draw text in too (red…info). GTK, Qt, VS Code and Firefox keep them as accents.
  - A per-entry `format` rewrites every color (foot's bare hex, cava's and k9s's quoted, KDE's `r,g,b`).
  - `Each` writes into every folder of a list that exists (Vesktop's and its forks', VS Code's and VSCodium's), `Profiles` into every browser profile the switch's `x-profiles` profiles.ini files list; with none found the integration fails with its `Missing` message.
  - `Requires` skips a file without its command (qt5ct's, qt6ct's colors).
- `theme.Integrator` (`integrate.go`) renders and writes each file atomically (`fsx.WriteFile`: a symlink is written through and kept), and `effects.go` does the rest per key: reshaping a file for the installed app (foot), keeping the app's own files in step (ncspot, kdeglobals), warnings, and telling running apps. Only the daemon's `Live` integrator tells apps; tests never do.
- Each writes only its own `axiom.*` file (a test checks every path of the table).
- A missing main config may be created with the hookup (`IfMissing`: cava's config, GTK's `gtk.css`). One that exists is never touched.
- Reloads (live only): cava (`SIGUSR2`), Ghostty 1.2+ (`SIGUSR2`), Helix 23.10+ (`SIGUSR1`; older versions die of the signal, so the version is asked first), kitty over its remote-control sockets, Neovim over its RPC sockets, ncspot's socket, zathura over D-Bus (`SourceConfig` on each `org.pwmt.zathura.PID-*` name), KDE apps (`notifyChange`), GTK's light/dark through `gsettings` (`color-scheme`, and `gtk-theme` between `adw-gtk3` and `adw-gtk3-dark` when it's one of them), bat's theme cache (`bat cache --build`). Signals go to this user's processes of that name (`/proc`, as `pkill -x`).
- foot: the template is foot 1.20's `[colors]`; a foot accepting `[colors-dark]`/`[colors-light]` (1.28 rejects `[colors]`) gets the theme in both, an older one its cursor in `[cursor]` (asked of the installed foot with `--check-config`).

### Changes from the scripts (2026-10)
The `theme_*.sh` scripts and their shared `theme_env.sh` were ported to Go (maintainer, for stage 4: "ensure the go implementation is as good as it can be and faithful to go - color drift is okay and go is the forever home so changes now are better"). On purpose:
- Contrast flooring keeps the most chroma that fits in sRGB at each lightness (the jq version shrank chroma by steps of 5%), so a floored color comes out a little more saturated: terminal colors on light themes shift slightly. Colors that already passed are unchanged (Catppuccin Mocha's files came out byte for byte the same).
- An app that isn't installed no longer fails its integration: the file is written anyway (an app installed later finds it), and only the reload needs the app.
- JSON files (VS Code, Zed, Neovim) are rendered from templates or Go, so their whitespace and key order differ (Neovim's maps are sorted); their content is the same.
- Firefox's profiles are read by the daemon from the schema's `x-profiles`, no longer through `integration_hookup.py profiles` (that action went).
- The scripts' progress lines are gone (how many kitty and Neovim instances reloaded goes to the daemon's log at info); only problems reach the shell.

### Qt and KDE apps
- The `qt` integration writes qt5ct's / qt6ct's `colors/axiom.conf` (a QPalette per state; for each tool installed, if any) and the KDE color scheme `$XDG_DATA_HOME/color-schemes/Axiom.colors` (`templates/qt.colors`, colors as `r,g,b`). The switch counts as installed with qt*ct or a common KDE app (`ThemeManager._integrationCommands`).
- Qt apps load qt*ct only with `QT_QPA_PLATFORMTHEME`: a managed compositor config sets it to `qt5ct` while the switch is on (`render.SessionEnv`; qt6ct's plugin answers to `qt5ct` too). `ThemeIntegrations.qt` is in `CompositorConfigManager._inputs`, so switching it rewrites the file. The session's own `Session.env` wins; apps started before the next login (qs's children included) keep the old environment.
- KDE apps (KColorScheme) read most of their colors from `kdeglobals`' `[Colors:*]`, `[ColorEffects:*]` and `[WM]` groups, a copy of the chosen scheme that Plasma keeps. The hookup's third target sets `ColorScheme=Axiom` in its `[General]`; from then on the integration keeps those groups (`integrations.MergeKDE`) a copy of `Axiom.colors` on every theme change, replacing only the keys the scheme sets (others, like `[WM] activeFont`, stay), and emits `org.kde.KGlobalSettings.notifyChange` (palette) so running KDE apps re-read it. With any other `ColorScheme` it leaves `kdeglobals` alone. This is the second exception to "only Apply edits a user's config": a file KDE's tools write, after the user opted in.
- That copy reaches only apps reading KColorScheme straight (System Settings). Apps with a color scheme menu (KColorSchemeManager: Okular, Dolphin, Kate, Gwenview) take the scheme named by `[UiSettings] ColorScheme` in their own rc, which falls back to `kdeglobals`'. With none they use the platform theme's (only `QT_QPA_PLATFORMTHEME=kde`, or the portal under `XDG_CURRENT_DESKTOP=KDE`, has one; qt5ct and qt6ct don't), else BreezeLight / BreezeDark, hard-coded (KF 6.31's `kcolorschememanager.cpp`). So the hookup's fourth target sets `ColorScheme=Axiom` in `kdeglobals`' `[UiSettings]` too, in effect for every app whose own menu is left at Default. An app that picked another scheme in its menu keeps it: the integration warns, naming its rc, and changes nothing.
  - Both `kdeglobals` targets go without `accept`: it would match the line in the other group (an `accept` is checked against the whole file).
  - Such apps load the scheme file at start: a theme change reaches them when they restart (the `notifyChange` reaches only apps on the `kde` platform theme).
  - A Flatpak KDE app doesn't see `~/.local/share/color-schemes`, so it doesn't find `Axiom`, and gets the `kdeglobals` copy only where its sandbox shares that file.

### ncspot (an exception)
- ncspot can't include a file, so its integration writes `$XDG_STATE_HOME/axiom/ncspot-theme.toml`.
- It copies that between the two marker lines its Apply put in `config.toml`'s `[theme]` (`integrations.SpliceNcspot`; `x-hookupNote` says so; a test checks the markers are the hookup's text).
- It leaves out keys the user sets in `[theme]` outside the markers. With no markers it only warns.
- It edits the file a symlink points at (only a warning when the user can't write it, e.g. a `/nix/store` link), rewrites only on a change, and sends `reload` to ncspot's socket.

### Neovim
- No line to add: colorschemes come from plugins, often loaded lazily after init.lua.
- The `nvim` integration writes `$XDG_STATE_HOME/axiom/nvim-theme.json` and calls `require("axiom_theme").reload()` in each running instance.
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
- The `firefox` integration reads the same profiles.ini files itself to write `chrome/axiom.css` (imported atop `userChrome.css`, with `toolkit.legacyUserProfileCustomizations.stylesheets` in `user.js`; the browser reads it at startup).
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
- An entry in `integrations.Table` (`backend/internal/theme/integrations/table.go`), usually a template in its `templates/`; anything it does beyond writing the file (a reload) is an entry in `effects` (`backend/internal/theme/effects.go`). Recipe: `docs/recipes/theme-integration.md`.
- A schema boolean under `ThemeIntegrations` with its `x-hookup` (and `x-hookupNote` if needed). `ThemeManager.integrations` picks it up from the schema; a Go test fails when the table and the schema's switches differ.
- A property in `config/ThemeIntegrations.qml` (ThemeManager reads `ThemeIntegrations[key]`).
- An entry in `ThemeManager._integrationCommands` only if the app's binary isn't named `<key>`.

### Testing
- `backend/internal/theme/integrations`: every file of every integration for a dark and a light theme against goldens (`go test ./internal/theme/integrations -update` rewrites them; read the diff), every shipped theme rendered through every integration (JSON and plist parse, colors well-formed), the terminal palette's contrast, and the merges (ncspot, kdeglobals, foot).
- `backend/internal/theme`: the writer in a scratch home (only axiom's files and the missing main configs written, links written through, kdeglobals kept in step only once chosen, the missing-target errors, runs joining one going).
- `tests/scripts/test_scripts.py` runs every hookup on empty configs and checks the Neovim module (`NvimModule`).
- Never apply a hookup to the real configs: run `integration_hookup.py` with a scratch `HOME`/`XDG_CONFIG_HOME` (AGENTS.md › Never, while testing).
