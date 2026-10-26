# Wayland protocols per compositor

> **Files:** `backend/internal/wayland/wire/`, `backend/internal/wayland/client/`, `backend/internal/wayland/vkbd/`, `backend/internal/wayland/ctm/`, `backend/internal/wayland/gamma/`, `backend/internal/wayland/datacontrol/`, `services/core/WaylandManager.qml`, `backend/internal/wayland/outputs/`, `backend/internal/wayland/seat/`, `backend/internal/wayland/idlenotify/`, `backend/internal/daemon/daemon.go`, `backend/internal/daemon/wayland.go`, `tests/fixtures/wayland/`
> **Related:** [The axiom binary](README.md), [Compositor contract](../compositor/contract.md)

The daemon's own Wayland connection, and what each compositor offers for what it does over it next (roadmap stage 2: idle, gamma, clipboard, typing).

### The connection
- `wire.Conn` (pure Go, no libwayland): object ids from 2 up, reused after the compositor's `delete_id`; each object's events go to its handler on the goroutine running `Run`; `Registry`, `Bind`, `Sync`. A `wl_display.error` ends it with the compositor's message.
- **Arguments**: `Uint`, `Int`, `Fixed` (24.8), `String`, `Array`, `NewID` (an interface named by the request, as `wl_registry.bind`'s) and `Fd`, read back by `Args` in order.
  - File descriptors ride beside the message on `internal/unixmsg` ([dbus.md](dbus.md) › Descriptors): `Fd(f)` sends a duplicate (`f` stays the caller's).
  - `Args.Fd()` takes the event's next one from the connection's queue. A handler must take every fd its event carries, in order, or later events get the wrong ones.
  - `SealedFile(name, data)` is a sealed memfd for what the compositor maps (a keymap, gamma ramps).
- `wire.Conn.PeerPID` is the compositor's pid, from the socket's credentials (the idle service tells the compositor holding `org.freedesktop.ScreenSaver` from another program with it).
- **The clients share it** (`wayland/client`): the daemon dials once (`Daemon.followCompositor`), `client.Run` asks for the registry once and hands each `client.Client` the globals of the interfaces it names (`Global` / `Removed`), after `Start` (a new connection) and before `Ready` (two roundtrips: the first globals bound and described). Its handlers run on the connection's goroutine and never block: slow work (a pipe to read, an action to run, a D-Bus call) goes to a goroutine of its own owner's.
  - The clients now: the connection itself (`daemon/wayland.go`), `wayland/outputs`, `wayland/seat` (the first `wl_seat`, which idle notifications, data control and the virtual keyboard are made on) `wayland/idlenotify` (`ext_idle_notifier_v1`: one notification per idle step, armed again when the notifier or seat comes back; [idle](../features/idle.md)) `wayland/vkbd` (`zwp_virtual_keyboard_v1`: `input.type`, shell only, at most 4096 characters, one text at a time), `wayland/ctm` / `wayland/gamma` (the night light, per bound output: `outputs.Tracker.Bound` and `OnChange`), and `wayland/datacontrol` (the clipboard: offers the compositor makes are adopted under its ids, `wire.Conn.Adopt`, and read through pipes off the connection's goroutine).
- **What it can do** reaches the shell as `wayland.state` (the `wayland` hello topic; `wayland.get` after each hello; `WaylandManager` in QML), one flag per feature from the globals actually bound: services gate on it, never on a compositor. Its `ready` turns true once the connection's first globals are bound (the session client's `Ready`, after the others'); until then every flag reads off, so `WaylandManager.known` waits for it and nothing takes "off" for "not offered" (the night light would start wlsunset beside the daemon).
- `wayland/outputs` runs on it for the daemon's whole life: it binds every `wl_output` (v4: its connector name and description) and `zxdg_output_manager_v1` (v3: each output's place and size in the layout, committed by `wl_output.done`; without it, `wl_output`'s geometry and current mode), and follows hotplug (`global` / `global_remove`, then `release`). `Names()` is the outputs by place (left to right, then top to bottom), nil until two roundtrips have described them, and while an output has no name (wl_output below v4): `share.*` names monitors by place with it.
- The connection ending is the compositor gone: the daemon stops. A protocol error falls back to `wire.Watch`.
- `axiom debug wayland-outputs [--json]` lists the outputs as the daemon sees them.
- Tests script a fake compositor: `wire/wiretest`.

### Globals
`axiom debug wayland-globals [--json]` lists a running compositor's globals; all three offer `wl_output` v4 and `zxdg_output_manager_v1` v3, which the outputs use. The captures are in `tests/fixtures/wayland/globals-<compositor>.json`:
- Hyprland 0.55: the live session.
- sway 1.12 (SwayFX 0.6): headless (`WLR_BACKENDS=headless`).
- niri 26.04: nested in a window (its winit backend).

A nested or headless compositor has no real outputs, so protocols tied to outputs can be missing there that a session on a TTY offers. Check niri's gamma and output power on a real niri session before relying on them being absent.

| Protocol | For | Hyprland | sway | niri |
|---|---|---|---|---|
| `ext_idle_notifier_v1` | idle (replace hypridle) | v2 | v2 | v2 |
| `zwp_idle_inhibit_manager_v1` | idle inhibit | v1 | v1 | v1 |
| `ext_session_lock_manager_v1` | lock screen | v1 | v1 | v1 |
| `zwlr_gamma_control_manager_v1` | night light (gamma) | v1 | v1 | — |
| `hyprland_ctm_control_manager_v1` | night light (CTM) | v2 | — | — |
| `ext_data_control_manager_v1` | clipboard (ext) | v1 | v1 | v1 |
| `zwlr_data_control_manager_v1` | clipboard (wlr) | v2 | v2 | v2 |
| `zwp_virtual_keyboard_manager_v1` | typing (replaced wtype) | v1 | v1 | v1 |
| `ext_image_copy_capture_manager_v1` | screen capture (ext) | v1 | v1 | — |
| `zwlr_screencopy_manager_v1` | screen capture (wlr) | v3 | v3 | v3 |
| `zwlr_output_power_manager_v1` | DPMS | v1 | v1 | — |
| `zwlr_foreign_toplevel_manager_v1` | window list (wlr) | v3 | v3 | v3 |
| `ext_foreign_toplevel_list_v1` | window list (ext) | v1 | v1 | v1 |
| `ext_workspace_manager_v1` | workspaces (ext) | v1 | v1 | v1 |
| `zwlr_output_manager_v1` | output config | v4 | v4 | v4 |
| `wp_security_context_manager_v1` | security context | v1 | v1 | v1 |

### What it means for branch 2
- **Idle** (done): `ext_idle_notifier_v1` everywhere, so the daemon replaced hypridle on all three, with inhibitors (`zwp_idle_inhibit_manager_v1`) respected by the compositor.
- **Clipboard** (done): `ext_data_control_manager_v1` everywhere, with `zwlr_data_control` as the fallback (`wayland/datacontrol`): the daemon's in-memory history replaced `wl-paste --watch` and cliphist, and its own selections replaced wl-copy ([launcher providers](../features/launcher-providers.md)).
- **Typing** (done): `zwp_virtual_keyboard_manager_v1` everywhere, so `wtype` went (`wayland/vkbd`).
- **Night light** (done): Hyprland's CTM (`wayland/ctm`), else `zwlr_gamma_control` (`wayland/gamma`, sway), picked by the globals bound ([night light](../theming/night-light.md)).
  - niri (nested) shows neither, so niri keeps wlsunset. The choice follows the globals, not the compositor: a TTY niri session offering gamma control gets it with no change.
