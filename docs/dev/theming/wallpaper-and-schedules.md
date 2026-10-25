# Wallpaper and schedules

> **Files:** `services/ui/WallpaperManager.qml`, `services/core/ThemeManager.qml`, `services/apps/DailySchedule.qml`, `components/methods/Schedules.qml`, `components/methods/ShownLook.qml`, `shell/Wallpaper.qml`, `components/surfaces/wallpaper/WallpaperWindow.qml`, `scripts/setWallpaper.sh`, `components/content/WallpaperPicker/WallpaperPicker.qml`, `components/content/ThemePicker/ThemePicker.qml`, `components/forms/SettingRows.qml`
> **Config:** `Appearance.wallpaper.*` (`file`, `perScreen`, `folder`, `mode`, `rotation`, `variants`, `backend`, `daemon`), `Appearance.theme.schedule.*`
> **Related:** [Themes](themes.md), [Night light](night-light.md)

How the wallpaper is drawn, and everything that changes the look on its own: wallpaper rotation, light/dark wallpapers, and the light/dark theme schedule.

### Chosen vs shown
- The config holds only what the user picked: `Appearance.theme` and the fixed wallpapers (`Appearance.wallpaper`/`wallpapers`, read as `Appearance.fixedWallpaper`/`fixedWallpapers`).
- The setup itself (mode, rotation, light/dark wallpapers, schedule, folder, fixed wallpapers) is config, and saved snapshots carry it (`x-snapshot`), so changing it marks the active snapshot modified and restoring one brings it back.
- What changes on its own never writes the config, so a snapshot's unsaved dot and `config.json` move only on explicit changes. ThemeManager shows it at runtime through `methods/ShownLook` (tests: `tst_ShownLook`):
  - `ThemeManager.activeTheme`: the theme showing (the schedule's variant, else `Appearance.theme`);
  - `ThemeManager.shownWallpapers` / `wallpaperFor(monitor)` / `wallpaper` (the primary's): what every surface draws (wallpaper window, desktop, lock screen, overview, picker, the greeter bundle).
- The runtime part is in `~/.local/state/axiom/ui/look.json`: the schedule's variant (`theme: { for, name }`, dropped when a theme is picked by hand), the rotation's wallpapers (`rotated`), `lastRotated`, and `applied` (what the backend was last told).

### Wallpaper backend (ThemeManager `_applyShown`)
- Any change of what's shown (a pick, a rotation, a light/dark switch, a mode switch, a restored config, a monitor connecting) runs `_applyShown`, which tells the backend about the monitors that changed and brings a generated theme in line (`syncGeneratedTheme`).
- `Appearance.wallpaper.backend` (reader `Appearance.wallpaperBackend`):
  - `quickshell` (the default): drawn by `shell/Wallpaper` from `wallpaperFor`, one Background-layer `surfaces/wallpaper/WallpaperWindow` per screen, crossfading.
  - `awww`: runs `setWallpaper.sh`. `Appearance.wallpaper.daemon` starts its daemon (`awww-daemon`) only then, from `WallpaperManager` at start-up.
- Fixed wallpapers are written through `ThemeManager.setWallpaper` / `setWallpapers(map)` → `ConfigManager.setWallpaper(s)` (one save); the rotation's through `ThemeManager.showRotated(map)` (state only).

### WallpaperManager: wallpaper modes
- `Appearance.wallpaper.mode` (reader `Appearance.wallpaperMode`):
  - `fixed`: picks write the config. `next()` here picks a new fixed one (asked for by hand).
  - `rotate`: `wallpaper.rotation` with `interval` (ms, shown in minutes), `random`/`sequential` order (via `methods/Schedules.nextWallpaper`) and `sameOnAll`. `ThemeManager.lastRotated` (state file, so it survives restarts) is checked every 30 s. Triggers: IPC `wallpaper next`, bind `nextWallpaper`, launcher `/nextwallpaper`. A pick by hand shows until the next rotation; a monitor not rotated yet shows its fixed wallpaper.
  - `variant`: `wallpaper.variants.dark`/`light` on every monitor, following `Appearance.darkMode`, derived by `ShownLook` (falling back to the fixed ones when that variant has none). `next()` does nothing here.
- Regenerating the theme:
  - automatic changes regenerate only while a generated theme is active;
  - picks by hand (`pick(url, monitor, variant)`, from `WallpaperPicker`) always do.
- Created from `shell.qml`'s `_services`.

### Theme schedule
- `Appearance.theme.schedule`: light from `lightAt`, dark from `darkAt`.
- An edge calls `ThemeManager.followSchedule(light)`: the variant is shown at runtime, and `Appearance.theme.name` keeps the theme picked. A pick or a light/dark switch by hand (`applyTheme`) writes the config and drops the schedule's variant until the next edge.
- Runs through a `services/apps/DailySchedule`:
  - it fires `due(inWindow)` only on edges: the window opens or closes, the schedule is turned on, or the times are moved across now;
  - so a switch by hand lasts until the next edge;
  - its last state survives reloads.
- The night light uses the same `DailySchedule` (see [Night light](night-light.md)).

### Editing (Themes page)
- The Themes page edits all of it inline:
  - `WallpaperPicker`'s Fixed/Rotate/Light-Dark switch;
  - `ThemePicker`'s Auto.
- Through `forms/SettingRows`: dotted-path `SchemaField` rows saved by `SettingsManager.commitValues`.
