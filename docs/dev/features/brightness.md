# Brightness

> **Files:** `qml/services/system/BrightnessManager.qml`, `backend/internal/brightness/`, `backend/internal/daemon/brightness.go`, `qml/components/content/Brightness/Brightness.qml`, `qml/components/surfaces/osd/systems/Brightness/`, `qml/components/surfaces/osd/design/OSDLevelBar.qml`
> **Config:** none of its own (the module's `monitor` property; OSD `brightness` bars)
> **Related:** [OSD](osd.md), [Idle](idle.md) (dim/undim), [Utility modules](../overlay/utility-modules.md)

Per-monitor brightness through backlight or DDC, the Brightness overlay module, and OSD brightness bars.

### BrightnessManager
- **`displays[screenName]`** gives each monitor's controller:
  - **`backlight`:** for an `eDP` / `LVDS` / `DSI` screen. Read from `/sys/class/backlight` (firmware over platform over raw, as systemd-backlight picks), set through logind's `Session.SetBrightness` (how the session's user may write it, as brightnessctl does).
  - **`ddc`:** for monitors that `ddcutil detect` maps to a DRM connector. Uses VCP 0x10.
- **The daemon does the work** (`backend/internal/brightness`): `brightness.detect` (the backlight with its level, the DDC monitors without theirs), `brightness.get` and `brightness.set` per controller. ddcutil stays a program, run from Go (10 s at most). Each backlight set dials logind afresh. The QML keeps the mapping onto screens, the coalescing and the dimming. Without the daemon (the greeter) there's no brightness.
- **When it reads:**
  - Detection runs at startup and on screen changes.
  - Values are read then, and again when the OSD opens (`refresh`).
  - Never polled.
- **Writing:**
  - `set` / `stepBy` update the value at once.
  - Writes are coalesced per monitor: one `brightness.set` in flight, with the latest value next.
- **`brightnessChanged(name)`** fires only for axiom's own sets, so the OSD opens on them. It fires after the write is marked (`_writing`), so the `refresh` of the OSD opening on it skips the monitor being written instead of running `ddcutil getvcp` beside `setvcp`.
  - Brightness changed outside axiom is picked up when the OSD opens (`BrightnessWatch.opened`, called as its OSD opens, `refresh`es the monitors its bar shows).
- **`icon(level)`**: `brightness_low`, `_medium` or `_high`, for the module, the OSD bar and the Quick actions tile.
- **Several monitors:**
  - `names` comes from `namesKey`, a string that only notifies when a monitor comes or goes.
  - `average(names)`.
  - `setMany(names, value, silent)`.
- **IPC `brightness`:** `up`, `down`, `set <percent>`, all on the focused monitor. The bind actions are `brightnessUp` / `brightnessDown`.
  - `dim <percent>` / `undim` are used by idle (see [Idle](idle.md)). The levels from before `dim` are kept in a `PersistentProperties` (a default child of the Singleton root), so an `undim` after a QML reload still restores them.
- Created from `qml/shell.qml`'s `_services`.

### Brightness module (`content/Brightness`)
- **`monitor`:**
  - `*` (the default) means every monitor with a controller, at their mean;
  - empty means the primary;
  - or a monitor's name.
- **Sliders:**
  - They scroll at any size: the shared slider first, then (on all monitors) one per monitor.
  - The shared one greys out while the monitors differ. A click on it sets them all to their mean.
- Its changes are marked as the pointer's (`ShellManager.onScreen("brightness")`), so an open OSD's brightness bar follows them, and they open one only with `OSD.onScreenChanges` ([OSD](osd.md) › What opens it). Only idle's `dim`/`undim` set silently.

### OSD brightness bars
- An OSD `brightness` bar with `allMonitors` sets every monitor. It shows their mean, and any of them changing pokes it.
- Only a level set through axiom counts as a change (`brightnessChanged`, which `BrightnessWatch` keeps as its state's `setAt`; the Brightness system's `countsWithin` counts a level only within 500 ms of it): one a `refresh` finds (on the OSD opening) or idle dimming's silent set only moves its state on. Every set counts, so a key at 0 % or 100 % (clamped, unchanged) still opens the OSD.
- The brightness keys still step only the focused monitor.
- See [OSD](osd.md).
