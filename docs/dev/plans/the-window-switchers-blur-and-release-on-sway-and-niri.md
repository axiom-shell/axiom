# The window switcher's blur and release on sway and niri

> **Issue:** [The window switcher's blur and release on sway and niri](../issues.md#the-window-switchers-blur-and-release-on-sway-and-niri)
> **Status:** proposed

### Problem
**Release.** Hyprland holds every switcher key itself: the bind enters a submap and a Lua key listener picks once the held modifiers are up (`supports.switcherRelease`, [Hyprland's switcher](../hyprland/window-switcher.md)). sway and niri can't report the release:
- sway fires a `--release` bind only when no other key came between, and Tab always does ([sway backend](../compositor/sway-backend.md) › The switcher). Its binds send `nop axiom switcher step ±1`, read from the IPC `binding` event (no process).
- niri has no release binds or key listener. In detached mode, or with `WindowSwitcher.compositorSwitcher` off, its binds `spawn` `axiom ipc windowSwitcher next|previous` (a process per key).
- On both, `SwitcherKeys` (`shell/WindowSwitcher.qml`) maps a 1 px Overlay window with exclusive keyboard focus once `WindowSwitcherManager.active`, and commits on a held modifier's `Keys.onReleased`.

The gap: **a modifier let go before that window has the keyboard is never seen.** The switcher then stays open (and draws after `showDelay`) with no window focused until the next key press. `SwitcherKeys`' fallback commits on that press, which it also eats. Checked in nested niri (detached, this branch):
- `axiom ipc windowSwitcher next` with no modifier held: `axiom-switcher` and `axiom-switcher-keys` (`Keyboard interactivity: exclusive`) stay mapped and `niri msg focused-window` says `No window is focused`, the strip drawn. A `wtype x` then commits (focus moves on), and the `x` never reaches the window.
- The IPC round trip is 4–5 ms. The rest of the window is niri's spawn, the shell mapping the window and the compositor focusing it. A quick tap releases inside that window more often on niri (a process per key) than on sway, where the sway doc notes taps are fine at 20 ms.
- Not reproduced with real keys: niri doesn't run binds for `wtype`'s virtual keyboard (the keys reach the focused client instead), so the bind path itself needs the maintainer's hands.

Who: sway users always, niri users in detached mode or with `compositorSwitcher` off. Included and managed niri default to niri's own switcher (row 16), which is untouched.

**Blur.** "The switcher's blur background is broken" wasn't reproduced. The switcher is a `FloatingPopout` (`axiom-switcher`, in `LayerStack.blurSurfaces`), the launcher's host: Hyprland's `axiom-blur` layer rule, SwayFX's `layer_effects`, niri's `BoxBlurRegion` of the box ([translucency and blur](../theming/translucency-blur.md)). In nested niri at 75% opacity the box is translucent over the windows (pixels differ over the gap and over a window), but nested niri had no `blur {}`, so no blur showed to judge. Plain sway has no blur by design (surfaces solid). Candidates, none confirmed:
- niri marks non-xray blur experimental: it can vanish during open and close animations, and the switcher scales and fades in every time it shows.
- The box's region (or the rule's `ignore_alpha`) versus the tiles drawn on it: the selected tile's fill is 14% accent.
- Something only Hyprland shows, since the note came before sway and niri had a switcher.

### Options
#### A. Harden SwitcherKeys in the shell
Keep the window mapped for the session with keyboard focus `None`, switching to `Exclusive` on open, so opening costs a focus change rather than a map. A missed release still falls back to the next key.
- Cost: a few lines in `SwitcherKeys`.
- Risk: none new.
- Leaves out: the gap only narrows. Qt reads the keys held at `wl_keyboard.enter` but QML can't ask for them, so the shell can never tell "released before I had focus" from "still held".

#### B. The daemon holds the release
On the first step the shell asks the daemon to hold the switcher's keys, and the daemon maps its own 1 px layer surface with exclusive keyboard focus.
- `wl_keyboard.enter` carries the keys already down. If none of the held modifiers is among them, the daemon commits at once. Otherwise it commits on their release, cancels on Escape and commits on Return, pushing `switcher commit|cancel` to the shell's `switcherKey` as Hyprland's events do.
- The held modifiers are evdev keycodes (Alt, Super, Ctrl, left and right), so no keymap is needed.
- sway and niri share one path and get `supports.switcherRelease`. `SwitcherKeys` goes, and a stray key is never eaten.
- Cost: the daemon's Wayland client (`backend/internal/wayland/`) has a seat and a virtual keyboard but no surfaces. This adds `wl_compositor`, a `wl_shm` buffer, `zwlr_layer_shell_v1` and `wl_keyboard`: a new package, a method and a push. It moves a side effect out of the shell, as the backend roadmap wants.
- Risk: the compositor must still run the Tab binds while another client holds exclusive focus, as it does today for `SwitcherKeys` (sway does; niri should, which needs checking live).

#### C. Only the compositor's switcher where there is one
On niri, steer users to `compositorSwitcher`, the default in included and managed. Do A for sway and detached niri.
- Cost: A's, plus a hint on the switcher card in detached mode.
- Leaves out: sway keeps the gap, and detached niri users with axiom's switcher keep it too.

### Recommendation
B. It is the only option that closes the race rather than narrowing it: the enter event says exactly which keys are down when the switcher takes the keyboard. It gives sway and niri the same guarantee Hyprland's listener gives, in code that's tested in Go and survives a QML reload. A could ship first as a stopgap if B waits behind other backend work, but it isn't needed once B lands.

The blur gets no option until the maintainer says what's broken (questions below). Its item is a placeholder.

### Items
1. **The daemon's key hold** (Go): a `wayland/keyhold` package (a 1 px layer surface, exclusive keyboard, enter keys and releases by evdev code), a `switcher.hold` method taking the held modifiers and a `switcher.release` to drop it, and a `switcherKey` push. Tests on the wire fakes.
2. **The shell on the hold**: `SwayManager` and `NiriManager` call `switcher.hold` on the first step (from `BindActions.switcherHeld`), `release` on commit, cancel and `leaveSwitcher`, and report `switcherRelease`. `SwitcherKeys` and its `LazyLoader` go. Update `hyprland/window-switcher.md` (or move it to a compositor-neutral doc) and the sway and niri backend docs.
3. **The switcher's blur**: once reproduced from the maintainer's answers, the smallest fix in `shell/WindowSwitcher.qml` or `FloatingPopout`, else closed as not reproduced.

### Open questions
- Which compositor shows the broken blur, and what does it look like: no blur at all, blur on a bigger rectangle than the box, blur that flickers or drops while the box opens, or something under the tiles? A screenshot, and whether the floating launcher blurs correctly on the same setup.
- On live niri with `compositorSwitcher` off (or detached), does a quick Alt+Tab tap leave the switcher open until the next key? And does a slow hold-and-release always pick (if not, the release itself is lost, not just early)?
- On live niri, do the Tab binds still step while `axiom-switcher-keys` holds exclusive focus?
- Is a Go Wayland surface in the daemon (option B) acceptable, or should the release stay in the shell?
