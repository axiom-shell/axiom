# Night light

> **Files:** `services/system/NightLightManager.qml`, `config/NightLight.qml`, `components/views/Settings/NightLightStatus.qml`, `components/content/NightLightControls/NightLightControls.qml`, `services/apps/DailySchedule.qml`
> **Config:** `NightLight.*`
> **Related:** [Wallpaper and schedules](wallpaper-and-schedules.md), [Utility modules](../overlay/utility-modules.md)

The night light: a screen color temperature run through hyprsunset or wlsunset, on a daily schedule.

### NightLightManager
- `NightLight` section, `NightLight` reader; `views/Settings/NightLightStatus` is the section's `x-intro`.
- Runs `hyprsunset -t <K> [-g <gamma>]` (only under Hyprland, whose color transform it drives), or wlsunset pinned to one temperature. Started detached, stopped with `pkill`.
- `active` is a `PersistentProperties`:
  - probed with `pgrep` once per launch (`_probeOnce`), however the tool becomes known;
  - the schedule waits for the probe.
- A `DailySchedule` turns it on at `startAt` and off at `endAt` (edge-triggered, see [Wallpaper and schedules](wallpaper-and-schedules.md)).
- A new temperature or gamma restarts it while on.
- Created from `shell.qml`'s `_services`.

### Entry points
- IPC `nightLight`: `toggle` / `enable` / `disable` / `status`.
- Bind `nightLight`.
- Launcher `/nightlight`.
- The QuickActions tile.

### NightLightControls module
- `NightLightControls` (`content/NightLightControls`; its reader is `NightLight`).
- A switch, warmth and dim sliders (saved on release through `SettingsManager.commitValues`), and a schedule switch.
- A big card adds a round button in the light's color.
