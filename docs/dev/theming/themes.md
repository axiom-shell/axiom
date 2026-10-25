# Themes

> **Files:** `services/core/ThemeManager.qml`, `components/methods/ThemeFamilies.qml`, `config/Theme.qml`, `config/json/theme-defaults.json`, `config/themes/`, `scripts/gen_theme_template.py`, `scripts/generate_theme.py`, `components/views/Themes/Themes.qml`, `components/content/ThemePicker/ThemePicker.qml`, `components/content/Palette/Palette.qml`
> **Config:** `Appearance.theme`
> **Related:** [Theme integrations](theme-integrations.md), [Wallpaper and schedules](wallpaper-and-schedules.md), [Config readers](../core/config-readers.md)

How the active theme is loaded, how themes are grouped into dark/light families, how a theme is generated from a wallpaper, and the Themes page. Read this before touching theme files, `ThemeManager` or the theme picker.

### ThemeManager: the active theme
- Owns `currentTheme`: loaded eagerly, watched, and reloaded when `activeTheme` or the file changes.
- `activeTheme` is the theme showing: `Appearance.theme`, or the variant the light/dark schedule switched to, which never writes the config ([Wallpaper and schedules](wallpaper-and-schedules.md)). Integrations and generation follow `activeTheme`.
- Owns `defaults` (`theme-defaults.json`, see below).
- `Appearance.darkMode` is derived from the theme's `variant`.
- The choice of theme is persisted through `ConfigManager.setTheme`.

### Theme families (discovery)
- `themeFamilies`: one entry `{ label, dark, light, shared, generated, community }` per theme, built by `methods/ThemeFamilies` (`tests/tst_ThemeFamilies.qml`).
- A dark/light pair (each file's `paired` naming the other) is one theme, labelled by the words their names share.
- A family's extra darks (Catppuccin Frappé and Macchiato, Tokyo Storm and Moon, Ayu Mirage, Rosé Pine Moon, Kanagawa Dragon, Nordfox/Carbonfox/Terafox) name its light in `paired` while the light names the main dark back. Each is a family of its own, keeping its name, that shares the light (`shared: true`), as upstream does: those schemes ship one light. No light themes are invented for them.
- `currentFamily`: the family of the active theme. A shared light belongs to the family it was picked from (`lightFrom` in the look state, saved by `applyFamily` / `setLightMode`), else to its main family, so Light then Dark goes back to the dark you started from. `Appearance.theme` changing any other way (a restored or applied config, the settings field) forgets it.
- A dark naming a light that doesn't name a dark back (half a pair) joins no family: both stay themes of their own.
- `applyFamily(family)` picks the variant for the current mode.
- `setLightMode(bool)` switches the current theme's variant by hand (config). The schedule uses `followSchedule(bool)` (runtime only). `Appearance.darkMode` follows the shown theme.

### Theme files
- `config/themes/template/theme.json` is the theme a new one is copied from: empty name, author and pair, plus `theme-defaults.json`'s fallback colors and dark semantic map. `scripts/gen_theme_template.py` writes it, the pre-commit hook runs that when the defaults change, and `test_scripts.py`'s `Themes` fails when it's stale. It sits in a subfolder, so the theme scan (`showDirs: false`) doesn't list it.
- `config/themes/*.json` are static; `Paths.generatedThemesPath` (`~/.local/state/axiom/themes/*.json`, named `generated/<name>`) come from a wallpaper; `Paths.communityThemesPath` (`~/.local/share/axiom/themes/*.json`, named `community/<id>`) are the palettes [community setups](../features/community-setups.md) brought, each a theme on its own (`paired` ignored), listed after the stock ones (`community: true` on their families).
- Static themes keep the hue slots fixed, even where an upstream base16 port reorders them, because the semantic names and the terminal ANSI colors read them by slot:
  - `base08` red, `09` orange, `0A` yellow, `0B` green, `0C` cyan, `0D` blue, `0E` magenta.
- A scheme without some hue fills that slot with its nearest color (Rosé Pine's pine as green, Dracula's purple as blue).
- Each scheme sets `accent` to its signature color.
- Pairing: an extra dark variant points `paired` at its family's light theme, and the light theme points back at the main dark one.

### theme-defaults.json
- `config/json/theme-defaults.json` is the one fallback palette and semantic → base16 map (dark and light).
- Read through `ThemeManager.defaults` by `Theme`, for keys a theme omits and for a missing theme.
- Also read by `scripts/generate_theme.py`.

### Generation from a wallpaper
- `scripts/generate_theme.py`: one run writes a `generated/wallpaper-<style>-dark|light` pair per `STYLES` entry.
- Styles: `tonal`, `vibrant`, `faithful`, `muted`, `alternate`. They are factors on the one build, like Material's scheme variants.
- Algorithm:
  - k-means in OKLab picks candidate colors;
  - the palette is built in OKLCH from targets measured off the hand-made themes;
  - the wallpaper's seed color goes in `base0F` as `accent`.
- Run with the system `python3`; needs numpy and Pillow (system packages). Without them it exits 3, and `ThemeManager` notifies once with the install command (`DependencyManager.installCommand`) and sets `generationUnavailable`.
- When automatic wallpaper changes regenerate: see [Wallpaper and schedules](wallpaper-and-schedules.md).

### Themes page
- `views/Themes/Themes.qml`, the `Themes` view type. It sits in `Overlay.items` like any other view, with nothing to configure.
- A `BaseView` in the editors' shape (see [Editors pattern](../core/editors-pattern.md)). It hosts ordinary modules directly, as the onboarding Look page does, each streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)):
  - `WallpaperPicker` at `sideWidth`. Two cards tall, it adds a monitor picker and a preview, and sets the picked monitor's wallpaper.
  - `ThemePicker`: the theme list and the light mode switch (plus Auto, see [Wallpaper and schedules](wallpaper-and-schedules.md)). The list is three folding groups (`reusable/FoldingSection`): Built-in (`config/themes/`), Imported (community setups' palettes) and Generated. Which are folded is `ThemeManager.foldedGroups` (`toggleGroup`, kept in the look state).
  - A column of `Palette` over a Look card:
    - `Palette`: the 16 base colors with their hex, and under each tile the semantic names that map to it (`Theme.roles`).
    - The Look card: `SettingRows` for font, corner radius and animations, and a link to Settings → Look & Feel.
