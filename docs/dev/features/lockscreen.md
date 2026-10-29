# Lockscreen

> **Files:** `services/session/LockManager.qml`, `services/session/AuthManager.qml`, `shell/Lockscreen.qml`, `components/surfaces/lockscreen/LockSurface.qml`, `components/surfaces/lockscreen/LockPreviewWindow.qml`, `components/surfaces/screenlayout/ScreenLayoutView.qml`, `components/content/Password/Password.qml`, `components/content/parts/PasswordField.qml`, `components/content/parts/FocusKeeper.qml`, `components/reusable/PasswordEntry.qml`, `components/content/Greeting/Greeting.qml`, `services/ui/ScreenLayoutEditor.qml`, `components/views/Layouts/LockscreenTarget.qml`, `config/LockscreenConfig.qml`
> **Config:** `Lockscreen.mode`, `Lockscreen.lockCommand`, `Lockscreen.layout` (reader `LockscreenConfig`)
> **Related:** [Idle](idle.md), [Greeter runtime](greeter-runtime.md), [Desktop](desktop.md), [Layouts editor](../overlay/layouts-editor.md), [Grid canvas](../overlay/grid-canvas.md), [Themes](../theming/themes.md), [Shell targeting](../core/shell-manager-targeting.md)

This doc covers the three lock modes, how the built-in lock screen's layout of modules works (grid, hosts, password, background), and how it is edited and previewed. (Rule: AGENTS.md › UI conventions › Lockscreen; never lock the session while testing.)

### Locking
- `LockManager.lock()` is the one way to lock.
  - Lock buttons call it through `SessionManager.sessionAction("lock")`.
  - Idle locks come from the daemon (`axiom lock`'s path: [idle.md](idle.md)); a user's own idle daemon calls `axiom lock` or the `lockscreen` IPC target.
- `lock()` ends a running preview first.

### Under axiom (`axiom lock`)
Run by `axiom run`, the binary makes locking dependable (`backend/internal/lockscreen`):
- `axiom lock` (and `axiom ipc lockscreen lock`) asks the shell. It exits 0 only once `shell/Lockscreen.qml`'s session lock is `secure` (the compositor acknowledged it), which `LockManager` reports as `lock.state`, with a lock surface on every monitor connected.
  - The report counts the lock surfaces `Lockscreen.qml` actually built (`LockManager.builtinSurfaces`) against `General.outputs`, so a monitor without one keeps the lock unconfirmed. With no monitor connected the session lock alone confirms it; `WlSessionLock` builds a surface for each monitor connected later.
  - A stopped shell's last report confirms nothing until the next shell reports.
- If that doesn't come within 3 s, the binary restarts the shell with `AXIOM_LOCK_ON_START=1`, which locks before anything else shows. If that fails too, `axiom lock` fails: the built-in locker has nothing to fall back on.
- A shell that dies while locked is restarted at once, locked. The compositor keeps the session locked meanwhile.
  - Locked here is the shell holding the lock (`holding`, `LockManager.builtinLocked`), acknowledged or not: a lock a reloaded generation took over never sees the compositor's acknowledgement again (`secure` stays false), and a shell restarted unlocked then left niri's red screen (2026-10-29).
- Nothing goes the other way: `lock.state` only informs, `lockscreen` takes no function but `lock`, and only PAM unlocks.
- With `Lockscreen.mode` `none`, `axiom lock` runs `Lockscreen.lockCommand`, except `loginctl lock-session`, which would come back to axiom through the idle daemon.

### Modes (`Lockscreen.mode`)

#### `quickshell` (default)
- The built-in locker, `shell/Lockscreen.qml`.
  - A `WlSessionLock` (Wayland `ext-session-lock-v1`).
  - One `WlSessionLockSurface` per Wayland output (Quickshell adds one for an output connected while locked), showing `surfaces/lockscreen/LockSurface.qml`.
- While locked, the compositor shows only the lock surfaces and sends them all input.
- If qs dies, the session stays locked (Hyprland's fallback). `misc:allow_session_lock_restore` lets a restarted qs take the lock back.
- The locked state lives in a `PersistentProperties`, so a QML reload never unlocks.
- A lock the compositor ends without PAM (its `finished`: it refused the lock, as when another locker holds the session) clears that state (`WlSessionLock.onLockedChanged`), so the shell stops holding a lock it hasn't got.

#### No reload under the lock
- **Why:** Quickshell 0.3's `WlSessionLock` hands its lock to the reloaded generation, but builds that generation's lock surfaces anew while the old ones still stand. A second lock surface for an output is a protocol error on niri (`Output is already locked.`) and sway (`session lock surface already created for the given output`), which ends qs and left niri's red screen with nothing to unlock it (2026-10-18, 2026-10-29). The log shows `Session lock object was destroyed without unlocking` as the old generation goes, on every reload under the lock, even one that worked (Hyprland let it through).
- **So:** while locked, `Lockscreen.qml` turns `Quickshell.watchFiles` off: a saved file doesn't reload the shell, and loads at the next save after unlocking.
- **Explicit reloads** (`/reload`, an auto self-update) go through `LockManager.reload()`, which waits for the unlock.
- New code never calls `Quickshell.reload` itself.
- **Only `AuthManager.authenticationSucceeded` (PAM, `login` stack) unlocks.**
  - There is no IPC unlock.
  - Nothing on the surface may run commands.

#### `none`
- Axiom provides no locker and no IPC target, so an idle daemon pointed at axiom can't loop through `loginctl lock-session`.
- Lock buttons run `Lockscreen.lockCommand`.

#### Idle and sleep
- With `Idle.enabled` the daemon locks on idle, on logind's lock request (`loginctl lock-session`) and before sleep, all through the locker above ([idle.md](idle.md)).
- A user's own hypridle (Idle off):
  - For the first two modes it uses `lock_cmd = axiom lock` and `before_sleep_cmd = loginctl lock-session`.
  - For `none` it has no axiom references.

### Layout
- **Where it lives:** `Lockscreen.layout`, marked `x-settings: false`.
- **Where it's edited:** the Layouts page's Lock screen row.
- **What a real lock shows:** only `LockscreenConfig.layout`, the saved layout. Unsaved drafts never reach a real lock.

#### Grid
- Overlay modules sit on a bounded grid fitted to each screen at the card size. The grid is a `ScreenLayout`, shared with the greeter. Its `columns` × `rows` (hidden, written by the editor) are the grid the modules were last placed on.
- **`grid.fine` ("Double grid")** splits each unit in two each way. `GridPlacement.screenGrid(layout)` gives the grid in the units places use.
  - Turning it on or off rescales every place (`GridPlacement.scalePlace`, in `ScreenLayoutEditor.updateLayoutField`). Merging rounds each edge, so modules that met still meet.
  - The `GridEditor`'s `sizeScale` doubles new modules' default sizes.
- **Fitting to the screen:** `LockSurface` is built on `surfaces/screenlayout/ScreenLayoutView`, which holds the background, dim and fitted grid it shares with `GreeterSurface` and the desktop. It takes `OverlayConfig.screenArrangement` (`GridPlacement.screenArrangement`):
  - cards of `OverlayConfig.cardUnitOn(screen.width, screen.height)` (two cards fill the short side, times `Widget.cardSize`%) times the layout's `moduleScale`%;
  - as many units as fit the screen inside a `cardSpacing` margin (`GridPlacement.screenLattice`, whole units even on a double grid), their gaps drawn at its zoom (`gap`, `GridPlacement.gapOf`), stretched by under a unit to sit flush (`ModuleGrid.stretch`);
  - each group of modules sharing some length of an edge (`GridPlacement.touchingGroups`; a corner alone doesn't join them) moved from the grid it was placed on to that one, keeping to its nearest side on each axis (the first or last third), else keeping its centre's share (`GridPlacement.anchorPlaces`). So corners stay corners on a wider screen or after a size change;
  - when that leaves modules overlapping or off the grid, the cards shrink a step at a time until they fit (`shrunk`), their content and gaps with them; at the latest, on the grid they were placed on nothing moves.
- **Content size:** content lays out at the card's size over its zoom, the layout's `moduleScale` (`zoom`, `ModuleGrid.zoom`, see [Edge menu hosts](../edge-menus/hosts.md)), so text is the Interface scale's (`Widget.scale`) times the Module size on every monitor.
- The editor (`ScreenLayoutEditor`) edits the layout as it shows on one screen (`screen`, `insets`; the primary monitor, or the desktop target's): loading it, or a change of screen or card size, rebases the places onto that screen's arrangement in the draft and in its saved copy alike (`rebase`), so the draft isn't marked changed. Moving modules never changes the grid under an edit. It draws that grid inside a screen outline (`ScreenLayoutTarget.screenBox`) and says when the modules had to shrink (`shrunk`, `shrunkTo`).

#### Hosts
- Modules get `host: { kind: "lockscreen", target, preview, key, bare, passwordBorder, greetingBorder }`.
- **`bare`** is `!moduleBorders`: no card box.
  - Unlike a bare edge menu module, it keeps its padding (`SlotContext.pad`), since nothing else pads it.
- **`Password` and `Greeting`** ignore `bare` here. Their boxes follow the layout's own `passwordBorder` / `greetingBorder` (off by default).
- **Which modules may go here:** only module types whose `x-hosts` list `lockscreen`.
  - Display-only modules.
  - NowPlaying (media transport) and VolumeDials.
  - Power: suspend, restart, shut down through `SessionManager.sessionAction`; restart and shut down ask twice.
  - Nothing that launches, dispatches, kills, writes files or shows private content.
- A new module stays off the lock screen unless it is added there deliberately.

#### Password
- **What it is:** the `Password` module (`x-hosts: ["lockscreen"]`, `x-required`) draws `content/parts/PasswordField`. The field talks to `AuthManager`.
- **When it's live:** the field keeps keyboard focus only when `active`, which means on the `target` screen of a real lock (`host.target && !host.preview`). Anywhere else it is inert.
- **Required-field report:** the module reports itself to `SurfaceManager.reportRequiredField(host.key, true)`.
  - Each surface's key comes from `SurfaceManager.newSurfaceKey(kind)` and is never reused.
  - Keys used to be screen names. A monitor that dropped out and came back while turning off then had its old surface's teardown clear the new surface's report, which flickered the fallback in.
- **Fallback field:** a surface whose key has no report shows a `PasswordField` of its own, so a hand-edited or broken layout can never lock anyone out.
  - It appears a tick after loading, near the bottom, over the modules.
- **Stable layout:** the field never moves or grows with its messages (`reusable/PasswordEntry`).
  - The message line's room is kept (`reserveMessage`).
  - The busy bar runs over the field's bottom edge.
- **Short slots:** a slot too short for the message line (one row on a doubled grid) changes the layout, as the greeter's `Login` does:
  - the card padding is dropped;
  - the field shrinks to fit;
  - the message shows as the empty field's placeholder (`inlineMessage`).
- **Focus** comes back through `content/parts/FocusKeeper` (also used by `LoginField`).
  - It waits while a clicked control is pressed, because a button that loses focus mid-press drops its click (the calendar arrows did).
- `AuthManager` answers PAM's prompts without showing them.

#### Other screens (`otherScreens`)
- `layout`: shows the modules without `Password`.
- `background`: shows only the background.

#### Background
- `background` is one of:
  - `wallpaper`: `ThemeManager.wallpaperFor(screen)`, blurred by a `MultiEffect` when the layout's `backdrop.blur` is on (each layout has its own: the lock screen's and the login screen's are independent).
  - `color`: `backgroundColor`.
- Either way it sits under a black layer at `dim`%.

#### Greeting module
- `content/Greeting` works on any host. It draws a line of text fitted to its slot (`Text.Fit`).
- Placeholders:
  - `{name}`
  - `{user}`
  - `{greeting}`: a `SystemClock` at hour precision, running only while the text uses it.
- Empty text means the translated "Hey {0}".
- On the real greeter the names are `GreetdManager.selectedUser`'s. With no user selected yet it shows "Welcome".

### Editing and preview
- **The editor:** `LockManager.editor` is a `services/ui/ScreenLayoutEditor`, a non-singleton shared with the greeter. It holds:
  - the draft, a `ConfigDraft` of `["Lockscreen", "layout"]`, so it never fights the settings page's draft over `mode`;
  - its `GridEditor` (`layout`);
  - `problems`, `updateLayoutField`, `ensureLoaded` / `saveChanges` / `resetChanges`;
  - the preview.
- **Show on screen** (`startPreview()`):
  - It closes the overlay and shows `surfaces/lockscreen/LockPreviewWindow` on the target screen. The screen is fixed when the preview starts (`previewScreen`).
  - That window is on the Overlay layer, with exclusive keyboard focus, and holds `LockSurface { preview: true }` showing the draft.
  - Nothing is locked, and the field is inert (it lets Escape through).
  - Escape or a click on the background (`stopPreview()`) reopens the overlay on Layouts.

### Testing
- Look at the lock screen through `LockManager.editor.startPreview()` (a `ScreenLayoutEditor`), called from a temporary `IpcTarget` in `shell.qml`; revert the handler afterwards.
- Put demo layouts on the draft only, then `resetChanges`.
- Test `LockSurface` in a hidden window, never by locking for real: only the user can type the password.
