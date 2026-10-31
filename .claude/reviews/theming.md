# theming
reviewed: 4d8f880 2026-10-31  (full)

Sound overall: the docs match the code, the pure helpers are tested, and the schedules hold across reloads. Open: the theme-folder rescan lists the working directory ($HOME) as themes, and generated themes regenerate when their wallpaper is reached through a symlink or isn't the primary's.

## Open findings
- Major: [Rescanning the theme folders lists the shell's working directory as themes](../../docs/dev/issues.md#rescanning-the-theme-folders-lists-the-shells-working-directory-as-themes)
- Major: [A generated theme from a wallpaper reached through a symlink is regenerated at every start](../../docs/dev/issues.md#a-generated-theme-from-a-wallpaper-reached-through-a-symlink-is-regenerated-at-every-start)
- Major: [A theme generated from another monitor's wallpaper is replaced by the primary's at the next start](../../docs/dev/issues.md#a-theme-generated-from-another-monitors-wallpaper-is-replaced-by-the-primarys-at-the-next-start)
- Cleanup: [setWallpaperAndGenerate only forwards for one caller](../../docs/dev/issues.md#setwallpaperandgenerate-only-forwards-for-one-caller)
- Cleanup: [~/.current_wallpaper is written but nothing reads it](../../docs/dev/issues.md#current_wallpaper-is-written-but-nothing-reads-it)
- Cleanup: [Six more reader members nothing reads](../../docs/dev/issues.md#six-more-reader-members-nothing-reads) (`Theme.variant` added)

Minor (unrecorded):
- themes.md's family shape leaves out `darkPreview` and `lightPreview`.
- wallpaper-and-schedules.md: "picks always regenerate" isn't true for a light/dark-mode pick of the variant not showing (`setVariantWallpaper`).
- night-light.md: "sent as a slider moves" isn't true for NightLightControls, which saves on release.
- Theme.qml logs an "Initialized" banner on every load.

## Contract
Holds:
- `currentTheme` is loaded eagerly, watched, and kept while its file is mid-write.
- `activeTheme` comes through `ShownLook.theme`, and the schedule never writes the config.
- darkMode comes from the theme's variant.
- Families build as documented: half pairs stay alone, shared lights get `lightFrom`, which is forgotten on other changes.
- theme-defaults fills missing keys.
- Colour names resolve through `Theme.resolveColor`.
- Generation writes atomically.
- The template staleness check runs from verify.sh and the pre-commit hook.
- `_applyShown` tells the backend only about changed monitors.
- Rotation runs from `lastRotated` every 30 s.
- DailySchedule fires only on edges and keeps its state across reloads; the night light's schedule waits for the probe.
- The night light's tool stays undefined until `WaylandManager.known`, and it is re-applied on `greeted`.
- Greeter mode is guarded by `Paths.greeter`.

## Coverage
Read deeply: ThemeManager, Theme, WallpaperManager, ShownLook, Schedules, ThemeFamilies, DailySchedule, NightLightManager, NightLight, WallpaperWindow, shell/Wallpaper, setWallpaper.sh, theme.go, nightlight.go, NightLightStatus · Outlined: ThemePicker, WallpaperPicker, NightLightControls, Themes view, palette.go (Themes), Appearance (theming members) · Skipped: integrate.go, effects.go (theme-integrations), wayland gamma/ctm (dbus-wayland), palette analyze/color (golden-tested), Palette, SettingRows, gen_theme_template.py, ColorTemperature.

## History
- 2026-10-31 full: 9 findings (3 Major, 3 Cleanup incl. one merged into an existing entry, 4 Minor); recorded
