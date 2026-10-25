# Idle (hypridle) and idle inhibit

> **Files:** `services/session/HypridleManager.qml`, `components/methods/HypridleConf.qml`, `config/Idle.qml`, `components/views/Settings/IdleStatusCard.qml`, `services/session/IdleInhibitManager.qml`, `shell/IdleInhibit.qml`, `components/bar/widgets/IdleInhibitor/IdleInhibitor.qml`
> **Config:** `Idle.*` (reader `Idle`)
> **Related:** [Lockscreen](lockscreen.md), [Brightness](brightness.md), [Hyprland config modes](../hyprland/config-modes.md)

Axiom can run hypridle with its own generated config, and it keeps a caffeine (idle inhibit) switch.

### HypridleManager
- Off by default; the onboarder's Integrations page recommends it.
- `Idle.enabled` takes over the user's hypridle (an `x-takeover` setting). Ask before enabling it on the live config: it replaces the user's running hypridle. (Rule: AGENTS.md › Never, while testing.)
- **While `Idle.enabled`:**
  - It renders `components/methods/HypridleConf` to `$XDG_STATE_HOME/axiom/hypridle.conf`, writing only on change.
  - `HypridleConf` is pure. It writes a general block, then the dim / lock / screen-off / suspend listeners in timeout order (a timeout of 0 means off), then the user's `listeners`.
  - It runs `hypridle -c` on that file and stops any other hypridle.
  - hypridle doesn't watch its config, so a change restarts it.
- **Turned off:**
  - It stops its own hypridle.
  - If `~/.config/hypr/hypridle.conf` exists, it starts a plain `hypridle` again.
  - The user's file is never touched.
- **Nothing is polled:**
  - `pgrep` runs on each apply, and once 15 s after startup.
  - `replacedOther` is set when a second hypridle turns up beside axiom's.
- **What the listeners do:**
  - **Lock:** `lockscreen lock`. In `none` mode it uses `Lockscreen.lockCommand` instead, unless that's `loginctl lock-session`.
  - **Dim:** `brightness dim <percent>` / `undim`. These act on every monitor and are silent, so no OSD.
  - **DPMS:** `hl.dsp.dpms({ action = … })`.
- The managed mode's autostart (`Session.autostart`) skips a plain `hypridle` entry while this is on.
- Settings → Idle starts with `IdleStatusCard`.
- Created from `shell.qml`'s `_services`.

### A user's own hypridle
For the lock screen's `quickshell` mode, a user's own hypridle should use:
- `lock_cmd = axiom lock`
- `before_sleep_cmd = loginctl lock-session`

For `none` mode it should have no axiom references. See [Lockscreen](lockscreen.md).

### Idle inhibit (caffeine)
- **`IdleInhibitManager`:**
  - Holds the shared caffeine state in a `PersistentProperties`, so it survives QML reloads but not restarts.
  - Has the `idleInhibit` IPC target.
- **`shell/IdleInhibit.qml`:**
  - Holds the Wayland inhibitor itself.
  - While caffeine is on, it maps a 1 px click-through Background-layer window on the primary monitor, because an inhibitor needs a surface.
- It therefore works without the bar widget (`bar/widgets/IdleInhibitor`).
