# Wallpaper and schedules

> **Files:** `services/ui/WallpaperManager.qml`, `services/core/ThemeManager.qml`, `services/core/DailySchedule.qml`, `components/methods/Schedules.qml`, `components/methods/ShownLook.qml`, `shell/Wallpaper.qml`, `components/surfaces/wallpaper/WallpaperWindow.qml`, `components/surfaces/wallpaper/WallpaperView.qml`, `components/surfaces/wallpaper/shaders/`, `components/methods/WallpaperTransitions.qml`, `components/methods/WallpaperFill.qml`, `scripts/check_shaders.py`, `backend/internal/files/list.go`, `components/content/WallpaperPicker/WallpaperPicker.qml`, `components/content/ThemePicker/ThemePicker.qml`, `components/forms/SettingRows.qml`
> **Config:** `Appearance.wallpaper.*` (`file`, `perScreen`, `folder`, `collection`, `subfolders`, `mode`, `rotation`, `variants`, `transition`, `fill`, `parallax`), `Appearance.theme.schedule.*`
> **Related:** [Themes](themes.md), [Night light](night-light.md)

How the wallpaper is drawn, and everything that changes the look on its own: wallpaper rotation, light/dark wallpapers, and the light/dark theme schedule.

### Chosen vs shown
- The config holds only what the user picked: `Appearance.theme` and the fixed wallpapers (`Appearance.wallpaper`/`wallpapers`, read as `Appearance.fixedWallpaper`/`fixedWallpapers`).
- The setup itself (mode, rotation, light/dark wallpapers, schedule, folder, fixed wallpapers) is config, and saved snapshots carry it (`x-snapshot`), so changing it marks the active snapshot modified and restoring one brings it back.
- What changes on its own never writes the config, so a snapshot's unsaved dot and `config.json` move only on explicit changes. ThemeManager shows it at runtime through `methods/ShownLook` (tests: `tst_ShownLook`):
  - `ThemeManager.activeTheme`: the theme showing (the schedule's variant, else `Appearance.theme`);
  - `ThemeManager.shownWallpapers` / `wallpaperFor(monitor)` / `wallpaper` (the primary's): what every surface draws (wallpaper window, desktop, lock screen, overview, picker, the greeter bundle).
- The runtime part is in `~/.local/state/axiom/ui/look.json`: the schedule's variant (`theme: { for, name }`, dropped when a theme is picked by hand), the rotation's wallpapers (`rotated`), `lastRotated`, and the shuffle's round (`shuffle`, `ThemeManager.shuffleBag`).

### Drawing it
- `shell/Wallpaper` draws `wallpaperFor` on one Background-layer `surfaces/wallpaper/WallpaperWindow` per screen, through a `WallpaperView`. The lock screen and greeter backdrops (`ScreenLayoutView`) are `WallpaperView`s too, so a change while locked plays the same transition.
- `WallpaperView` holds two hidden `Image`s, the one shown and the one loading the next (a source it held last, dark → light → dark, isn't loaded again), and draws them through one `ShaderEffect`:
  - At rest its shader is `show` (the new image alone); the scene graph redraws only on a change, so idle costs what a plain Image did.
  - Once the next image is ready it reads `ThemeManager.transition` (`{ seed, forced }`), asks `WallpaperTransitions.pick(Appearance.wallpaperTransition, …pool, seed, forced)` for `{ name, angle, origin, seed }`, switches the shader to that one and animates `progress` 0 → 1 over `transition.duration` (InOutCubic), then back to `show`. A new wallpaper mid-transition ends the running one at once.
  - `none`, or `Appearance.animations` off: it switches at once. The very first wallpaper fades in over the background.
  - `ThemeManager.transition` gets a fresh random seed on each change of what's shown (not on a re-evaluation showing the same, such as `lastRotated` saving), so every screen changing together plays the same transition, direction and origin. `forceTransition(name)` makes the next change play `name` (the preview).
- **Shaders** (`surfaces/wallpaper/shaders/`): `common.glsl` (the uniform block, `fromColor`/`toColor` sampling each image through its rect and painting `background` outside it, and the `reveal`/`along`/`noise` helpers) is prepended to each `<name>.frag`; at progress 0 each shows the old image and at 1 the new one, exactly. Qt 6 loads only precompiled shaders, so each `.frag.qsb` is committed beside its source: `scripts/check_shaders.py --build` rebuilds the stale ones (qsb from qt6-shadertools, `--qt6`, in a pack Qt 6.4+ reads) and records each source's hash in `stamps.txt`; the check (verify.sh on a shader change, CI's checks job) fails on a source changed since, without needing qsb. A new transition is a `.frag`, its name in `WallpaperTransitions.names` and the schema's `transition` enums, then `--build`.
- **Fill** (`Appearance.wallpaper.fill`: crop, fit, stretch, center): `WallpaperFill.rect` places each image on the screen (screen units, handed to the shader as `fromRect`/`toRect`), `decodeSize` sets what it's decoded at, and `fillMode` maps it for plain Images (the overview's cells). The picker's thumbnails stay cropped.
- **Parallax** (`Appearance.wallpaper.parallax`): the window draws the image `strength`% larger and slides it within the overflow by `WallpaperFill.parallax(activeId, spec)`: by column and row on the grid layout, else by place along one axis, vertical where `supports.verticalWorkspaces` (niri), the order the compositor keeps where `supports.dynamicWorkspaces`. The shift animates (`animSlow`).
- Any change of what's shown (a pick, a rotation, a light/dark switch, a mode switch, a restored config, a monitor connecting) brings a generated theme in line (`ThemeManager.syncGeneratedTheme`).
- Fixed wallpapers are written through `ThemeManager.setWallpaper` / `setWallpapers(map)` → `ConfigManager.setWallpaper(s)` (one save); the rotation's through `ThemeManager.showRotated(map)` (state only).

### WallpaperManager: wallpaper modes
- `Appearance.wallpaper.mode` (reader `Appearance.wallpaperMode`):
  - `fixed`: picks write the config. `next()` here picks a new fixed one (asked for by hand).
  - `rotate`: `wallpaper.rotation` with `interval` (ms, shown in minutes), `random`/`sequential` order and `sameOnAll`. `random` shuffles (`methods/Schedules.shuffleWallpaper`): it draws from the round in `ThemeManager.shuffleBag`, so each wallpaper shows once before any repeats; `sequential` takes the next by name (`Schedules.nextWallpaper`). `ThemeManager.lastRotated` (state file, so it survives restarts) is checked every 30 s, unless `WallpaperManager.rotationHeld` (`rotation.pause`: a fullscreen window on any screen, `LockManager.builtinLocked`, `BatteryManager.onBattery`); when the hold lifts and the time has passed it rotates at once. Triggers: IPC `wallpaper next`, bind `nextWallpaper`, launcher `/nextwallpaper`. `WallpaperManager.random()` (IPC `wallpaper random`, bind `randomWallpaper`, launcher `/wallpaper random`) is a pick by hand of a random file instead. A pick by hand shows until the next rotation; a monitor not rotated yet shows its fixed wallpaper.
  - `variant`: `wallpaper.variants.dark`/`light` on every monitor, following `Appearance.darkMode`, derived by `ShownLook` (falling back to the fixed ones when that variant has none). `next()` does nothing here.
- Regenerating the theme:
  - automatic changes regenerate only while a generated theme is active;
  - picks by hand (`pick(url, monitor, variant)`, from `WallpaperPicker`) always do.
- Created from `shell.qml`'s `_services`.
- IPC `wallpaper preview <transition>` and launcher `/transition <name>` (`WallpaperManager.preview`) go to the next wallpaper with that transition.

### The list of wallpapers (WallpaperManager `images`, `collections`)
- The daemon lists them (`file.list`, `backend/internal/files/list.go`: the jpg, jpeg, png and bmp files, links to files included, hidden ones and links to folders left out, by name, at most 20000): `folder`, or its subfolder `collection` (a path inside it), and every folder under it with `subfolders`. A second listing of the whole folder gives `collections`, the folders holding images: the picker's folder field and the setting's suggestions (`x-suggestions: wallpaperCollections`).
- Nothing watches the folders: the list is fetched again on the daemon's hello, on a change of the folder, collection or subfolders, as the picker opens, and before each `next()` / `random()`, so a new file shows up then.

### Theme schedule
- `Appearance.theme.schedule`: light from `lightAt`, dark from `darkAt`.
- An edge calls `ThemeManager.followSchedule(light)`: the variant is shown at runtime, and `Appearance.theme.name` keeps the theme picked. A pick or a light/dark switch by hand (`applyTheme`) writes the config and drops the schedule's variant until the next edge.
- Runs through a `services/core/DailySchedule`:
  - it fires `due(inWindow)` only on edges: the window opens or closes, the schedule is turned on, or the times are moved across now;
  - so a switch by hand lasts until the next edge;
  - its last state survives reloads.
- The night light uses the same `DailySchedule` (see [Night light](night-light.md)).

### Editing (Themes page)
- The Themes page edits all of it inline:
  - `WallpaperPicker`'s Fixed/Rotate/Light-Dark switch;
  - `ThemePicker`'s Auto.
- Through `forms/SettingRows`: dotted-path `SchemaField` rows saved by `SettingsManager.commitValues`.
