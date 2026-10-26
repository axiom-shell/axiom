# Night light

> **Files:** `backend/internal/nightlight/`, `backend/internal/wayland/ctm/`, `backend/internal/wayland/gamma/`, `services/system/NightLightManager.qml`, `config/NightLight.qml`, `components/views/Settings/NightLightStatus.qml`, `components/content/NightLightControls/NightLightControls.qml`, `services/apps/DailySchedule.qml`
> **Config:** `NightLight.*`
> **Related:** [Wallpaper and schedules](wallpaper-and-schedules.md), [Utility modules](../overlay/utility-modules.md), [Wayland protocols](../backend/wayland.md)

The night light: a screen color temperature, set by the axiom daemon (wlsunset where the compositor can't), on a daily schedule.

### NightLightManager
- `NightLight` section, `NightLight` reader; `views/Settings/NightLightStatus` is the section's `x-intro`.
- **The daemon** (`internal/nightlight`), when `WaylandManager.nightLight` isn't "":
  - `nightlight.set {on, temperature, gamma}` (shell only), sent as a slider moves and again after every hello (a re-exec forgets it).
  - The color: Tanner Helland's fit to blackbody colors (the one `ColorTemperature` shows), relative to 6500 K's so 6500 K is the screen's own, times the Gamma setting as brightness.
  - `ctm`: Hyprland's `hyprland_ctm_control_manager_v1` (what hyprsunset used), a diagonal matrix per output. Bound only while it's on, since holding it keeps every other client out; letting it go puts the identity back.
  - `gamma`: `zwlr_gamma_control_manager_v1` (sway), ramps per output, held only while on.
  - Either follows output hotplug. Another program holding the colors (CTM's `blocked` event; a gamma control's `failed`, which also means an output without gamma tables, as a nested sway's) shows as `NightLightManager.blocked` on the card.
- **wlsunset**, where the compositor offers neither (niri, so far): wlsunset pinned to one temperature, started detached, stopped with `pkill`.
- `tool` is "axiom", "wlsunset" or "" (neither); undefined until the daemon's Wayland connection is ready (`WaylandManager.known`), so wlsunset is never picked, and started, where the daemon is about to say it warms the screens itself.
- `active` is a `PersistentProperties`:
  - probed once per launch (`_probeOnce`): `nightlight.get` from the daemon, or `pgrep` for wlsunset;
  - the schedule waits for the probe.
- A `DailySchedule` turns it on at `startAt` and off at `endAt` (edge-triggered, see [Wallpaper and schedules](wallpaper-and-schedules.md)).
- A new temperature or gamma applies while on (wlsunset restarts, debounced).
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
