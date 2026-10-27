# Greeter: runtime (bundle, session, greeter mode, login)

> **Files:** `greeter.qml`, `shell/Greeter.qml`, `shell/GreeterPreview.qml`, `components/surfaces/greeter/GreeterSurface.qml`, `components/surfaces/greeter/GreeterWindow.qml`, `components/surfaces/greeter/GreeterPreviewWindow.qml`, `services/session/GreetdManager.qml`, `services/session/GreeterManager.qml`, `components/methods/GreeterBundle.qml`, `components/methods/GreeterUsers.qml`, `components/methods/GreeterSessions.qml`, `components/content/Login/Login.qml`, `components/content/Session/Session.qml`, `components/content/KeyboardLayout/KeyboardLayout.qml`, `components/content/Power/Power.qml`, `components/content/parts/LoginField.qml`, `scripts/greeter/greeter-session.sh`, `scripts/greeter/sway.conf`, `scripts/greeter/hyprland.lua`, `backend/internal/greeter/greeter.go`, `backend/internal/cli/greeter.go`, `backend/internal/daemon/greeter.go`
> **Config:** `Greeter.*` (reader `GreeterConfig`), plus the sections exported in the bundle
> **Related:** [Greeter install](greeter-install.md), [Lockscreen](lockscreen.md), [Themes](../theming/themes.md), [Config manager](../core/config-manager.md), [Monitors](../hyprland/monitors.md), [Schema annotations](../core/schema-annotations.md)

This doc covers what runs at the login screen and the data it reads: the bundle the user's axiom exports, the greetd session script, greeter mode (`Paths.greeter`), `GreetdManager`'s login API, and the greeter's surfaces and modules. Installing the root-owned copy is in [greeter-install.md](greeter-install.md).

### Who owns what
- **`GreeterManager`:** axiom as greetd's login screen, seen from the user's side (install, bundle, status). It is created from `shell.qml`'s `_services`.
- **`GreetdManager`:** the login in the greeter itself. Only greeter-side code references it.

### The bundle
- `GreeterBundle.exportConfig` (pure) builds the bundle from:
  - the `Greeter`, `Appearance`, `Interface` (so its controls are sized and rounded as on the desktop), `General` and `Weather` sections (its wallpaper blur is `Greeter.layout.backdrop.blur`, its own since config v67);
  - `Compositor.mode` and `Monitors.items`;
  - the `Input` options marked `x-greeter` (the part switches, keyboard, mouse, touchpad, cursor);
  - `theme.json` (`ThemeManager.currentTheme`);
  - each wallpaper showing (`ThemeManager.shownWallpapers`, exported as fixed ones in `fixed` mode, so the greeter shows what the desktop does), copied to `wallpapers/<md5 of its url>.<ext>` (cp + mv, stale ones removed). The bundle's `Appearance` names these copies.
- **How it's written:** one `sh` (`GreeterManager._writeBundle`).
  - Each JSON goes through a temp file and a rename.
  - Then `chmod -R go+rX`, so greetd's user can read it whatever the umask.
- **When it's written:**
  - while the greeter is installed and the bundle writable, a second after any of it changes; a failed write is retried on the next change;
  - right after an install or update succeeds, so the greeter never starts before its bundle exists;
  - JSON only, to the staging folder before an install or update.
- Changing the login screen therefore needs no root. Only code changes need Update.

### Running it (session script)
- `greeter-session.sh`, greetd's command, starts the greeter's own compositor, whichever one the user logs in to:
  - **sway** when installed, on `scripts/greeter/sway.conf` (no binds, no bar, no XWayland, numlock on; `--unsupported-gpu` when `/sys/module/nvidia` exists). Plain sway is enough: the greeter blurs nothing ([Surfaces](#surfaces-and-modules)).
  - **Hyprland** (`start-hyprland` on `scripts/greeter/hyprland.lua`: logo off, numlock on, no animations) when sway isn't installed, or exited non-zero without the failure marker (it couldn't start).
  - sway's own stderr goes to the greeter's `state/compositor.log`.
- Each one's start (sway's `exec`, the Lua's start hook) runs `greeter-session.sh shell`, which runs `axiom greeter --tree <copy>` (below), its stderr in the greeter's `state/greeter.log` (emptied at each start; greetd's user's runtime dir, where qs keeps its own logs, goes with the greeter's session). Both are greetd's user's: `sudo` to read them.
  - `<copy>` is the install folder, or for a packaged axiom the folder its `.greeter-source` names (`package /usr/share/axiom`).
  - The binary is the install folder's `bin/axiom` (root's), else a packaged one on `PATH`.
  - It exports `AXIOM_GREETER_FALLBACK`, the install folder's `fallback/`, which `axiom greeter` and `Paths.greeterFallbackUrl` read (without it, `fallback/` beside the code).
  - If that fails, it runs once more with `--safe` (the snapshot, never the bundle); qs exits non-zero on a broken load.
  - Then it ends the compositor: `swaymsg exit` under sway (`$SWAYSOCK`), else `hyprctl dispatch 'hl.dsp.exit()'`.
- **Fallback:** if qs failed twice, or neither compositor starts, the session runs `agreety --cmd '${SHELL:-/bin/sh}'`, so a login is always possible.
  - The failure marker lives in `$XDG_RUNTIME_DIR`, else the greeter's `state/`, never in `/tmp`.
  - The command is quoted so the session's own `sh` expands it to the login shell of whoever logs in.

### Greeter mode
- **How it's detected:** `AXIOM_GREETER=1` sets `Paths.greeter`. `ConfigManager.greeter` reads the environment again itself, since `ConfigManager` reads no reader.
- **What it builds:** `greeter.qml` builds only `shell/Greeter`, a `GreeterWindow` per screen.
  - `AXIOM_GREETER_WINDOWED=1` builds one `FloatingWindow` instead, for looking at it from a session.
  - `AXIOM_GREETER_DIR` points it at a scratch folder.
- **Config:** `axiom greeter` (the greeter's parent, as `axiom run` is the shell's) loads it with the same pipeline as config.json (`greeter.Load`): the bundle's `greeter.json`, else `fallback/`'s, else the schema defaults, logging why each was skipped. The schema is built from the copy's own YAML (the binary's, if that fails).
  - A format-1 file is converted; a format-2 bundle from a newer axiom is still tried as the current version, with its unknown keys pruned.
  - It writes the result to a private runtime folder (`$XDG_RUNTIME_DIR/axiom/greeter-<display>/`, else the greeter's `state/run/`), never the session's own, then runs `qs -p <copy>/greeter.qml` as its child with `AXIOM_GREETER=1`, `AXIOM_CONFIG`, `AXIOM_SCHEMA`, `AXIOM_GREETER_SOURCE` (`bundle` | `fallback` | `defaults`) and `AXIOM_BIN` (itself: sway's and niri's backends read the compositor's config through `axiom compositor …`). Every other inherited `AXIOM_*` is dropped, as the daemon does for the shell, but `AXIOM_GREETER_WINDOWED`, `AXIOM_COMPOSITOR` and `AXIOM_COMPOSITOR_OFF` (for looking at it from a session; `greeterKept`).
  - `ConfigManager` reads that snapshot as it reads the shell's, and never writes, watches or polls.
  - **The greeter's axiom:** `axiom greeter` stays qs's parent until qs exits, and exits non-zero when qs did (so the session script tries `--safe`); SIGTERM stops qs first. It serves a socket in that runtime folder (`AXIOM_SOCKET`, `daemon.RunGreeter`). It answers only that qs's hello, then `exec.run` / `exec.spawn` (`CommandManager.run` / `runDetached`: `GreetdManager`'s sessions, avatars and power actions, `SwayIpcManager`, `NiriManager`), `exec.watch` / `exec.unwatch` / `exec.refresh` (`CommandManager.acquire`: a Button's label, a CommandOutput module), `file.write` / `file.watch` (`FileManager`: its state, `StateManager`), `tz.*`, `net.addresses`, `hypr.request` (`HyprlandManager` under the greeter's Hyprland: its monitors, layouts and cursor) and the `weather` topic (`WeatherManager`, for its Weather module). It owns no config, lock, idle, compositor layer or Wayland connection, and pushes nothing but `exec.outputs`, `file.changed` and `weather.state`: any other call is `unavailable`, as with no axiom at all (so the callers and subscriptions a greeter module reaches, such as the `tailscale` and `system` topics and `deps.check`, stay quiet), and nothing of the session's daemon is reachable from the login screen ([protocol](../backend/protocol.md)).
- **Theme:** `ThemeManager` reads the `theme.json` beside the config named by `ConfigManager.greeterSource` (the bundle's, else `fallback/`'s), so safe mode never loads a bundle theme.
  - It generates, links and runs nothing.
- **State:** `Paths.statePath` / `userStatePath` point at the greeter's `state/`.
- **Startup:** singletons are lazy, so nothing else from the session starts.
- **No config layer:** the daemon does axiom's compositor layer, and the greeter has none; `CompositorConfigManager.enabled` is false in greeter mode too, so nothing writes or sends axiom's layer (binds, look, rules) to the greeter's compositor, or, from a greeter run in a session, to the session's.
- (Rule: in greeter mode nothing writes config, generates or runs integrations; AGENTS.md › Greeter.)

### GreetdManager
Built on `Quickshell.Services.Greetd`.
- **Users:** `users` comes from `methods/GreeterUsers`: `/etc/passwd` within `/etc/login.defs`' UID range, login shells only.
- **Sessions:** `sessions` comes from `methods/GreeterSessions`: `wayland-sessions/*.desktop` in each data dir (`Paths.dataSearchDirs`: `$XDG_DATA_HOME`, then `$XDG_DATA_DIRS`; the first file of a name wins, as `GreeterSessions.files` picks), with Exec split per the desktop entry spec and field codes dropped.
- **Selecting a user:** `selectUser(name)`. A typed name not in the list is still tried. Selecting loads the user's last session, even before the sessions are listed (the remembered user is selected at start, while `find` still runs): `selectedSession` falls back to the first while that id isn't among them.
- **Logging in:**
  - `submit(response)` creates the session, with the password pending for greetd's first question.
  - Later questions (an OTP) become `prompt` / `promptEcho`.
  - `cancel()` and `failed` are also exposed.
  - The session launches with `XDG_SESSION_TYPE` / `XDG_CURRENT_DESKTOP` / `XDG_SESSION_DESKTOP`.
  - It remembers the user (with `rememberUser`) and their session.
- **Other:**
  - `power(action)` through `systemctl`.
  - Keyboard layouts through `CompositorManager.withKeyboard` and `cycleKeyboardLayout`.
  - `avatarOf(name)` from AccountsService's icons.
- **At start** (but not when windowed), `_applyCompositor`:
  - on Hyprland it evals `HyprLua.greeterLua`: the profiles' `monitorsLua` (which picks the profile again on each hotplug), plus one `hl.config` of the `x-greeter` input options whose parts are on; and it sets the cursor while the cursor part is on with a theme (`HyprlandManager.setCursor`);
  - elsewhere (sway) it applies the saved profile for the outputs connected at start (`MonitorLayout.savedRules` → `CompositorManager.applyOutputs`), and the input options and cursor through `CompositorManager.applyInput` (sway's live `input` / `seat` commands, `SwayConf.inputLines`).

### Surfaces and modules
- **`surfaces/greeter/GreeterSurface`** is a `ScreenLayoutView`, the same view the lock screen uses ([lockscreen.md](lockscreen.md#layout)).
  - Its cards are sized like the lock screen's (`OverlayConfig.cardUnitOn`, from the bundle's `Widget.cardSize`), so both look the same on a monitor.
  - Its host is `{ kind: "greeter", target, preview, key, bare, passwordBorder, greetingBorder }`.
  - The target is `Greeter.monitor`'s screen. Other screens follow `otherScreens`.
  - With no Login module reported (`SurfaceManager.requiredFields`), it draws a `content/parts/LoginField` of its own.
- **Greeter-only modules:**
  - `Login` (`x-required`): a `LoginField` holding a `StyledComboEntry` of users (can be typed over), a `PasswordEntry`, and the user's picture.
    - In a slot too short to stack them, the two fields go side by side.
    - In a slot shorter than one field, they shrink to fit.
  - `Session`: in a slot shorter than its card, just the field, with no card.
  - `Power`: restart and shut down ask twice. It is also on the lock screen.
  - `KeyboardLayout`.
- **Solid:** in greeter mode `Appearance.compositorBlurs` is false (`CompositorManager`), so every surface is opaque and nothing frosts; `GreeterSurface` also sets `frost: false`, so the layouts editor's preview isn't frosted either, though its cards keep the session's translucency (`Appearance.fill` is global). The wallpaper still follows `Greeter.layout.backdrop.blur` (Qt's own blur, needing nothing of the compositor).
- **Display modules** that list `greeter` in `x-hosts`: ClockCalendar, Greeting, Weather, Battery, Network, Palette, ColorSwatch.
- **Inert outside the greeter:** every greeter module is inert unless `host.kind === "greeter" && !host.preview && Paths.greeter`, so the user's session never talks to greetd.
- **Host filtering:** `ScreenLayoutView` draws only modules whose `x-hosts` list the host's `kind`.
  - Validation accepts any module in a `ScreenLayout`.
  - The bundle's folder is writable by any of the user's programs.
  - So the filter is what stops a hand-made bundle from putting a launcher on the login screen.
- **Preview:** "Show on screen" (`GreeterManager.editor`, a `ScreenLayoutEditor`) shows `GreeterPreviewWindow`, built by `shell/GreeterPreview`.

### Testing
- Look at the greeter in a window: `AXIOM_GREETER_WINDOWED=1 AXIOM_COMPOSITOR=none axiom greeter --tree "$PWD" --dir <scratch>`, with a scratch `XDG_RUNTIME_DIR` (short: the socket's path must fit 108 bytes) and `WAYLAND_DISPLAY` as an absolute path. qs started without it has no axiom and runs no command.
- Stop only that instance: SIGTERM to its `axiom greeter`, which stops its qs. Never restart greetd: it ends the session.
