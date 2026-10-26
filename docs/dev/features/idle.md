# Idle and idle inhibit

> **Files:** `backend/internal/idle/`, `backend/internal/wayland/idlenotify/`, `backend/internal/logind/`, `backend/internal/screensaver/`, `backend/internal/daemon/idle.go`, `services/session/IdleManager.qml`, `config/Idle.qml`, `components/views/Settings/IdleStatusCard.qml`, `shell/IdleInhibit.qml`, `components/bar/widgets/IdleInhibitor/IdleInhibitor.qml`
> **Config:** `Idle.*` (reader `Idle`; the daemon reads the section itself)
> **Related:** [Lockscreen](lockscreen.md), [Brightness](brightness.md), [D-Bus](../backend/dbus.md), [Wayland protocols](../backend/wayland.md)

What happens when you step away is the axiom daemon's (`internal/idle`), in place of hypridle, which isn't a dependency anymore. The shell keeps the caffeine switch and shows the state.

### Turning it on
- `Idle.enabled` (off by default; the onboarder's Integrations page recommends it) is an `x-takeover` setting: ask before enabling it on the live config (rule: AGENTS.md › Never, while testing). It replaces an idle daemon of the user's own; a running hypridle shows up as the holder of `org.freedesktop.ScreenSaver` in the card's warning.
- Off, the daemon does nothing about idle: no listeners, no D-Bus connections, no hypridle started or stopped.
- The managed mode's autostart (`Session.autostart`) still skips a plain `hypridle` entry while it's on, so a leftover one doesn't run beside it.

### The steps (`internal/idle/plan.go`)
- `Plan(settings)`: dim, lock, screen off and suspend, each with its timeout (0 is off), in timeout order (ties keep that order), then the user's own `items` that are enabled, timed and run something.
- Each step is a typed action, not a shell line:
  - **Dim** / **undim**: the shell's `brightness` IPC target (`dim` / `dimBy` / `undim`, every monitor, no OSD), until brightness moves to the daemon (stage 3).
  - **Lock**: the locker `axiom lock` uses (`internal/lock`), so `Lockscreen.mode` `none` runs `Lockscreen.lockCommand`.
  - **Screen off / on**: the compositor's socket (`Manager.ScreenPower`: Hyprland `dispatch hl.dsp.dpms`, sway `output * power`, niri `PowerOff/OnMonitors`).
  - **Suspend**: logind's `Suspend`.
  - **The user's own**: `sh -c` in its own process group (`internal/shellcmd`).
- One idle notification per step on the daemon's Wayland connection (`ext_idle_notifier_v1`; v2's input-only kind when `respectInhibitors` is off). A step that fired runs its return when the user comes back. Lock has none: only PAM unlocks.
- Actions run one at a time on one worker, in order, so dim always comes before lock.
- A config change arms the listeners again only when the plan (or `respectInhibitors`) differs. A re-exec arms them anew, so idle counts from the handoff.

### What holds idle off
With `respectInhibitors` on:
- The compositor holds the notifications off for Wayland inhibitors: caffeine's surface, a video player's.
- The daemon holds them off itself for:
  - Apps calling `org.freedesktop.ScreenSaver.Inhibit` (`internal/screensaver`). The daemon takes the name while idle is on, and drops an app's inhibitors when it leaves the bus.
  - logind's idle inhibitors (`systemd-inhibit --what=idle`): `BlockInhibited`, listed by `ListInhibitors`.
- When another program holds `org.freedesktop.ScreenSaver`, axiom reports who (`idle.state`'s `screensaver.owner`). niri answers it itself and applies it to its own notifications: that one isn't a problem (`compositor`), anything else is warned about on the card.
- With it off, only caffeine counts, and the daemon applies that itself, as input-only notifications ignore the compositor's inhibitors.
- When something starts holding idle off, every listener is disarmed and the steps that fired run their return (the screens come back when a video starts). They arm again when it lets go; `SimulateUserActivity` restarts them too.

### logind (`internal/logind`)
- The session: `$XDG_SESSION_ID`, else the daemon's own, else the user's display session (a daemon outside the session's scope has none of its own).
- `Session.Lock` (`loginctl lock-session`) locks, while `Idle.enabled` only: a user's own hypridle would also answer it.
- Before sleep (`PrepareForSleep(true)`), with `lockBeforeSleep`: a delay inhibitor held all along keeps sleep waiting while the screen locks, up to logind's `InhibitDelayMaxUSec` less half a second; then it's let go. On waking it's taken again, and with `screenOnAfterSleep` the screens are turned on.
- A lost bus is dialled again every 30 s.

### The shell
- `IdleManager` (`services/session/`, from `shell.qml`'s `_services`):
  - `status`: `off`, `running`, `inhibited`, `unsupported` (no `ext_idle_notifier_v1`) or `unavailable` (no daemon), from `idle.state` (a push on the `idle` topic; `idle.get` after each hello).
  - `inhibitors`, `screensaverHolder`.
  - Caffeine: `caffeine`, `toggle()` and the `idleInhibit` IPC target. It's kept in a `PersistentProperties`, so it survives QML reloads but not restarts. It is sent to the daemon (`idle.caffeine`, shell only) on change and after each hello.
- `shell/IdleInhibit.qml` holds the Wayland inhibitor itself. While caffeine is on, it maps a 1 px click-through Background-layer window on the primary monitor, because an inhibitor needs a surface. It therefore works without the bar widget (`bar/widgets/IdleInhibitor`).
- Settings → Idle starts with `IdleStatusCard`: the status, what holds idle off, and the ScreenSaver warning.

### Testing
- Go: `internal/idle` (the plan, and the service against a fake notifier, a fake bus and `logind/logindtest`), `wayland/idlenotify` (`wiretest`), `logind`, `screensaver`.
- Live: only in a nested compositor (`scripts/dev/nested.sh`) under `dbus-run-session`, on a scratch config with short timeouts, and **`Idle.suspend.timeout` 0**: logind is the real system bus. Check with `systemd-inhibit --what=idle sleep 30`, and `gdbus call --session -d org.freedesktop.ScreenSaver -o /org/freedesktop/ScreenSaver -m org.freedesktop.ScreenSaver.Inhibit app why`.

### A user's own hypridle
With Idle off, for the lock screen's `quickshell` mode, a user's own hypridle should use:
- `lock_cmd = axiom lock`
- `before_sleep_cmd = loginctl lock-session`

For `none` mode it should have no axiom references. See [Lockscreen](lockscreen.md).
