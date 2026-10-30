# Themes

> **Files:** `services/core/ThemeManager.qml`, `components/methods/ThemeFamilies.qml`, `config/Theme.qml`, `config/json/theme-defaults.json`, `config/themes/`, `scripts/gen_theme_template.py`, `backend/internal/theme/`, `backend/internal/theme/palette/`, `components/views/Themes/Themes.qml`, `components/content/ThemePicker/ThemePicker.qml`, `components/content/Palette/Palette.qml`
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
- `themeFamilies`: one entry `{ label, dark, light, shared, generated, community }` per theme, built by `methods/ThemeFamilies` (`tests/tst_ThemeFamilies.qml`). `ThemeFamilies.previewOf(families, name)` gives one theme's preview colors by name (the onboarder's example cards).
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
- Also read by theme generation (`backend/internal/theme`, from the binary's embedded copy).

### Generation from a wallpaper
- `ThemeManager.generateThemesFromWallpaper` calls axiom's `theme.generate` (`{ wallpaper }`, an absolute path; `daemon/theme.go`). One call writes a `generated/wallpaper-<style>-dark|light` pair per style into `Paths.generatedThemesPath`, each file atomically (`fsx.WriteFile`), and answers the paths. A failure (no such file, not an image, a write refused) is an `axerr` kind whose message `generationFailed` shows; without axiom nothing is generated.
- `backend/internal/theme` is the edge: it decodes the image (PNG, JPEG, BMP: the wallpaper list's formats, plus WebP and GIF for a wallpaper set by path; BMP and WebP through `golang.org/x/image`), refusing one over Pillow's decompression-bomb limit (about 89 MP) from its header (it's decoded whole, in the daemon), and writes the files. `backend/internal/theme/palette` (pure) does the colour work, with golden tests (`testdata/*.golden`, `go test -update` rewrites them) and property tests (contrast, ramp direction, each style's character).
- Styles (`palette.Styles`): `tonal`, `vibrant`, `faithful`, `muted`, `alternate`. They are factors on the one build, like Material's scheme variants.
- Algorithm:
  - the image is averaged down to 128 px on its longer side and clustered in OKLab into up to 24 candidate colors;
  - candidates are scored as Material scores seeds (hue share and chroma); the best becomes the seed, in `base0F` as `accent`;
  - the palette is built in OKLCH from targets measured off the hand-made themes: a tinted neutral ramp, and accents that keep their slot's hue cell (red stays red) but lean toward the wallpaper's colours there, or else rotate toward the seed;
  - every accent is pushed to 3:1 contrast against `base00`.
- Moved from the Python script generate_theme.py (numpy, Pillow) to Go in roadmap row 8, on purpose not bit-for-bit (maintainer: "ensure the go implementation is as good as it can be and faithful to go - color drift is okay and go is the forever home so changes now are better"). What differs from the Python:
  - clustering is deterministic: pixels are binned in OKLab, and each k-means start is the bin with the most to gain (weight × squared distance to the nearest start), k-means++'s choice without the random draw, so a stray pixel weighs little and an image always gives the same colors;
  - the thumbnail is a plain area average (up to 8×8 samples a pixel), not Pillow's bicubic with JPEG draft decoding;
  - an accent taking the wallpaper's colour takes the weighted mean of the candidates in its cell, not the heaviest one alone, so a small change to the image moves it slightly instead of jumping between candidates.
  - So a wallpaper's generated themes may look different once, the first time they're generated again after the move (the Python's own k-means changed visibly with its random seed on about a third of wallpapers). An image whose clustering doesn't depend on the start (the bands golden) gives the Python's colours exactly.
- When automatic wallpaper changes regenerate: see [Wallpaper and schedules](wallpaper-and-schedules.md).

### Themes page
- `views/Themes/Themes.qml`, the `Themes` view type. It sits in `Overlay.items` like any other view, with nothing to configure.
- A `BaseView` in the editors' shape (see [Editors pattern](../core/editors-pattern.md)). It hosts ordinary modules directly, as the onboarding Look page does, each streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)):
  - `WallpaperPicker` at `sideWidth`. Two cards tall, it adds a monitor picker and a preview, and sets the picked monitor's wallpaper.
  - `ThemePicker`: the theme list and the light mode switch (plus Auto, see [Wallpaper and schedules](wallpaper-and-schedules.md)). The list is three folding groups (`reusable/FoldingSection`): Built-in (`config/themes/`), Imported (community setups' palettes) and Generated. Which are folded is `ThemeManager.foldedGroups` (`toggleGroup`, kept in the look state).
  - A column of `Palette` over a Look card:
    - `Palette`: the 16 base colors with their hex, and under each tile the semantic names that map to it (`Theme.roles`).
    - The Look card: `SettingRows` for font, corner radius and animations, and a link to Settings → Look & Feel.
