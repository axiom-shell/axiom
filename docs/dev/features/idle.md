# Idle and idle inhibit

> **Files:** `backend/internal/idle/`, `backend/internal/wayland/idlenotify/`, `backend/internal/logind/`, `backend/internal/screensaver/`, `backend/internal/daemon/idle.go`, `qml/services/session/IdleManager.qml`, `qml/config/Idle.qml`, `qml/components/views/Settings/IdleStatusCard.qml`, `qml/components/bar/widgets/IdleInhibitor/IdleInhibitor.qml`, `qml/components/content/Caffeine/Caffeine.qml`
> **Config:** `Idle.*` (reader `Idle`; the daemon reads the section itself)
> **Related:** [Lockscreen](lockscreen.md), [Brightness](brightness.md), [D-Bus](../backend/dbus.md), [Wayland protocols](../backend/wayland.md)

What happens when you step away is the axiom daemon's (`internal/idle`), in place of hypridle, which isn't a dependency anymore. The shell keeps the caffeine switch and shows the state; the daemon applies caffeine.

### Turning it on
- `Idle.enabled` (off by default; the onboarder's System page recommends it) is an `x-takeover` setting: ask before enabling it on the live config (rule: AGENTS.md › Never, while testing). It replaces an idle daemon of the user's own; a running hypridle shows up as the holder of `org.freedesktop.ScreenSaver` in the card's warning.
- Off, the daemon does nothing about idle: no listeners, no D-Bus connections, no hypridle started or stopped. Only caffeine still acts: its logind idle inhibitor (below).
- The managed mode's autostart (`Session.autostart`) no longer has a `hypridle` entry by default (the v78 step drops the old default's from saved configs), and still skips a plain `hypridle` one the user added while Idle is on, so it doesn't run beside it.

### The steps (`internal/idle/plan.go`)
- `Plan(settings)`: dim, lock, screen off and suspend, each with its timeout (0 is off), in timeout order (ties keep that order), then the user's own `items` that are enabled, timed and run something.
- Each step is a typed action, not a shell line:
  - **Dim** / **undim**: the shell's `brightness` IPC target (`dim` / `dimBy` / `undim`, every monitor, no OSD), which remembers what each monitor was.
  - **Lock**: the locker `axiom lock` uses (`internal/lockscreen`), so `Lockscreen.mode` `none` runs `Lockscreen.lockCommand`. When that names no locker (empty, or `loginctl lock-session`, which comes back to axiom: `Locker.CanLock`), the daemon sets `Settings.NoLocker`: the plan has no lock step, logind's lock and the lock before sleep are skipped (no sleep inhibitor either), and `idle.state`'s `noLocker` makes the card's status "Doesn't lock".
  - **Screen off / on**: the compositor's socket (`Manager.ScreenPower`: Hyprland `dispatch hl.dsp.dpms`, sway `output * power`, niri `PowerOff/OnMonitors`).
  - **Suspend**: logind's `Suspend`.
  - **The user's own**: `sh -c` in its own process group (`internal/shellcmd`).
- One idle notification per step on the daemon's Wayland connection (`ext_idle_notifier_v1`; v2's input-only kind when `respectInhibitors` is off). A step that fired runs its return when the user comes back. Lock has none: only PAM unlocks.
- Actions run one at a time on one worker, in order, so dim always comes before lock.
- A config change arms the listeners again only when the plan (or `respectInhibitors`) differs. A re-exec arms them anew, so idle counts from the handoff.

### What holds idle off
- **Caffeine**, always (`respectInhibitors` on or off): the daemon holds its own listeners off itself (`idle.state` lists `{source: "caffeine"}` while Idle is on, and says `inhibited`). There is no Wayland inhibitor for it: one needs a surface, and Hyprland (0.57) decides whether an inhibitor counts when it's made, before a layer surface maps, and doesn't look again until a window's focus changes, so a window holding one held nothing after each caffeine-on or reload.
- **Caffeine's logind idle inhibitor**: while caffeine is on, Idle on or off, the daemon holds `Inhibit("idle", "axiom", "Caffeine", "block")` (what `systemd-inhibit --what=idle` takes), so a user's own idle daemon that honours logind's idle inhibitors (hypridle does by default) holds off too. It's taken on a system bus connection of its own, closed once the descriptor is in hand (logind holds idle off while it's open), tried again every 30 s when it can't be, and closed the moment caffeine goes off or the daemon stops. The last shell's connection closing turns caffeine off too (`Daemon.lastShellGone`), so a shell that quit leaves no inhibitor behind; one that comes back sends its caffeine after its hello. A re-exec closes it (close-on-exec): the next image takes its own when the shell, greeting it, sends caffeine again. Idle daemons that don't read logind's idle inhibitors (swayidle, …) don't see caffeine at all.
- With `respectInhibitors` on, also:
  - The compositor holds the notifications off for Wayland inhibitors (a video player's).
  - The daemon holds them off itself for apps calling `org.freedesktop.ScreenSaver.Inhibit` (`internal/screensaver`). The daemon takes the name while idle is on, and drops an app's inhibitors when it leaves the bus.
  - And for logind's idle inhibitors (`systemd-inhibit --what=idle`), listed by `ListInhibitors` when `BlockInhibited` names idle. Caffeine's own (who `axiom`, the daemon's pid) is left out: it isn't an app, and idle is blocked only while another one is listed. As `BlockInhibited` doesn't change while another inhibitor joins or leaves beside caffeine's, they're listed again once caffeine's is let go.
- When another program holds `org.freedesktop.ScreenSaver`, axiom reports who (`idle.state`'s `screensaver.owner`). niri answers it itself and applies it to its own notifications: that one isn't a problem (`compositor`), anything else is warned about on the card.
- With it off, the notifications are input-only, which ignore the compositor's inhibitors: only caffeine counts.
- When something starts holding idle off, every listener is disarmed and the steps that fired run their return (the screens come back when a video starts). They arm again when it lets go; `SimulateUserActivity` restarts them too.

### logind (`internal/logind`)
- The session: `$XDG_SESSION_ID`, else the daemon's own, else the user's display session (a daemon outside the session's scope has none of its own).
- `Session.Lock` (`loginctl lock-session`) locks, while `Idle.enabled` only (and not `NoLocker`): a user's own hypridle would also answer it.
- Before sleep (`PrepareForSleep(true)`), with `lockBeforeSleep`: a delay inhibitor held all along keeps sleep waiting while the screen locks, up to logind's `InhibitDelayMaxUSec` less half a second; then it's let go. On waking it's taken again, and with `screenOnAfterSleep` the screens are turned on.
- A lost bus is dialled again every 30 s.

### The shell
- `IdleManager` (`qml/services/session/`, from `qml/shell.qml`'s `_services`):
  - `status`: `off`, `running`, `inhibited`, `noLock` (nothing locks: `noLocker`), `unsupported` (no `ext_idle_notifier_v1`) or `unavailable` (no daemon), from `idle.state` (a push on the `idle` topic; `idle.get` after each hello).
  - `inhibitors`, `screensaverHolder`.
  - Caffeine: `caffeine`, `setCaffeine(on)`, `toggle()` and the `idleInhibit` IPC target (`timer <text>` too). It is sent to the daemon (`idle.caffeine`, shell only, whether Idle is on or not), which applies it, on change and after each hello, but only once the ticker is `ready`: on a reload caffeine reads off until its kept state is copied in, and the daemon must not see it go off and on.
  - Caffeine on a timer: `startCaffeineText("30m")` (or `startCaffeine(ms, once)`, from the popout's parsed field and chips) turns it on with a `caffeineTimer` (`StopwatchClock`'s timer state; `caffeineTimed`, `caffeineRemaining`, `caffeineText`, `caffeineProgress`, the last 3 durations in `caffeineRecent`), which turns it off at its end; paused, it stays on. With `Idle.caffeineWarning` (default on) the ticker's `warnBefore` fires 5 minutes before the end (only when crossed while running, once per end) and a notification offers 30 more minutes. `setCaffeine`/`toggle` drop the timer (on means until turned off). Both live in a `DeadlineTicker` (`keeps: false`: a `PersistentProperties` only, so they survive QML reloads but not restarts, and the end fires with nothing showing it); displays `acquire(owner, interval)` its ticking `now`.
- The `IdleInhibitor` widget toggles caffeine and shows the time left while timed (faded while paused); its popout (`content/Caffeine/Caffeine.qml`, `popout.enabled`) has an on/off switch and the shared `CountdownTimer` (`content/parts/`, the one-off timer's too) over the widget's `presets` (default 30m, 1h, 4h); it takes `until 17:00` too, and while running shows "Until 17:30", steps by 5 minutes on the wheel and offers +30m / +1h / +2h on a right click of +15 min. The same file is the Caffeine overlay module (its own `presets` setting, default 4×5; compact, the time left or On/Off). On with no timer, both show "Awake until turned off" with Turn off and Set a timer (which brings back the presets, with a way back to no timer) instead of the presets. The quick action shows the time left too, and the launcher's `/caffeine 30m` starts one.
- Settings → Idle starts with `IdleStatusCard`: the status, what holds idle off, and the ScreenSaver warning. `noLock` says to set the Lock command. `off` says caffeine reaches a user's own daemon only through logind (hypridle yes, swayidle no); the onboarder's System page says the same with Idle off, naming no daemon.

### Testing
- Go: `internal/idle` (the plan, and the service against a fake notifier, a fake bus and `logind/logindtest`, whose idle inhibitors taken with `Inhibit` are listed and block idle until closed), `wayland/idlenotify` (`wiretest`), `logind`, `screensaver`.
- Live: only in a nested compositor (`scripts/dev/nested.sh`) under `dbus-run-session`, on a scratch config with short timeouts, and **`Idle.suspend.timeout` 0**: logind is the real system bus. Check with `systemd-inhibit --what=idle sleep 30`, and `gdbus call --session -d org.freedesktop.ScreenSaver -o /org/freedesktop/ScreenSaver -m org.freedesktop.ScreenSaver.Inhibit app why`.

### A user's own hypridle
With Idle off, for the lock screen's `quickshell` mode, a user's own hypridle should use:
- `lock_cmd = axiom lock`
- `before_sleep_cmd = loginctl lock-session`

Any other idle daemon (swayidle, …) locks with `axiom lock`, before sleep too; the onboarder says only that, naming no daemon. For `none` mode it should have no axiom references. See [Lockscreen](lockscreen.md).

Caffeine reaches a user's own idle daemon only through logind's idle inhibitor: hypridle honours it (unless its `ignore_systemd_inhibit` is set); swayidle and other daemons that don't read logind's idle inhibitors don't, so caffeine doesn't keep them off.
