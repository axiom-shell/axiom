# Brightness

> **Files:** `services/system/BrightnessManager.qml`, `components/content/Brightness/Brightness.qml`, `components/surfaces/osd/OSDBar.qml`
> **Config:** none of its own (the module's `monitor` property; OSD `brightness` bars)
> **Related:** [OSD](osd.md), [Idle](idle.md) (dim/undim), [Utility modules](../overlay/utility-modules.md)

Per-monitor brightness through backlight or DDC, the Brightness overlay module, and OSD brightness bars.

### BrightnessManager
- **`displays[screenName]`** gives each monitor's controller:
  - **`backlight`:** for an `eDP` / `LVDS` / `DSI` screen. Read from `/sys/class/backlight`, written with `brightnessctl`.
  - **`ddc`:** for monitors that `ddcutil detect` maps to a DRM connector. Uses VCP 0x10.
- **When it reads:**
  - Detection runs at startup and on screen changes.
  - Values are read then, and again when the OSD opens (`refresh`).
  - Never polled.
- **Writing:**
  - `set` / `stepBy` update the value at once.
  - Writes are coalesced per monitor: one process in flight, with the latest value next.
- **`brightnessChanged(name)`** fires only for axiom's own sets, so the OSD opens on them.
  - Brightness changed outside axiom is picked up when the OSD opens (`OSDTriggers` calls `refresh`).
- **Several monitors:**
  - `names` comes from `namesKey`, a string that only notifies when a monitor comes or goes.
  - `average(names)`.
  - `setMany(names, value, silent)`.
- **IPC `brightness`:** `up`, `down`, `set <percent>`, all on the focused monitor. The bind actions are `brightnessUp` / `brightnessDown`.
  - `dim <percent>` / `undim` are used by idle (see [Idle](idle.md)).
- Created from `shell.qml`'s `_services`.

### Brightness module (`content/Brightness`)
- **`monitor`:**
  - `*` (the default) means every monitor with a controller, at their mean;
  - empty means the primary;
  - or a monitor's name.
- **Sliders:**
  - They scroll at any size: the shared slider first, then (on all monitors) one per monitor.
  - The shared one greys out while the monitors differ. A click on it sets them all to their mean.
- It sets silently, so it doesn't open the OSD.

### OSD brightness bars
- An OSD `brightness` bar with `allMonitors` sets every monitor. It shows their mean, and any of them changing pokes it.
- The brightness keys still step only the focused monitor.
- See [OSD](osd.md).
