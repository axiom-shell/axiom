# Known issues

> **Files:** this file only
> **Config:** none
> **Related:** [Developer docs](README.md), [testing](testing.md)

Problems found while working on something else: not fixed yet, but recorded so they aren't lost. **Add an entry whenever you find a problem outside the task at hand** rather than fixing it unasked or only mentioning it. Remove the entry in the change that fixes it. Before starting work in an area, check here for what's already known about it. This is a working list for coding agents and the maintainer, meant to move to GitHub over time: it's not where to report or look up problems, which is [GitHub issues](https://github.com/axiom-shell/axiom/issues). Agents never open a GitHub issue themselves; the maintainer moves an entry there.

Every entry is linked from the phase of the [cleanup roadmap](roadmap.md) that resolves it: add the link with a new entry, and remove it with the entry (`scripts/check_docs.py` fails on a link to an entry that's gone and warns about an entry the roadmap doesn't link).

Each entry is a `###` heading plus these four bullets, in this order (`scripts/check_docs.py` checks the shape and that cited paths and members exist):

```
### <Short title>
- **Where:** `path/File.qml` (symbol, or several paths)
- **What:** what's wrong and the evidence (log line, grep count, failing case); quote a log warning's message in backticks so verify.sh marks it known (when it comes from a file **Where** cites, by its `@path` or a `[Name]` tag; one from Qt or Quickshell that names no file: quote its category too, `quickshell.I3.ipc`)
- **Size:** trivial | small | needs a plan (designed first: the roadmap's Items that need a plan)
- **Found:** YYYY-MM-DD, while <task>
```

## Open

### "Colour the text by state" does nothing on a bar whose widgets have no fill
- **Where:** `qml/components/methods/BarWidgetStyle.qml` (`textByState`, `_make`)
- **What:** `textByState` asks `colors.fill.a < 1`, but `colors()` gives an unfilled style (outline, underline, accentText, plain, and a merged run's widgets) the string `"transparent"` as its fill, whose `.a` is undefined (checked in qmltestrunner: `"transparent".a` is `undefined`, `Qt.color("transparent").a` is 0). So `appearance.colorText` takes effect only on a tinted bar, where display-styles.md says it colours the text wherever it isn't the background's fill. Fix: `Qt.color(colors.fill).a < 1`, with a test row; but a merged run on a filled bar then puts the state colour on the run's own fill (its widgets' fill is transparent, the run's isn't), so whether that counts as a fill is a look choice for the maintainer.
- **Size:** trivial
- **Found:** 2026-11-06, while sharing SystemStats' text-by-state rule (row 20)

### A fading toast keeps its full blur on niri
- **Where:** `qml/components/surfaces/notifications/ToastStack.qml` (its `BlurShape`), `qml/shell/BlurBackingWindow.qml` (`_piecesOf`)
- **What:** On niri (`supports.blurRegion`) a toast's blur-window rect fades through its colour's alpha (`color: Qt.alpha(Theme.background, toastCard.opacity)`), but `_piecesOf` cuts a shape's region off only by its source's `shownOpacity` / `hostOpacity`, which a toast's box doesn't have, so the full region is blurred while the toast fades in and out. Hyprland's `ignore_alpha` and SwayFX drop it at the threshold. Fix: give the cut-off the shape's colour alpha too (or the toast box a `shownOpacity`).
- **Size:** small
- **Found:** 2026-11-05, while reviewing the floating popouts branch

### A latched held dock's gap to its edge swallows clicks while the pointer is in it
- **Where:** `qml/components/surfaces/dock/DockWindow.qml` (`inputArea.fromEdge`, `hover`, `pointerIn`)
- **What:** A held hover or intellihide dock takes the gap from the screen edge to its box into its input mask while latched, so the pointer coming in from the trigger doesn't leave it on the way. The `HoverHandler` covers the whole window (`dockContent` fills it), so once latched, the pointer anywhere in that gap counts as on the dock: moving from the box toward the edge keeps it open (`closeTimer` stopped) and clicks on the windows there go to the dock. With `distance` (up to 50% of the free screen, where the old px `gap` was at most 200) that strip can be half the screen. Options: the gap only until the pointer first reaches the box, hover only on the box (the gap kept for the trigger's path alone), or keep it.
- **Size:** small
- **Found:** 2026-11-05, while reviewing the floating popouts branch

### A reserving held dock reserves the screen up to its distance
- **Where:** `qml/components/surfaces/dock/DockWindow.qml` (`panelWindow.exclusiveZone`)
- **What:** An always-shown held dock with Reserve space (both defaults) reserves `boxOffset + thickness`, from its edge to the box's far side. With `distance` (0–50% across the free screen, new in place of a px `gap` of at most 200) a dock at 50% reserves half the screen, and the windows tile into the other half. A layer surface can only reserve from its edge, so the choice is the maintainer's: hide Reserve space past a distance of 0, reserve only at 0, or keep it.
- **Size:** small
- **Found:** 2026-11-05, while reviewing the floating popouts branch (round 2)

### A hide while a popout closes leaves its queued show to open it
- **Where:** `qml/components/hosts/popout/PopoutWrapperBase.qml` (`hide`, `safeOpenPopout`), `qml/shell/WindowSwitcher.qml` (`sync`)
- **What:** `show()` during the close animation queues the open (`hasPendingOpen`), but `hide()` acts only `if (isOpen)`, false while closing, so a hide before the close finishes leaves the queued open to fire (`closeDelayTimer` → `_openPending`): the popout opens with nothing wanting it. The window switcher reaches it: `showDelay` (default 120 ms) is under `animNormal` (150 ms), so released, pressed again and released within the close (held past `showDelay`) leaves the strip up with `autoDismiss: false` until the switcher opens again. Fix: `hide()` also drops a pending open (`hasPendingOpen = false`).
- **Size:** trivial
- **Found:** 2026-11-05, while reviewing the floating popouts branch (round 3)

### A detached dock and toasts don't slide in from under the bars
- **Where:** `qml/components/surfaces/dock/DockWindow.qml` (`_detachedBox`, `slide`), `qml/components/surfaces/notifications/ToastStack.qml` (`area`)
- **What:** Every other detached box slides in from off the screen under the bars on Hyprland ([Held off an edge › Sliding in from off the screen](popouts/held-off-edge.md#sliding-in-from-off-the-screen)), but these two don't. A detached dock slides out from its window's edge at the reserved line: its window is always mapped (`axiom-dock`, ordered over the bars), and when held and reserving, its exclusive zone ends at its box, so a window reaching back to the screen edge needs its own design. The toasts' area window is always mapped on the Overlay layer, so a detached toast slides from that window's edge, over the bars, or from the screen edge over a fullscreen window. Going under the bars needs a Top window under them that moves to Overlay over a fullscreen window, and Hyprland reads a layer rule's `order` only as a surface maps: measure that in a nested Hyprland first.
- **Size:** needs a plan
- **Found:** 2026-11-05, while making every floating popout slide in from off the screen

### A menu at the screen-size cap can still lose a bar's depth
- **Where:** `qml/config/EdgeMenusConfig.qml` (`scaleOf`)
- **What:** `scaleOf` shrinks a menu's Module size so its depth across its edge fits the screen less its padding (`GridPlacement.fitModuleScale`). Worked out from config alone, it doesn't take off what the bars and border reserve across that edge (EdgeMenuManager's frame, `frame.across`), so a menu at the cap sits past them and loses about their depth at the far screen edge (a nested niri run, 2026-11-05: a top menu at Module size 200 reached the screen's bottom edge). Fix: take the frame's `across` off the room too, from the hosts (which know the frame), or leave it (rare: it takes a card size and Module size high enough to reach the cap). Kept as built by the coordinator (2026-11-05): rare path, no product stake.
- **Size:** small
- **Found:** 2026-11-05, while fixing bar-popouts-07 (row 20)

### The tray watcher check could start a watcher by D-Bus activation
- **Where:** `backend/internal/inputmethod/fcitx5.go` (`followFcitx`)
- **What:** `tray()` reads `org.kde.StatusNotifierWatcher`'s `RegisteredStatusNotifierItems` without the NoAutoStart flag, so on a system shipping an activatable watcher (none here: `org.x.StatusNotifierWatcher` is the only activatable one) the read would start it. Asking `NameHasOwner` first, or sending NoAutoStart, avoids it.
- **Size:** trivial
- **Found:** 2026-11-05, while reviewing input sources (Go, round 7)

### A bar Grid warns as its bar turns between horizontal and vertical
- **Where:** `qml/components/bar/widgets/Workspaces/WorkspaceCellRow.qml` (`cells`), `qml/components/bar/widgets/Workspaces/WorkspaceStrip.qml` (`layout`), `qml/components/bar/widgets/SystemTray/SystemTray.qml` (`items`)
- **What:** These Grids bind `rows` and `columns` to `isVertical` apart (`rows: isVertical ? -1 : 1`, `columns: isVertical ? 1 : -1`; the tray's to its count), so as a bar turns, one is updated before the other and for a moment both are 1: the live log (a bar editing session, 2026-11-05) has `Grid contains more visible items (3) than rows*columns (1)` from WorkspaceCellRow.qml and `(6)` from SystemTray.qml. Reproduced in a qmltestrunner Grid flipping a bound orientation. Harmless (the next layout pass fits). Fix: one positioner per orientation, or a check that leaves the flip quiet.
- **Size:** small
- **Found:** 2026-11-05, while fixing WorkspaceStrip's Grid lag (compositor-17)

### A fitted wallpaper a pixel off the screen's shape shows a band at the parallax's ends
- **Where:** `qml/components/methods/WallpaperFill.qml` (`rect`'s `grow`)
- **What:** With `fill: fit` and the parallax on, `rect` grows the image only by the sides that cover the screen at rest (`w >= 1 - 1e-9`). An image a hair off the screen's shape (1920x1079 on 1920x1080, travel 4%) leaves half a pixel of letterbox at rest, so its height counts as not covering: grown by the width alone, at the first and last workspace of a vertical slide (niri, a grid) it leaves a 13.6 px band of background at the top or bottom, where a 1920x1080 image (and the same image before the parallax measured travel) covers. The gap jumps from 0 to about `px/screenHeight - px/screenWidth` of the screen at that threshold. Fix (a look choice, for the maintainer): grow each side by what it covered (`(Math.min(s, 1) + travel) / s`, as the comment once said: this also grows a clearly letterboxed fit image more, 7% instead of 3% for 21:9 on 16:9), or count a side within a screen pixel of covering as covering (narrows the jump to images 1 px off, not gone).
- **Size:** small
- **Found:** 2026-11-05, while reviewing the wallpaper chunk of the tweaks-minor-complaints branch

### A VPN bind ignores Tailscale unless a VPN widget is showing
- **Where:** `qml/services/system/VpnManager.qml` (`_tailscaleShown`, `toggleLast`)
- **What:** Tailscale joins `rows` only while something acquires the VPN state (`_registry.active`), so `axiom ipc vpn toggle` from a keybind, hot corner or `axiom vpn toggle` sees only NetworkManager VPNs: with Tailscale the only VPN it says "No VPN set up", and with Tailscale up it brings the last NetworkManager VPN up instead of taking Tailscale down. The IPC toggle should read Tailscale's state once (acquire, act, release) before choosing.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the bindable commands

### The dev config's diff compares lists whole
- **Where:** `backend/internal/devconfig/diff.go` (`Rows`), `qml/components/views/Settings/DevConfigDiffCard.qml`
- **What:** `dev.config.diff` takes its paths from `config.Diff`, which sets a list whole, so a list differing anywhere (one bar widget's setting in `Bars`, one page in `Overlay.items`) is one row holding the whole list, and copying it copies every item, dev's other edits and live's alike. Lists of objects with ids (bars, pages, edge menus, OSDs, widgets) should compare per id: a row per item added, removed or changed, each copied on its own (`{id}` selectors, as `config.set` takes). Decided for v1 (the restructure's plan, Decided 8): "Lists are compared whole in v1 (per-id rows are an issues.md follow-up)".
- **Size:** small
- **Found:** 2026-11-03, while documenting the dev config

### Copying a setting to live uses dev's paths, which an older live may not have
- **Where:** `backend/internal/daemon/devsync.go` (`configCopy`), `backend/internal/devconfig/devconfig.go` (`WriteLive`)
- **What:** A copy to live applies dev's ops (paths in the dev tree's shape) to live's raw JSON and checks the result against the install's schema. When the install is older (a setting the dev tree moved or reshaped, a section live hasn't migrated to), the op lands where the install doesn't look, or the check refuses it with the install schema's issue, which names a path the user didn't pick; the diff only marks settings the install's schema lacks entirely (`devOnly`), not ones it has at another path or shape. Nothing says the two configs are of different versions, or that updating the install would let the copy through.
- **Size:** small
- **Found:** 2026-11-03, while building the dev config's copy to live

### Wallpapers list only jpg, png and bmp
- **Where:** `qml/services/ui/WallpaperManager.qml` (`_extensions`), `backend/internal/files/list.go`
- **What:** An idea from the wallpaper transitions branch, not a bug: the wallpaper list takes jpg, jpeg, png and bmp only, though Qt reads webp (and avif and jxl with their image format plugins) and the theme generator already decodes webp (`golang.org/x/image`). Adding them is a longer `_extensions` (and the folder count in `checkFolder`), the theme generator's formats checked for each, and the Qt plugins as optional packages where they aren't in qt6-base.
- **Size:** small
- **Found:** 2026-11-01, while adding wallpaper transitions

### Video wallpapers
- **Where:** `qml/components/surfaces/wallpaper/WallpaperView.qml`, `qml/services/core/ThemeManager.qml` (generateThemesFromWallpaper)
- **What:** An idea from the wallpaper transitions branch, not a bug: mp4/webm wallpapers through QtMultimedia. It adds a dependency and a steady GPU and battery cost, the transitions would need a video's frame as a texture, and generating a theme needs a still frame grabbed from it. Kept out of the branch (maintainer, 2026-11-01: not picked among the wallpaper improvements).
- **Size:** needs a plan
- **Found:** 2026-11-01, while adding wallpaper transitions

### Eject may leave a USB stick powered on
- **Where:** `backend/internal/udisks/udisks.go` (`eject`)
- **What:** `eject` picks the Drive's `Eject` over `PowerOff` for any drive with `CanEject` and removable media (`case drive.Optical || drive.CanEject && drive.mediaRemovable:` before `case drive.CanPowerOff:`). If udisks2 reports a USB stick with the removable bit as Ejectable, it only gets `Eject`: it stays in udisks2 without media (hidden, `removed` sent) but powered, which contradicts `docs/dev/features/drives.md` ("locks and powers off"). A card reader's card wants `Eject` (the reader stays). PLAUSIBLE: `udisksctl info -b /dev/sdX` on a real stick (Ejectable, CanPowerOff, MediaRemovable) settles it. Fix, if it holds: `PowerOff` first when `CanPowerOff` and the drive isn't a card reader (`Optical` or a media-changing reader keeps `Eject`), the way GNOME's gvfs powers off a stick after its eject.
- **Size:** small
- **Found:** 2026-11-01, while reviewing removable drive support

### The axiom CLI can't send a notification
- **Where:** `backend/internal/cli/named.go`, `backend/internal/daemon/tools.go`, `backend/internal/notification/notify.go`
- **What:** A feature request from the maintainer (2026-11-02, "yes file the cli notification support where it goes"): with notify-send gone as a dependency, the daemon's `notify.send` and `notify.action` are reached only by the shell, and the CLI's `axiom notifications` only clears them and switches do-not-disturb. A command such as `axiom notify "title" "body" [--icon --urgency --action id=Label --wait]` would wrap them for scripts: it sends through the daemon, and with `--wait` blocks until a button is picked or the notification closes, printing the button's id as `notify-send --action` does. It should share its flags with `axiom message` (the OSD message command) where they overlap, and take the levels' `--key` (one entry per key: `x-axiom-key`) and `--transient`; `--silent` would need a daemon push to the shell's `_file`, since a silent one never goes over D-Bus.
- **Size:** small
- **Found:** 2026-11-02, while removing the notify-send dependency (roadmap row 20, platform-03)

### A bind can't be limited to some compositors
- **Where:** `qml/config/schema/sections/Keybinds.yaml`, `qml/services/compositor/KeybindManager.qml`, `qml/components/views/Keybinds/BindEditor.qml`, `qml/components/views/Keybinds/FilterChips.qml`
- **What:** A feature request from the maintainer (2026-11-02): "add another config option for binds that is only on (default nothing selected), and can pick any if the three compositors (multiple allowed) (i.e. this bind is only niri, or this bind is only sway/hyprland)". With the improvements proposed alongside it ("just add the issue and roadmap entries"): (1) one multi-select, "Only on": Hyprland, sway, niri, plus "Scrolling strips" and "Tiling" (no strips), empty meaning everywhere, so a later compositor with strips gets those binds by capability, not by name. "Scrolling strips" means strips in use, not `supports.strips` alone (maintainer, 2026-11-02: "hyprland supports strips but should only be active if strips are on right?"): `supports.strips` only says a compositor can do strips (Hyprland has it); strips are in use where every workspace is one (`supports.stripsAlways`: niri) or where an output's strip direction is set (`CompositorManager.stripDirection`, from `WorkspacesConfig`). Open for the plan: Hyprland turns strips on per output while its binds are global, so either a strips-only bind is written while any output is a strip (the simpler default: `WorkspacesConfig.hasStrips`) or it acts only when the focused output is one; (2) two binds on the same keys whose "Only on" sets don't overlap aren't a conflict (one key, a niri and a sway meaning); (3) set by itself where a bind can only work on one: a raw-command bind defaults to its compositor, a bind moved in from a compositor's own config gets that compositor, and an action that needs strips counts as strips-only without the user setting it; (4) the Keybinds page lists binds that don't apply here dimmed, with an "only on" chip and a filter, still editable, while the cheatsheet and the keyboard reference show only the binds that apply; (5) the default is an empty list, so no migration, and saved configs and presets carry it (it describes the bind, not the machine). Each compositor's config writer leaves out the binds that don't apply to it.
- **Size:** needs a plan
- **Found:** 2026-11-02, while running the roadmap autopilot (the maintainer's request)

### Toggles are switched in several places, and most have no IPC
- **Where:** `qml/components/content/QuickActions/QuickActions.qml`, `qml/components/surfaces/osd/OSDStatusSource.qml` (toggle), `qml/services/ui/LauncherCommands.qml`
- **What:** Wi-Fi, Bluetooth, caffeine, do not disturb, night light, power saver and dark mode are each flipped by their own switch in QuickActions, the OSD's status icons and the launcher commands, all calling the same service functions. Wi-Fi, Bluetooth, airplane mode, dark mode, the power profile and the keyboard layout have no `IpcTarget`, so no keybind or hot corner can reach them (the bindable actions cover about 32 of some 140 IPC functions). One catalogue of actions (id, label, icon, run, state) could serve all of them and the keybinds; the maintainer plans it as its own change.
- **Size:** needs a plan
- **Found:** 2026-11-01, while making the OSD's status icons clickable

### In dev mode a reshaped schema can prune the dev config before its migration runs
- **Where:** `backend/internal/daemon/dev.go` (`watchSchema`, `rebuildSchema`), `docs/dev/backend/README.md`
- **What:** In the dev image the shell loads a schema rebuilt from the dev tree's YAML within 100 ms of an edit, while the running dev build still has the old migrations until its own build (after 1 s of quiet, then `go build`) re-execs, or for good when that build fails. A settings save in between validates and prunes the dev config against the new shape, so keys a new step would have moved are dropped instead of migrated. Seen 2026-11-01 (before the dev config, on the live one): v87 split each OSD's `items` into `bars` / `statuses` / `media`; a save from the settings page before the daemon ran v87 wrote the new shape with default `bars`, losing every OSD's own bars (`version` still 86, so v87 later skips the already reshaped entries). Since dev mode runs on its own config (`$XDG_CONFIG_HOME/axiom/dev/config.json`), only the dev config can lose them; live is written only by a copy or the takeover mirror, checked against the install's schema. Saving should hold off, or the daemon refuse a write, while the tree's schema version is ahead of the binary's steps.
- **Size:** small
- **Found:** 2026-11-01, while splitting the OSD's items (config v87)

### The lock screen has no settings for allowing or viewing notifications
- **Where:** `qml/config/schema/sections/Lockscreen.yaml`, `docs/dev/features/lockscreen.md`
- **What:** Asked by the maintainer (2026-10-31) beside the x-lockActions decision: "there should be settings for allowing/viewing notifications as well" on the lock screen. Not designed yet.

  **Decided** (maintainer, 2026-11-01, on the recommendation "defer"): "defer".
- **Size:** needs a plan
- **Found:** 2026-11-01, while recording the maintainer's answers to the clear-out's questions

### A pill bar stacked inside another pill bar grows its pills out of nothing
- **Where:** `qml/components/bar/BarContainer.qml` (`borderOpening`), `qml/components/methods/BarEnds.qml` (`placeStack`)
- **What:** A pill bar's pills grow out of a stroke at its outer edge: the border's, which they cover and open. Stacked inside another pill bar (`offBorder`: pill bars are the first kind inside the border), there is no such stroke. Its outer edge lies on the far side of the bar outside it, which only that bar's pills stroke. Where an inner pill sits under an outer pill it joins that pill's far stroke and looks right; seen in a nested niri (two top pill bars, the inner one's end pills under the outer one's). Under a gap between the outer bar's pills, its outer side is open and its fillets curve into nothing. Since `offBorder`, it opens no border stroke (it used to cut the border's under the outer bar), and merged popouts on it open none either. Open for the plan: draw an inner pill bar's pills closed on their outer side (as islands), stretch the outer bar's pills over them, or leave pills inside the border's first bar to the user.
- **Size:** needs a plan
- **Found:** 2026-11-01, while adding stacked bars

### The chat has no slash commands to control it
- **Where:** `qml/components/content/parts/chat/ChatComposer.qml` (`_send`), `qml/services/apps/ChatManager.qml` (`send`), `qml/services/ui/LauncherCommands.qml` (`chat`), `qml/services/ui/LauncherManager.qml` (`_chatRow`)
- **What:** The maintainer (2026-11-01): "add chat slash commands for control to roadmap where necessary". Today the chat's composer handles no `/` input: `_send` hands the text to `ChatManager.send`, which sends `/new` to the model like any message. Outside the chat, the launcher's `@question` (`_chatRow`) and IPC `chat ask` start a new conversation with the default preset and send the question (`ChatManager.ask`); the launcher's `/chat` (alias `/ai`) opens the chat, a new conversation or a saved one; IPC `chat` also has `open`, `newChat` and `settings`. Every other control is a button only: New conversation (the header), Stop (the send button while busy), the preset and model pick (`ModelPicker`), regenerate, copy and remove a message (`ChatMessage`), rename, open and delete a conversation (`ConversationList`), attach the clipboard or a screenshot (the composer's buttons), and the provider's key (`openSettings`). Open for the plan: which of these get a command in the composer (candidates: new, stop, preset, model, regenerate, rename, delete, attach, settings, help), how they're offered (a suggestion list while typing `/`, as the launcher does), how a message really starting with `/` is sent, and whether the launcher's `/chat` takes the same commands.
- **Size:** needs a plan
- **Found:** 2026-11-01, while filing the maintainer's notes

### A VPN's password request can go unseen
- **Where:** `qml/services/system/VpnManager.qml` (`secretRequest`), `backend/internal/daemon/vpn.go` (`OnSecret`)
- **What:** axiom takes NetworkManager's secret request whenever the shell is connected, but only a `VpnRow` shows it: the Wi-Fi menu (with its VPN section), the VPN popout or a VPN card. A VPN needing a password brought up from `/vpn` in the launcher, the `vpn` keybind action, or a click on a `Vpn` widget in an edge menu, shows its field nowhere: the row reads "Connecting…" until NetworkManager gives up, and nm-applet is never asked. Open: whether the request opens the VPN popout, sends a notification that opens it, or axiom answers `NoSecrets` while no row is shown (so another agent asks).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the VPN branch

### BlurManager.paused and WallpaperManager.rotationHeld read undefined on a reload
- **Where:** `qml/services/ui/BlurManager.qml` (`paused`), `qml/services/ui/WallpaperManager.qml` (`rotationHeld`), `qml/services/compositor/HyprlandManager.qml` (`activeWindowId`)
- **What:** A hot reload logged `@services/ui/BlurManager.qml[36:3]: Unable to assign [undefined] to bool` once (2026-10-30, after saving QML files under `qml/components/content/`; neither file the binding reads had changed). `paused` is a `&&` chain whose last term is `General.outputs.some(…)`; something in it (likely a singleton not ready yet during the reload, or `Appearance.blurPauseFullscreen`) reads undefined for a moment. Harmless (it settles at once), but it's log noise; `=== true` on the term that can be undefined, or `!!` on the chain, would silence it once the term is found. `WallpaperManager.rotationHeld`, the same shape (`&&`/`||` chains ending in `General.outputs.some(…)` and service reads), logged `@services/ui/WallpaperManager.qml[271:3]: Unable to assign [undefined] to bool` on a reload (2026-11-01, switching the checkout to a branch). `HyprlandManager.activeWindowId` (`"0x" + Hyprland.activeToplevel.address`, the toplevel there but its address not yet) logged `@services/compositor/HyprlandManager.qml[38:3]: Unable to assign [undefined] to QString` three times on a reload (2026-11-04, saving page window files).
- **Size:** trivial
- **Found:** 2026-10-30, while building the network popout's VPN fold and connection details

### A custom element sees another kind's element as its slot changes kind
- **Where:** `qml/components/content/parts/custom/CustomElement.qml` (`_load`), `qml/components/content/parts/custom/elements/Button/CustomButton.qml` (`label`, `icon`), `qml/components/content/parts/custom/elements/Toggle/CustomToggle.qml` (`label`)
- **What:** When a slot's element changes kind (the default Ring + Text giving way to a definition's own elements, or an element removed in the editor), the loaded item's bound `element` takes the new kind's element before `onKindChanged` reloads it: what overlay-modules-09 gave CustomRing's `inside` a `?? ""` for. Only Ring was quieted; a Button or Toggle handed another kind's options assigns an undefined `options.label` (and Button's `options.icon`) to a string the same way. PLAUSIBLE: a Button slot turning into another kind with the log open settles it. Fix at the cause: bind the item's `element` only while its kind matches the one loaded (keep the last matching element otherwise), then drop Ring's `?? ""`.
- **Size:** small
- **Found:** 2026-11-05, while reviewing the overlay and custom widgets minor sweep (overlay-modules-09)

### A hot corner can't close what covers it
- **Where:** `qml/shell/HotCorners.qml` (its layer, `LayerStack`), `docs/dev/features/hot-corners.md`
- **What:** Hot corners sit on the Top layer, so a surface on the `Overlay` layer (axiom's workspace overview, a full-screen overlay page) covers the corner pixel: a toggling action opens it from a corner but can't close it there. niri's own corner toggles its overview; the migrated corner (v82) does that only while `WorkspaceOverlay.compositorOverview` is on. Whether a corner should stay live over Overlay-layer surfaces is the maintainer's call.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the hot corners branch (row 16)

### Close on outside click differs on Hyprland since the overlay ignores its grab ending
- **Where:** `qml/components/hosts/overlay/OverlayPanel.qml` (`grab`, `onClickedOutside`), `qml/services/compositor/FocusGrab.qml` (`clickedOutside`)
- **What:** With `Overlay.closeOnOutsideClick` on, the overlay now closes on its empty background (`backgroundClicks`) everywhere, and, without a native grab (sway, niri), on a press on any screen's backdrop: another monitor, the screen border (its mask is empty), a floating bar's gap. On Hyprland those clicks only end its native grab, which it no longer closes on (that also fires when a popout's or the dock menu's own grab starts over it, one native grab at a time), so they leave it open, where before this change they closed it on every compositor. The maintainer decided on #211 "only where the blur backing would be": whether those places count (another monitor has no backing; the border covers it; a bar's gap shows it) decides the fix: none on sway and niri dropping `clickedOutside`, or on Hyprland closing on `FocusGrab.dismissed` (a native grab cleared with no newer grab started, as edge and floating popouts do since bar-popouts-02) or a backdrop that takes the click.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the overlay and popouts plan's build (row 16)

### The overlay's gaps can't be adjusted
- **Where:** `qml/components/methods/GridPlacement.qml` (`cardSpacing`, `baseCard`, `gapOf`), `qml/config/OverlayConfig.qml` (`boxPadding`)
- **What:** The maintainer's note: "the overlay's gaps become adjustable". The gaps are one design value, `GridPlacement.cardSpacing` = 20: the gap between modules, the margin around the grid, the overlay box's padding and the tool pages' spacing; through `baseCard` and `gapOf` edge menus, the desktop, the lock screen and the greeter are drawn as the overlay's grid scaled. Answered so far (2026-10-29): "one setting, gaps between modules and edges of the overlay page look the same". Open: the overlay's alone, or one Look & Feel setting for the overlay, lock screen, greeter and desktop with edge menus kept at today's value (the maintainer: "Menus already seem smaller"); a bigger gap shrinks the cards on a page fitted to its screen. Deferred: "defer for now, still unsure".
- **Size:** small
- **Found:** 2026-10-29, while splitting Phase 13 step 2 (row 16)

### Submenus don't always get their blur backing
- **Where:** `qml/components/hosts/popout/SubPopout.qml` (the surface's `backed`, `parentOrigin`)
- **What:** The maintainer sees submenus (a popout's or an edge menu's) open without the blur behind them some of the time; not reproduced yet. A lead: `backed` also needs `parentOrigin` (`slot.popupScreenOrigin`, where the parent's window is on screen), so a submenu opened before that's known stays unbacked until something re-evaluates it; `onOverlayLayer` follows its host too.
- **Size:** small
- **Found:** 2026-10-29, while building custom widgets (reported by the maintainer)

### The daemon never watches config.json, so outside edits aren't read
- **Where:** `backend/internal/store/store.go` (`Watch`), `backend/internal/daemon/methods.go` (`configPart`)
- **What:** Nothing starts `Store.Watch`: a5ca837 (2026-10-24) removed `serve("the config watch", d.store.Watch)` from the daemon and no part runs it since (`git grep 'store.Watch' -- backend/internal/daemon` is empty). An outside edit (an editor, `axiom config set --offline`, a sync tool) is read only at the next load (a re-exec or a dev-mode `Reschema`) or, since config-02, at the next save, which it makes refuse as a Conflict (`Store.write` reads it then). Seen 2026-11-01: a hand fix of a config the daemon had started on the defaults over stayed unread (`axiom config status` kept the old problems, nothing in the daemon log) until a dev rebuild re-exec'd the daemon; an earlier hand edit was overwritten by a save from the shell's copy, never having been read. That explains the 2026-10-29 sighting (a rename not read for 15 s and more; an in-place rewrite that seemed read was likely a re-exec's load). Fix: `run: d.store.Watch` on `configPart`, with a daemon test that an outside edit is pushed. Related: `axiom config validate` checks against the installed binary's schema, not the running daemon's, so under dev mode it calls a config with new types invalid that the daemon accepts.
- **Size:** trivial
- **Found:** 2026-10-29, while testing custom widgets on the live config; cause found 2026-11-01, while renaming the OSD's audio statuses

### With no takeovers kept, a broken config.json can still release the compositor's config
- **Where:** `backend/internal/store/store.go` (`loadInitial`, `write`, `holdTakeovers`), `backend/internal/compositor/manager/manager.go` (`ConfigChanged`)
- **What:** The store reads the takeover values from `$XDG_STATE_HOME/axiom/takeovers.json` when config.json isn't JSON at the start. With none kept (the first start of this version on a file already broken, the state folder wiped) they're unknown: a restore, import or reset is refused (`write`; decided 2026-10-28: "Refuse, clearer message", which the Saved configs page shows), and the first hand fix that loads sets them as it reads, so a fix saying detached gives back a managed config applied before. The compositor manager's own hold, deleted in row 12, kept the mode applied in that case (`AppliedMode`, or `configIsOurs` / `moduleLoaded` after a reboot) and saved it back. Accepted by the maintainer (2026-10-28, #163): with no takeovers kept, a restore is refused and a hand fix sets the takeovers as it reads.
- **Size:** needs a plan
- **Found:** 2026-10-28, while reviewing row 12's third batch

### The daemon's own commands are left zombies across a re-exec
- **Where:** `backend/internal/updates/updates.go`, `backend/internal/brightness/brightness.go`, `backend/internal/tailscale/tailscale.go`
- **What:** The commands the daemon runs for itself (`checkupdates`, `ddcutil`, `tailscale`, …) start through their own `exec.Command`, not `command.start`, so a re-exec doesn't hand them on (`command.Children`, which covers `exec.run` and the watches): one in flight when the image is replaced stays a zombie until the daemon quits. `ps --ppid <axiom run>` on 2026-10-27 showed 58, from about a dozen dev-mode re-execs (36 `qs`, 9 `checkupdates`, 2 `ddcutil`, `tailscale`, and 8 `bash`, likely `exec.run`'s from before the handoff). Later the same day the same daemon (about 9 h of dev-mode re-execs) had 104: 61 `qs`, 18 `checkupdates`, 8 `bash`, 7 `bat`, 5 `ddcutil`, 3 `tailscale`, mostly in groups started in the same second, the commands a fresh image runs at once (`ipcroute`'s `qs ipc --pid … show` and `call`, gone since, and the startup checks). The `qs` ones were those `qs ipc` ran, not shells: the shell a re-exec adopts is waited on and reaped (`supervise.Supervisor.adopt`), and only ever one runs. Running them through `command.Run` with the daemon's `Children` would cover them.
- **Size:** small
- **Found:** 2026-10-27, while handing exec's commands across a re-exec

### Leaving managed, the runtime layer can go on before the given-back config reloads
- **Where:** `backend/internal/compositor/manager/manager.go` (`SetInputs`, `liveChanged`, `apply`)
- **What:** The shell's first inputs arm both `debounce` and `liveDebounce` (300 ms each). When the live one fires first, `liveChanged` sees `AppliedMode != mode` and calls `apply`, which releases the managed config and asks for a reload; the layer debounce's `apply` then runs `runtimeApply` before that reload lands, so the runtime layer reads the managed config's binds (every axiom key looks taken, each logged once) and goes on over it. It's corrected after the reload (`configReloaded` applies again). Holding `runtimeApply` until `configReloaded` after a release that reloads would close it, but a missed reload event would then leave no runtime layer.
- **Size:** small
- **Found:** 2026-10-24, while reviewing the Go backend branch

### Compact cards still build their full layout
- **Where:** `qml/components/content/base/Card.qml` (`full`), `qml/components/content/base/Panel.qml` (`column`, `background`)
- **What:** A module's children go into `Card.full` / `Panel.column` (a default property alias), which is only hidden while `compactContent` shows, so a compact card builds its whole layout as well as its figure. On the Tiny page (34 modules in quarter-card slots) this is most of what's left of its build: WifiNetworks about 65 ms, each ClockCalendar about 45 ms (`Built overlay module <Type> in X ms` with `--debug`). It also slows the bar popouts using those panels. A fix is an optional `fullContent: Component` on both roots, loaded only while not compact, then moving the heavy modules to it one by one (their ids are referenced from the module root, so each needs its own pass): see [streamed-building](core/streamed-building.md). The modules review (2026-10-31) found the same in Tailscale, VpnConnections, BluetoothDevices, AudioMixer, Palette, Pomodoro, Focus, Todo, Battery and TopProcesses; Notes always builds both its `tiny` figure and its editor; Disks, SystemGraphs and VolumeDials already skip part of their layout while compact. Parts hidden by mode rather than by compactness are [their own entry](#daypane-builds-its-eventeditor-before-it-opens).
- **Size:** needs a plan
- **Found:** 2026-10-21, while benchmarking the overlay's opening (overlay performance overhaul)

### Nineteen windows stay mapped on one monitor
- **Where:** `qml/components/surfaces/border/RoundedBorders.qml`, `qml/components/surfaces/border/BorderPanel.qml`, `qml/components/surfaces/backdrop/ScreenBackdrop.qml`, `qml/shell/BlurBackingWindow.qml`, `qml/components/hosts/popout/SubmenuHost.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/overlay/OverlayPanel.qml`
- **What:** Each window has its own render thread and GL context (19 `QSGRenderThread`s on one niri monitor). 9 are the border (4 strips, 4 corners, the shadow); the backdrop, blur backing and border shadow are `held` only for niri's map-order stacking. About 25 more (overlay, launcher, a submenu per popout host, edge-popout bodies, power menu, overview, switcher, prompts) keep their context for the session once shown. Options: strips drawing their own corners, windows unloaded a while after they hide, one stacking anchor instead of three held windows ([layer arrangement](compositor/layer-arrangement.md)).
- **Size:** needs a plan
- **Found:** 2026-10-27, while measuring the shell's memory

### Text clips on 1080p screens
- **Where:** `qml/components/views/Layouts/MenuOpening.qml` (the Show on screen / Show other menus buttons)
- **What:** On a 1920×1080 monitor at the default Interface scale, the edge menu editor's two buttons side by side ("Show on screen", "Show other menus", and their Hide labels) don't fit their halves of the inspector and their labels clip. Likely not the only place: much of the UI was laid out on a 1440 px screen, and since the sizing revamp text keeps its size on every monitor while panels and cards follow the screen. Wants a pass over the overlay pages and inspectors at 1080p (`scripts/dev/nested.sh` with a 1080p output), wrapping or stacking what doesn't fit.
- **Size:** needs a plan
- **Found:** 2026-10-21, while checking the sizing revamp on 1080p (overlaySettingsRevamp)

### A popout taller than the screen runs off it
- **Where:** `qml/components/hosts/popout/BarPopouts.qml` (`popoutRoom`), `qml/components/content/Calendar/Calendar.qml`
- **What:** Nothing keeps a bar popout's content within the screen: content taller than the room past the bar (the Calendar popout with its event editor open on a short screen, 1080 px or less with a top bar) draws its box past the screen's far side, and what's there is cut off. `popoutRoom` measures the room left, and only `StyledComboEntry`'s inline list keeps to it. A general guard would hand the content a most height (as `SubPopout.maxContentHeight` does for submenus) for it to scroll within. The tray's own menu (`content/SystemTray`, a `TrayMenuList` with no height cap or Flickable) is another case (popouts audit, 2026-10-30); [A tray submenu longer than the screen runs off it](#a-tray-submenu-longer-than-the-screen-runs-off-it) gives `TrayMenuList` the `maxHeight` this guard could set.
- **Size:** needs a plan
- **Found:** 2026-10-20, while making dropdowns in popouts open inline

### A dropdown in an edge menu card with nothing scrolling gets two rows
- **Where:** `qml/components/reusable/StyledComboEntry.qml` (`_roomBelow`), `qml/components/content/parts/PomodoroDial.qml`
- **What:** In a floating edge menu a `StyledComboEntry` opens inline, capped by the Flickable around it. A card with no Flickable (Pomodoro as a card, its task picker) gets the two-row minimum (`_roomBelow` is 0 with no Flickable and `popoutRoom` null), and the card's rows below it are pushed out of view while it's open. Since PomodoroDial became a DialControls (row 20, features-05) the picker is the card's last row and the ring fills what's left, so there the open list shrinks the ring instead; it still gets two rows. Open question: how much room should such a list take (shrink the parts above it, or more rows over them)?
- **Size:** small
- **Found:** 2026-10-20, while making dropdowns in popouts open inline

### Surfaces touch a dead screen after the outputs go away
- **Where:** `qml/config/General.qml` (`outputs`: whatever is built on it while no monitor is connected)
- **What:** After the monitors drop out (`qt.qpa.wayland` `There are no outputs - creating placeholder screen`, e.g. DPMS off), the log fills with `attempted to use dangling screen object` (68 lines in one session, no file named). Something holds a `ShellScreen` past its removal and reads it. Which surface it is hasn't been found yet: next step, reproduce with a nested compositor dropping its output and bisect by commenting out surfaces in `qml/shell.qml`.
- **Size:** needs a plan
- **Found:** 2026-10-20, while reviewing the popouts system

### Saving a profile that names a new monitor can move other monitors' blocks
- **Where:** `qml/components/methods/WorkspaceGeometry.qml` (`blockBases`), `qml/services/compositor/CompositorManager.qml` (`_bases`), `qml/services/compositor/WorkspaceRemap.qml` (`remap`)
- **What:** Blocks are numbered over the monitors the saved profiles name, sorted by output identity, so saving a profile that names a monitor no profile named before puts it among them: every monitor sorting after it gets a new base, its workspaces sit outside its block, and in the `perMonitor` and `grid` layouts its list and steps miss them (the scrolling layout lists them as borrowed, which compaction leaves) until `axiom ipc workspaces reconcile`. The same happens once on updating to row 13 where the profiles name a monitor that isn't connected. Nothing remaps when `_bases` changes; a remap from the old block order to the new one would (`remapWorkspaces` takes each monitor's `block`, one per layout today). Rare: a per-monitor layout, a newly saved monitor, and its identity sorting before a connected one. Less rare than that (the hyprland review, 2026-10-30): the Monitors inspector's Primary switch (`qml/components/views/Monitors/MonitorInspector.qml:99`, committed at once) is a common trigger, as `WorkspaceGeometry.orderMonitors` puts the primary first.
- **Size:** small
- **Found:** 2026-10-29, while reviewing row 13 (stable workspace blocks)

### A remap runs at startup, from the layout before the config loaded
- **Where:** `qml/services/compositor/WorkspaceRemap.qml` (`_applied`, `_timer`, `onBlockSizeChanged`)
- **What:** Seen 2026-10-30 under Hyprland with a 3×3 grid: the session came up on workspace 10, with `[CompositorManager] remapping workspaces: 0 windows, outputs to DP-1:10` in the debug log. The 10 was the block a `desc:` profile rule gave DP-1 before its description arrived (fixed in row 20's compositor-11), so that symptom is gone, but what restarted the 200 ms timer at the shell's start is still unknown: `begin()` records `_applied` from the config snapshot, which `ConfigManager` reads synchronously, and Qt emits no change signal for a `blockSize`, `perMonitorBlocks` or `workspaceGrid` binding re-evaluated to the same value, so a guard skipping an unchanged layout would catch only a value that changed and changed back within the 200 ms. Either a value really changed after `begin()` (the snapshot differing from the config axiom answers `config.get` with, or a value read before the backend's `supports` settled), and the remap then ran from a layout the workspaces were never in, or something else called `remap`. The log line now carries the `from` and `to` layouts: the next time it shows at a start, they say which value moved. Fix: once that's known, record `_applied` after that value settles.
- **Size:** small
- **Found:** 2026-10-30, while investigating Hyprland starting on workspace 10

### Calendar times in a Windows zone name with no VTIMEZONE read as local time
- **Where:** `backend/internal/calendar/ical/zone.go` (`Zones.With`), `backend/internal/calendar/calendar.go` (`New`'s `Lookup`)
- **What:** A TZID the zone database doesn't know is read only from the object's own VTIMEZONE. The Python helper this replaced (icalendar's `tzp.timezone`) also mapped a Windows zone name (`Pacific Standard Time`, about 140 of them in its `WINDOWS_TO_OLSON` table) and a "globally unique" `/vendor/…/Europe/Berlin` TZID to the IANA zone without one. An event naming such a zone with no VTIMEZONE beside it (rare: Outlook's feeds and invitations carry theirs) now shows at its wall time read as local time, off by the zones' difference. A fix is the CLDR windowsZones table and the prefix strip in `Lookup`; whether the rare case is worth the table is the maintainer's call.

  **Decided** (maintainer, 2026-11-01, on the recommendation "leave it logged"): "agree".
- **Size:** small
- **Found:** 2026-10-27, while reviewing the calendar port (roadmap row 8)

### A bar popout's stroke flashes off its fill switching content on niri
- **Where:** `qml/components/hosts/popout/BarPopouts.qml` (`shownBoxWidth`/`shownBoxHeight`, the box gliding to new content), `qml/shell/BlurBackingWindow.qml` (its fill), `qml/components/hosts/popout/SwitchStill.qml`
- **What:** With blur on under niri, a bar popout switching to another widget's content in the same window shows its old stroke cutting into the box for a frame or two as it resizes: the stroke is the popout's window's, the fill the blur window's, and niri shows the two windows' frames out of step (no `supports.layerFrameSync`). Tried and reverted (2026-10-18), neither changing what the maintainer saw: holding the switch until the popout's window had drawn the new content twice (`SwitchStill`, its window's `frameSwapped`), and drawing the popout's stroke in the blur window with its fill (a stroke-only `AttachedSurfaceCopy` over the fills, the popout's own stroke transparent). That the second didn't help suggests the stroke isn't what's late: perhaps the popout's content, its clip, or the blur region. Next: log each window's `frameSwapped` with what it drew, during a switch.
- **Size:** small
- **Found:** 2026-10-18, while adding niri's blur


### Quickshell's wlr screencopy crashes the shell on niri
- **Where:** `qml/services/apps/ScreenshotManager.qml` (`grimFrames`, the workaround), `qml/components/surfaces/screenshot/ScreenshotPickerWindow.qml` (its `ScreencopyView`); the bug is Quickshell's
- **What:** Without ext-image-copy-capture (niri 26.04 has only wlr-screencopy), Quickshell's wlr screencopy binds a second `wl_output` of its own (`WlrScreencopyContext::OutputTransformQuery`, a `QtWayland::wl_output`; still so in upstream master). niri then sends `wl_surface.enter` for it to every surface; Qt takes it for one of its screens (`QWaylandScreen::fromWlOutput` casts it) and keeps a bogus screen in each surface's list. The next `enter`/`leave` on such a surface crashes in `QWaylandWindow::handleScreensChanged` → `QPlatformScreen::screen()` (at once with a popout open, which unmaps as the picker opens). WAYLAND_DEBUG: `bind(46, "wl_output", 3, …)` beside `zwlr_screencopy_manager_v1.capture_output`, `wl_surface.enter(wl_output#198)` on every surface, then `axiom-edge-popout`'s surface `leave(wl_output#19)` and the crash. Worked around: niri has no `supports.outputCapture`, so the picker's frame is grim's. Left: report it upstream (awaiting a second person to confirm), then drop the workaround once fixed. Sway and Hyprland 0.55 keep `outputCapture` (Hyprland checked by hand: no crash with a popout open).
- **Size:** small
- **Found:** 2026-10-18, while debugging the screenshot crash with a popout open

### A model of size -1 when the overlay grid resizes
- **Where:** `qml/components/hosts/overlay/OverlayPages.qml` (around the `grid` unit change; the model itself not found yet)
- **What:** The log shows `Model size of -1 is less than 0` right after `Overlay card unit 572 for 3376x1231` (the overlay's first sizing on a monitor), five times in one session. Opening the Themes or Settings page again didn't repeat it, so it's likely a Repeater or Grid whose count is worked out from a size that is still 0 or unset at that moment.
- **Size:** small
- **Found:** 2026-10-18, while adding the community setups gallery

### Quickshell's I3 socket warns on every reload
- **Where:** `qml/services/compositor/SwayManager.qml` (Quickshell.I3)
- **What:** Under sway every reload of the shell logs `I3 event socket disconnected` twice (category `quickshell.I3.ipc`); events still arrive afterwards (checked in nested sway). Both come from Quickshell 0.3.2's `I3IpcListener` deleting its own connected socket, which its `stateChanged` handler reports as a disconnect: once when the old generation's listener is destroyed, once when the new one, already connected by setting `subscriptions` at creation, starts over in its `onPostReload` (so a cold start logs it once too). Axiom can't avoid it: any teardown of a connected listener logs it, and `I3.rawEvent` (the process-wide connection, which survives reloads) subscribes only to `workspace` and `output`. Nor is a log rule honest: the category also carries real faults, and sway drops an IPC client whose buffer fills, which Quickshell never reconnects, so this warning is then the only sign the event stream is dead. The fix is upstream: `I3Ipc` disconnecting its socket's signals before deleting it, and `I3IpcListener` not restarting with unchanged subscriptions.
- **Size:** trivial
- **Found:** 2026-10-16, while writing the sway backend

### niri reports no position for a tiled window, nor other apps' layers
- **Where:** `qml/components/methods/NiriState.qml` (`windows`, `outputs`)
- **What:** niri's IPC gives no layer surface geometry, so an output's `reserved` counts only axiom's own layers (`LayerArrange.arrange`): another app's bar on niri isn't in it, and the dock centres as if it weren't there. Nor, in 26.04, does it give a position for a tiled window (`tile_pos_in_workspace_view` is null; only floating windows have one; checked 2026-10-28). So tiled windows are laid out from their column and place in it from the output's edge, without niri's scroll (`windowGeometry` stays off: no screenshot window mode; the dock hides behind a window's `cover`, its column or the whole output, which ignores struts, reserved space and `center-focused-column`).
- **Size:** small
- **Found:** 2026-10-17, while adding the niri backend

### A side edge's submenus always open away from the edge
- **Where:** `qml/components/hosts/popout/SubmenuSide.qml` (`openToLeft`)
- **What:** On a left or right edge a submenu always opens away from that edge (`openToLeft` is `edge === ScreenEdge.Right`), so a floating menu on the right edge opens every submenu to its left, across the menu's own content side. The maintainer finds that unexpected for a right-edge menu: which way it should open there (and whether by the box's place on screen, as top and bottom edges do) needs deciding. Seen with a `Submenu` module in a right-edge floating menu in nested niri.

  **Decided** (maintainer, 2026-11-01, on a) toward the edge, b) away as now, c) by the box's place on screen; recommended c): "defer - This takes quite a bit of thought to make consistent without an option."
- **Size:** small
- **Found:** 2026-10-18, while checking shadow seams on side-edge menus

### A pill bar's end reach trails a sliding popout's wall
- **Where:** `qml/components/hosts/popout/PillBarJoin.qml`, `qml/components/hosts/popout/EdgePlacement.qml` (`_slideLead`), `qml/components/bar/BarContainer.qml` (`_endReach`)
- **What:** Seen on niri with a solid bottom bar (border off) whose SystemStats popout joins the left pill bar: while the popout slides in or out, the left bar's end pill, run on to the popout's top wall, trails it by about 8px for two or three frames (below the wall while opening, above it while closing), so the two strokes and their shadows step at the left bar's inner edge. At rest they line up. Probably the other bar's window committing a frame or so after the popout's (as `AttachedSurface`'s fillet opening is taken a stroke ahead for). The end pill leads the wall by a stroke there (niri has no `supports.layerFrameSync`, `EdgePlacement._slideLead`), which helps but doesn't close the gap; sway and Hyprland move the two as one without it.

  **Decided** (maintainer, 2026-11-01, on the recommendation "defer"): "defer".
- **Size:** small
- **Found:** 2026-10-18, while fixing shadow seams where a wall runs on into another surface

### Readers read files through a service
- **Where:** `qml/config/Paths.qml` (`packagedVersion`), `qml/config/I18n.qml`
- **What:** Readers read only the data owners and each other (AGENTS.md › Layering), but `Paths.packagedVersion` calls `FileManager.read`, and `I18n` reads with both `FileManager.read` and a FileView of its own. Either the rule names `FileManager` as allowed in readers, or the reads move to a data owner.
- **Size:** small
- **Found:** 2026-10-26, while reviewing the repository's organization

### Setting names that still confuse
- **Where:** `qml/config/schema/sections/`
- **What:** From the maintainer's notes: "still confusing option names in settings" (after the look-and-feel renames). The plan lists the settings whose titles or keys read wrong, with a proposed name for each, for the maintainer to decide; a renamed key is a migration step.
- **Size:** needs a plan
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The Monitors page's off and mirroring buttons throw when one leaves the list
- **Where:** `qml/components/views/Monitors/MonitorCanvas.qml` (the `others` Repeater)
- **What:** The Repeater's model is `root.others.length`, and each delegate reads `root.others[index]`: when the list shrinks (Reset, or a hotplug re-detect, after a monitor was turned off in the draft) the delegates about to go re-evaluate first with `rule` undefined, logging `TypeError: Cannot read property 'output' of undefined` and `Cannot read property 'disabled' of undefined` from `MonitorCanvas.qml` (seen in a nested Hyprland, 2026-11-04). Harmless beyond the log; the model could be the list itself, or the reads guarded.
- **Size:** trivial
- **Found:** 2026-11-04, while testing the trial Apply (compositor-10)

### The monitor editor shows changes nobody made
- **Where:** `qml/services/compositor/MonitorManager.qml` (`draft`, `ensureLoaded`), `qml/components/views/Monitors/Monitors.qml`
- **What:** From the maintainer's notes: the monitors page shows unsaved changes when nothing was changed (likely a value the draft normalises on load differing from the saved one).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Typing in modules on the overlay and the desktop
- **Where:** `qml/components/hosts/overlay/OverlayPanel.qml` (`keyboardFocus`), `qml/components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`, `wantsKeyboard`)
- **What:** From the maintainer's notes: modules that take typing can't be used while they're on the overlay, and a click outside a desktop module stops its typing.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Modules inside borders aren't sized evenly
- **Where:** `qml/components/content/base/Card.qml`, `qml/components/content/ColorSwatch/ColorSwatch.qml`, `qml/components/content/KeyboardLayout/KeyboardLayout.qml`, `qml/components/content/Greeting/Greeting.qml`, `qml/components/content/Session/Session.qml`
- **What:** From the maintainer's notes: module sizing within borders isn't even (the space around modules framed by a border differs from side to side or between modules). Of the two likely causes the overlay review saw (2026-10-31), the first, slots and `Card`'s border on fractional pixels under `contentZoom`, was shown in a nested niri (page scaled 0.697: module borders smeared over two pixels at uneven strengths, crisp and even at zoom 1) and fixed in row 20 (`GridPlacement.rectPx` on whole drawn px, `OverlayGrid.drawnZoom`). The second is left: `Card` doesn't pad its content (`full` fills the box), while `Panel`'s column takes `pad`, so each `Card` module applies `pad` itself: ColorSwatch not at all, KeyboardLayout width only, Greeting `anchors.margins`, Session its own `margin` (0 when tight). PLAUSIBLE: not shown as uneven on screen (the swatch fills its box and KeyboardLayout centres its row by design), and padding every `Card` module changes how 25 modules look, a maintainer's call.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The keybinds page on a small monitor with large binds
- **Where:** `qml/components/views/Keybinds/BindListRow.qml`, `qml/components/views/Keybinds/BindSection.qml`
- **What:** From the maintainer's notes: the keybinds page needs checking on a small monitor with long binds (combos and commands): rows that don't fit. Take it with the 1080p pass of [Text clips on 1080p screens](#text-clips-on-1080p-screens).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Shift+Enter on an emoji doesn't type it on niri
- **Where:** `qml/components/surfaces/launcher/LauncherPanel.qml` (`activate`), `qml/services/apps/EmojiManager.qml` (`type`)
- **What:** From the maintainer's notes: under niri, Shift+Enter on an emoji in the launcher doesn't type it into the focused window (typing goes through `input.type` on the daemon's virtual keyboard). Not reproduced (2026-10-28): in a nested niri on the live binary, `axiom launcher search ";grinning"` then Shift+Enter typed it into foot, kitty and a GTK entry every time, with fcitx5 and mozc running too; the live logs show no typing error, and the last emoji uses predate typing moving to the daemon. Untested: a physical Shift+Enter, Electron or Xwayland windows, the live focus-follows-mouse. Waits for the maintainer: which app, and does it still fail.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### A window takes the keyboard from a desktop module on niri
- **Where:** `qml/components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`), `qml/services/ui/DesktopManager.qml`
- **What:** From the maintainer's notes: under niri, as soon as the mouse leaves a desktop module that takes typing, the window under the pointer takes the keyboard focus (niri's focus follows the mouse onto it), so typing in the module stops. How to hold the focus there is still open ("idk how to handle this").
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Hyprland's default workspace doesn't highlight its first window
- **Where:** `qml/components/bar/widgets/Workspaces/StripWindows.qml` (`focused`), `qml/services/compositor/HyprlandManager.qml`
- **What:** From the maintainer's notes: on the workspace Hyprland starts on, the first window opened isn't highlighted as focused until a workspace move. Checked 2026-10-29 (code read, nested Hyprland): Hyprland's own data is right (the first window on workspace 1 has `focusHistoryID` 0 and is `activewindow`), and `StripWindows` highlights `CompositorManager.lastFocused` of the workspace's windows, which for one window is always it; so the cause isn't in either. Which highlight it is (bar strip, dock `DockManager.focusedId`, overview `WindowPreview.focused`) and under which layout (`StripWindows` shows only under scrolling, whose workspace ids `DynamicWorkspaces` renumbers until `_compaction` runs) needs the maintainer to reproduce it.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### A greeter-only module validates on any page
- **Where:** `qml/components/content/Session/schema.yaml` (`hosts`), `qml/components/content/Login/schema.yaml`, `qml/components/content/Password/schema.yaml`
- **What:** `hosts: {only: [greeter]}` keeps Session out of the layouts editor's library elsewhere, but the built schema still lists it in every host's `oneOf`: a config with Session in an edge menu and on an overlay page passed `axiom config validate`, and it drew as a bare "Session" field on an empty card. So an import, a community setup or a hand edit can put a greeter- or lock-only module (Session, Login, Password) where it can't work.
- **Size:** small
- **Found:** 2026-10-29, while building the revamped example setups

### TestDiscoverCalDAV failed once under verify.sh --all
- **Where:** `backend/internal/calendar/calendar_test.go` (`TestDiscoverCalDAV`)
- **What:** One `verify.sh --all` run failed `TestDiscoverCalDAV/from_the_server's_root,_redirected` with `got {Calendars:[]}`, while the other parallel subtests passed. That message didn't print the error, but there was one: traced, `discoverCalDAV` returns no calendars without an error only when its last candidate, `/.well-known/caldav`, answers, and `davServer` 404s it. Ruled out (row 20): the shared account id `acc` (only a read-only `Secrets.Lookup` of a file no test writes); `CloseIdleConnections` on the shared `http.DefaultTransport` (the weather flake's cause), hammered beside the test for about 20 000 runs, never broke a request. Not reproduced in about 15 000 runs of the package under load (`-race`, `-cpu 1,2,4,8`). The test now prints the error: read it the next time it fails before changing anything.
- **Size:** small
- **Found:** 2026-11-05, while running verify.sh --all for row 20 (bar-popouts-06)

### TestLogindLockAndSleep failed once under verify.sh
- **Where:** `backend/internal/idle/idle_test.go` (`TestLogindLockAndSleep`)
- **What:** One `scripts/dev/verify.sh` run failed it at its first `h.rec.expect(t, "lock")` with `actions [], want [lock]`: nothing was recorded within the 3 s bound after `h.logind.Lock()`, though `until(s.Logind)` had passed. Three `go test -count=1 ./internal/idle/` runs right after and a second verify.sh run passed. PLAUSIBLE: the service reports `Logind` before its `Lock` signal match is in place, so a Lock sent at once is missed; settle by running the package under load (`-race`, `-cpu 1,2,4,8`, `-count` in the hundreds) and checking when the match is added against when `Logind` turns true.
- **Size:** small
- **Found:** 2026-11-05, while reviewing the settings chunk of the tweaks-minor-complaints branch

### The guard judges a push where the line starts, not where git runs
- **Where:** `.claude/hooks/guard.py` (`check_git`, `simple`), `tests/scripts/test_guard.py`
- **What:** `check_git` reads the branch once, in the folder the line starts in (or `git -C`'s), before anything in the line runs, so a push to main gets past it when git runs on another branch or folder than that: `git switch main && git push` (or `git checkout main`) from a feature branch's folder; a wrapper that changes folder (`env -C <main checkout> git push`, `sudo -D`, `systemd-run --working-directory`, whose options `simple` drops); `git --git-dir=…`/`--work-tree=…` or `GIT_DIR=… git push`. Each was allowed by `guard.check` from a folder on a feature branch (2026-11-02). Fix: refuse a bare push (no refspec, or `HEAD`) after a `switch`/`checkout` in the same line, and judge the folder those options and variables name.
- **Size:** small
- **Found:** 2026-11-02, while reviewing the guard's leading `cd` (row 20, config-05)

### Opening a hover-closing edge menu by IPC closes it at once
- **Where:** `qml/services/ui/EdgeMenuManager.qml` (the `edgeMenu` `IpcTarget`'s `open`), `qml/components/surfaces/edgemenu/EdgeMenuSync.qml` (`autoDismiss`)
- **What:** `axiom edge-menu open <id>` on a menu with `close.onLeave` (the default) shows it for one close delay and closes it, since the pointer isn't in it: the IPC `open` calls `open`, not `reveal`, so it's never `revealing`. `pin` on a closed menu doesn't open it either; only `pin` then `open` keeps it up. A bind or script can't open such a menu.
- **Size:** small
- **Found:** 2026-10-29, while building the revamped example setups

### The window switcher reads a removed screen's name
- **Where:** `qml/shell/WindowSwitcher.qml` (`claimKey`)
- **What:** Unplugging a monitor logs `TypeError: Cannot read property 'name' of null` from `@shell/WindowSwitcher.qml[79:-1]` (`claimKey: "switcher:" + screenScope.modelData.name`): the Variants delegate's screen is gone before the delegate is (seen in a nested Hyprland, removing a headless output). Fix: `screenScope.modelData?.name ?? ""`, or read the name once.
- **Size:** trivial
- **Found:** 2026-11-05, while keeping the bar across a hotplug (bar-popouts-04)

### Bluetooth pairing that asks for a PIN or a passkey
- **Where:** `qml/services/system/BluetoothManager.qml` (`_connectAfterPair`), `qml/components/content/BluetoothDevices/`
- **What:** Pairing trusts, pairs and connects, but no pairing agent asks the user to confirm a passkey or type a PIN, so a keyboard or phone needing one may not pair unless another agent runs. Not tested on such a device. Also open: whether Quickshell's Bluetooth registers an agent, or the daemon does, and the prompt's surface.
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### No keyboard backlight control
- **Where:** `qml/services/system/BrightnessManager.qml`
- **What:** Laptops' keyboard backlights (`kbd_backlight` LEDs) have no slider, OSD bar or keys: nothing in services reads them. Also open: whether `BrightnessManager` takes them as another device, the OSD bar kind, and writing the LED through the daemon.
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### The border's stroke row is left unfilled where two pill bars meet at its corner, unbacked
- **Where:** `qml/components/bar/BarContainer.qml` (`borderOpening`, `joinOpening`), `qml/components/surfaces/border/RoundedBorders.qml`
- **What:** The border leaves its inner stroke open under a joined surface whenever `Appearance.translucent`, not only while the blur window backs it. In nested niri with a top and a left pill bar meeting at the top-left corner (translucency 80%, the look's blur off, so nothing is backed), the top frame's stroke row (y = 7) is bare wallpaper across the left frame's width (x 0–6): nothing fills it there, as the keepFill row was before compositor-20. Backed, the blur window fills it. Which opening takes that stretch (the left pill's `joinOpening` or the top pill's `borderOpening`) wasn't traced.
- **Size:** small
- **Found:** 2026-11-04, while fixing a keepFill opening's unfilled row (compositor-20)

### On Hyprland a click back in an older popout closes it with the newer one
- **Where:** `qml/services/compositor/FocusGrab.qml` (`dismissed`, `_outside`), `qml/services/ui/BackdropManager.qml` (`clickedOutside`)
- **What:** Hyprland has one native grab at a time, and its `cleared` doesn't say where the click landed. So while a newer keyboard popout (Todo, Calculator) holds the native grab over an older edge or floating popout (the launcher, a floating edge menu), a click back inside the older one clears the newer grab, which sends `BackdropManager.clickedOutside(null, null)`, and the older one is dismissed and closes too. Rare: hover popouts close once the pointer leaves them, so the pointer reaches the older popout only after the newer grab ended with no click, except where the two overlap or the newer one is held open. Accepted as is by the leader (bar-popouts-02, round 4); fixing it needs the click's position (a backdrop that takes clicks on Hyprland too).
- **Size:** small
- **Found:** 2026-11-01, while reviewing bar-popouts-02 (edge and floating popouts closing on an outside click)

### A tray submenu longer than the screen runs off it
- **Where:** `qml/components/content/parts/TraySubmenu.qml:14` (`implicitHeight`), `qml/components/content/parts/TrayMenuList.qml:29` (`implicitHeight`), `qml/components/hosts/popout/SubPopout.qml:133` (`maxContentHeight`)
- **What:** SubPopout gives submenu content the room it has (`maxContentHeight`, from `screenFrom`/`screenTo`), and submenus.md says "content that may be taller … scrolls past `maxContentHeight`". Only `Submenu/MenuSubmenu.qml:46` reads it. `TraySubmenu`'s height is `menuList.implicitHeight`, and `TrayMenuList` is a bare ColumnLayout with no Flickable. So a tray submenu with more entries than fit (about 25 or more on a 1080 px screen) is as tall as all its entries. `SurfaceContext.submenuPlace` clamps only its start, so the box runs past the screen's bottom and the last entries can't be reached. Fix: `TrayMenuList` takes a `maxHeight` (unbounded by default) and wraps `menuLayout` in a Flickable as MenuSubmenu does; TraySubmenu passes `root.wrapper.maxContentHeight`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### Eight modules' full layouts need more room than their fullMin sizes, even inside the padding
- **Where:** `qml/components/content/Palette/Palette.qml:17` (`columns`), `qml/components/content/Pomodoro/Pomodoro.qml:20` (`fullMinHeight`), `qml/components/content/Focus/Focus.qml:30` (`fullMinHeight`), `qml/components/content/Disks/Disks.qml:25` (`columns`), `qml/components/content/Tailscale/Tailscale.qml:54` (`fullMinHeight`), `qml/components/content/WifiNetworks/WifiNetworks.qml:75` (`fullMinHeight`), `qml/components/content/Updates/Updates.qml:44` (`fullMinHeight`), `qml/components/content/NowPlaying/NowPlaying.qml:32` (`short`, `mini`)
- **What:** Contract (writing-modules.md): a module sets `fullMinWidth` / `fullMinHeight`, "the px its full layout needs inside its padding". These don't cover it. All figures are inner px at font 14, normal density.
  - **Palette** picks 2, 4 or 8 columns from width alone. `fullMinHeight` 12f (168 px) covers only 8 columns. 4 columns need about 266 px and 2 about 502 px (16 chips of about 57 px each with one role line). The default `[8, 4]` on a card under about 300 px tall cuts the bottom rows. Fix: choose the columns from both axes, and set the minimum from the chip count.
  - **Pomodoro**: the dial is at least 4f (56 px) plus 86.8 px of dots, play button and task picker, so it needs 142.8 px. `fullMinHeight` is 9f (126 px). Fix: about 13f, or derive the dial's reserve and the minimum from one `controlsHeight`.
  - **Focus**, stacked (under 34f wide): timer row 84 + separators 9 + todo field 30 + 4 + `DayPane`'s `Layout.minimumHeight` 8f (112) = 239 px, with no todo row showing. `fullMinHeight` is 14f (196 px).
  - **Disks**: a second column needs `innerWidth >= 12f`, but a disk lays out down to 7f. Two paths in a 4x1 strip at a 60 px unit (204×24 inside) stack 65 px into 24 px rather than going side by side. Its `fullMinHeight` 3f (42 px) is also under one disk (29.6 px) plus the pad.
  - **Tailscale**, connected with `actions` on (default): header 28 + this machine 47 + three folds 84 + separator + gaps 60 is about 220 px before one peer row. `fullMinHeight` is 11f (154 px), and a 4×2 card at 1080p (179 px inside) gives the device list 0 px. Fix: drop the folds in a short card (S4), or raise the minimum.
  - **WifiNetworks**: `fullMinHeight` 12f leaves about 23 px for the list (one row is 37 px). With VPNs, the controls alone need 146 px.
  - **Updates**: by its own `maxRows` terms, one section needs about 109 px and two need 180 px. `fullMinHeight` is 6f (84 px), and `Math.max(1, …)` forces one row. A 4x2 at a 50 px unit with AUR updates cuts off the AUR section entirely, with nothing to show it exists. Fix: derive `fullMinHeight` from the same terms.
  - **NowPlaying**: only the side-by-side layout sheds parts (`short` requires `sideBySide`). Stacked needs about 152 px but is used from `mini`'s 7f (98 px). Side by side and short needs about 86 px, so the schema's own `defaultSize: [4, 2]` at a 50 px unit (64 px inside) is about 22 px short. The strip at `fullMinHeight` 3.5f has 13 px for a 17 px title. Fix: let `short` apply when stacked too, raise `mini` to about 9f, and set the strip's minimum to its title line.

  These are arithmetic from the code, not screenshots. PLAUSIBLE in the exact px (font metrics vary), but each is more than 20 px over; re-measure in a nested shell at the sizes named.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### DayPane builds its EventEditor before it opens
- **Where:** `qml/components/content/parts/calendar/DayPane.qml:70` (`EventEditor`)
- **What:** qml/components/content/AGENTS.md: "a part shown in one mode only is a Loader gated on it, not `visible: false`". DayPane (the Calendar popout and module, the Clock & calendar module, the Calendar page) builds an `EventEditor` that shows only after a click. Agenda's is built on demand (row 20), and the other nine modules and parts first listed with it were fixed in row 20 (overlay-modules-04). DayPane's is left because the Calendar popout's `maxImplicitHeight` reads `DayPane.growth`, the editor's height before it opens, to make room up front (a shown popout that grows flashes); its height can't be stated without building it, since the repeat buttons' `Flow` wraps by width and translation. Fix: a Loader active while editing or while a host reads `growth` (only the Calendar popout, `!root.embedded`), with `open()` going through `session` as Agenda's does.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### The popout docs give AudioMixer's list two rows at least
- **Where:** `docs/dev/popouts/hosts-and-switching.md` (Which do), `qml/components/content/AudioMixer/AudioMixer.qml:49` (`rowsHeight`)
- **What:** hosts-and-switching lists "AudioMixer (2 to 4 rows)", but the popout's list is `Math.max(root.rowsHeight(1), Math.min(list.implicitHeight, root.listHeight))`: one row (also when empty) to four, as the file's own comment says. Fix: "1 to 4 rows" in the doc.
- **Size:** trivial
- **Found:** 2026-11-05, while reviewing row 20's overlay-modules-04 (AudioMixer and WorldClocks build only what their mode shows)

### A stale exec-if check can block a widget after its exec-if changed
- **Where:** `qml/services/apps/CustomWidgetsManager.qml:163` (`_checkIf`)
- **What:** The check's callback only asks whether the id is still watched (`if (!(id in root._watching))`), not whether its `execIf` is still the one checked. Editing Run only if on the page re-checks on every keystroke (`_wanted` changes, `_sync` calls `_checkIf`), and clearing it watches at once (`_watch`). A check that ends after a newer one, e.g. typing `ping -c1 -W1 myhost` (the partial `ping -c1 -W1 myh` waits its second to fail while the full one answers in milliseconds), sets `_blocked`, releases the watch the newer check started and shows `"ping -c1 -W1 myh" failed` until the next refresh. PLAUSIBLE: the order the checks end in; a slow failing prefix settles it. Fix: `if (root._watching[id]?.execIf !== def.execIf) return;` in place of the `in` check (`_watching` holds each id's `execIf`).
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### An integrated top or bottom menu's zone follows its growing modules
- **Where:** `qml/components/surfaces/edgemenu/IntegratedEdgeMenu.qml:49` (`depth`), `qml/components/surfaces/edgemenu/IntegratedEdgeMenu.qml:135` (`exclusiveZone`), `qml/components/surfaces/edgemenu/EdgeMenuBody.qml` (`maxGrownHeight`)
- **What:** hosts.md says of an integrated menu: "The zone is set once while it's open (windows retile in one step)". But `depth` is `Math.ceil(root.bodyDepth + root.pad * 2 + root.innerStroke)`, with `bodyDepth` the body's live `implicitHeight` on a top or bottom edge: `ModuleGrid.sizes.height`, from the grown places (`ModuleGrid.places`). `exclusiveZone` and the window's `implicitHeight` follow it. So a top menu holding a module with `grow` (Notifications, AudioMixer, WifiNetworks, …: nine modules have it) changes its exclusive zone each time that module grows or shrinks, e.g. when a notification arrives: the windows retile again, and the shown layer window grows (the squeezed flash growing popout windows show). FloatingEdgeMenu avoids this by reserving the most up front (`maxContentDepth: root._body.maxGrownHeight`). Proposed fix (not decided): reserve `maxGrownHeight` on a top or bottom integrated menu, so the zone is set once.

  **On hold** (maintainer, 2026-10-31): "put this on hold - note that growing modules kinda needs a re-work or removal". Growing modules as a whole (`grow`, [grow-expand](overlay/grow-expand.md)) need a rework or removal; this entry waits for that and is [deferred](roadmap.md#deferred). No design is recorded.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

### DockWindow logs a binding loop on _wouldShow
- **Where:** `qml/components/surfaces/dock/DockWindow.qml:270` (`_wouldShow`), `qml/components/surfaces/dock/DockWindow.qml:318` (`conceal`), `qml/components/hosts/popout/PopoutClaim.qml` (`_sync`), `qml/services/ui/PopoutManager.qml` (`_refuse`), `qml/shell/Dock.qml` (the DockWindow the log names)
- **What:** The live shell logged `Binding loop detected for property "_wouldShow"` (`@shell/Dock.qml[35:19]`) after a reload on 2026-11-02. main's code has the loop (none of these files differ on the maintainer's branch): when `_wouldShow` turns true (the dock latches) while a popout covers its spot, the claim's `wanted:` binding (line 247) makes `PopoutClaim._sync` call `PopoutManager.claim`, which refuses a resident synchronously (`_refuse` puts it `yielded`); `away` turns true and `onAwayChanged` runs `conceal()`, setting `latched = false` while `_wouldShow`'s binding is still writing its value. The dock ends hidden, as wanted, but with the warning. Fix: drop the latch a turn later (`Qt.callLater` in `onAwayChanged`), or have `conceal` skip `latched` when `away` already hides it.
- **Size:** small
- **Found:** 2026-11-02, while clearing out the launcher's issues (platform-07)


### A device's own level arriving late brings the OSD's bars out beside its card
- **Where:** `qml/components/surfaces/osd/PipewireVolumeBar.qml` (`_systemChanged`), `qml/components/surfaces/osd/OSDBar.qml` (`_levelChanged`), `qml/components/surfaces/osd/OSDContent.qml` (the bars' `onPoked`, `_openBox`), `qml/components/methods/OSDItems.qml` (`replaces`)
- **What:** The System volume and Microphone bars count a level or mute change only while `AudioManager.sinkSettled()` / `sourceSettled()` holds, which turns true a moment after the new default node is ready. `OSDItems.replaces` already allows that a new device's mute may come after that ("a mute just after a device switch is the new device's own state coming in"), and PipeWire sends a node's volumes and mute in the same params. So when a headset connects, its own volume landing after the settle pokes the bar, and the bars' `onPoked` opens the bars part (`_openBox`) with no `replaces` check: the bars come out beside the device card, a change the user didn't make. PLAUSIBLE: a log of `defaultSink.ready` against `AudioManager.volume` changes on a headset connect settles it (the roadmap's Live checks already asks whether plugging in a headset opens the bars). Fix, if it shows: run the System volume and Microphone bars' pokes through `replaces` as the `audio` / `microphone` statuses' mutes (an `OSDItems` rule mapping a bar type to its status, a test row), which also holds back the user's own volume key in the 2 s after a switch: a trade-off for the maintainer.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the OSD's statuses

### The dock's menu and drag state outlive the icons they point at
- **Where:** `qml/components/surfaces/dock/DockWindow.qml:216` (`dragIndex`), `qml/components/surfaces/dock/DockWindow.qml:357` (`menuIndex`), `qml/components/surfaces/dock/DockWindow.qml:574` (`anchorItem`), `qml/components/surfaces/dock/DockItem.qml:100` (the hover Timer)
- **What:** The menu is held as `menuKey`/`menuFull` and anchored on `repeater.itemAt(root.menuIndex)`; a drag as `dragIndex`. Both are cleared only by the icon or the menu itself (`closeMenu()` from DockItem's press, click and drag start, DockMenu's FocusGrab `onCleared`, `conceal()`; `dragIndex = -1` only in DockItem's `_endDrag`). Two paths leave them set:
  - (1) The app goes while its full menu is open: an unpinned app's last window closes by itself (an app quitting, a dialog finishing). `menuIndex` becomes -1, `anchorItem` null, the menu hides, and its FocusGrab (`active: root.visible && root.full`) goes inactive without `cleared`. `menuFull` stays true, so DockItem's hover Timer (`running: … && !root.dockWindow.menuFull && …`) never opens an app's name and windows again; a press doesn't clear it either (`if (!root.dockWindow.menuFull) closeMenu()`). Only a left click or drag on an icon, or the dock being put away, ends it; if the app comes back, its full menu pops open again unasked.
  - (2) Any app appears or goes while a menu is open or an icon is carried: `model: root.keys` is a new JS array, and the Repeater rebuilds every DockItem (the comment at line 84: "they only rebuild when the set of apps changes"). The menu's anchor is destroyed; `anchorItem` isn't re-read when `menuIndex` keeps its value (a pinned app's index doesn't move when a running app is added), so the menu hides with `menuKey` still set (the hover Timer's `menuKey !== root.key` keeps that icon's names shut). A carried icon's delegate is destroyed with its press, so no drop or cancel reaches `_endDrag`: `dragIndex` stays ≥ 0, `engaged` stays true, and a hover or intellihide dock never hides again, magnification stays off and the icon now at that index draws without its indicator. PLAUSIBLE for (2): settle in a nested session (hover a pinned icon until its menu shows, open a window of an app not on the dock by a bind; the menu goes and doesn't come back on that icon) and the same while carrying an icon.
  Fix: clear both whenever the set of apps changes, in DockWindow: `onKeysChanged: { root.closeMenu(); root.dragIndex = -1; }` (4 lines; a hover menu reopens after its 450 ms rest). Keeping the menu across a change instead means anchoring it by key (`menuKey`) on the rebuilt delegate.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:dock system

### A dock beside another edge's reserving dock is laid out as if that dock weren't there
- **Where:** `qml/components/surfaces/dock/DockWindow.qml:467` (`margins`), `qml/components/surfaces/dock/DockWindow.qml:102` (`length`), `qml/components/hosts/popout/EdgePlacement.qml:161` (`innerStart`)
- **What:** A dock window is a Normal-exclusion layer anchored to both ends of its edge, so the compositor starts it past every exclusive zone at those ends, another dock's included (an always-shown, reserving left dock for a bottom dock). Its layout along the edge doesn't: `length` is `placement.innerEnd - placement.innerStart`, and EdgePlacement's inner sides are `ScreenEdgeManager.reservedWithMenusOn` (bars and integrated menus, no docks). Its margins along the edge are only `-root.startStrokeInset` / `-root.endStrokeInset`. EdgePopout, under the same compositor rule, reaches past docks there (`-root.startStrokeInset - DockManager.zoneOn(surfaceWindow.screenName, "left")`, EdgePopout.qml:414–415; comment "Docks reserving space inside the border don't push it in: it reaches past them, on its own edge and at both ends"). So with a reserving left dock of zone Z, the bottom dock's box is drawn Z px right of where `centre`/`insetStart`/`insetEnd` put it in a window Z px shorter than `length`: at `position` 100, or a dock as long as the edge, its far end runs Z px past the window and is cut off, and an attached dock's start end is worked out as joining the border's left stroke while it actually sits past the left dock. The trigger and intellihide rect (`DockManager.reservedOf`, the compositor's reserved) follow the shifted box, not the computed one. Which dock is pushed depends on the compositor's order when both reserve. PLAUSIBLE: settle in a nested session with a left reserving dock and a bottom dock at position 100. Open product question: should a dock keep clear of another edge's dock at its ends (subtract those zones from its inner sides, the box beside it) or reach past it as edge popouts do (the margins above, the box may meet the corner under it)?
  Fix: make the layout and the window agree: reaching past, subtract `DockManager.zoneOn(<screen>, <end side>)` in the along-edge margins as EdgePopout does (2 lines, the dock's own edge excluded).

  **Decided** (maintainer, 2026-11-01, on the recommendation "b) reach past it as edge popouts do"): "agree".
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:dock system

### A pomodoro, timer or caffeine end due during a suspend fires up to an hour after waking
- **Where:** `qml/services/apps/DeadlineTicker.qml:133` (`_arm`), `qml/services/apps/DeadlineTicker.qml:159` (`_armWarning`)
- **What:** `_arm` sets a single-shot Timer to `Math.min(left + 50, 3600000)` and only looks at `Date.now()` again when it fires. Qt's timers run on the monotonic clock, which stops while the machine sleeps. Start a 25-minute pomodoro, suspend after 5 minutes, wake an hour later: the alarm still has 20 minutes to run, so for 20 minutes the dial and bar widget read `00:00` while still running, and when it finally fires the end is over 5 minutes late, so `_end(late)` advances silently with no notification. The same holds for the one-off timer (StopwatchManager) and caffeine's timer (IdleManager), and for the warning alarm. Nothing in the shell listens for wake (the daemon's logind watcher sees `PrepareForSleep`, but no shell code reacts to it). PLAUSIBLE: settle by suspending with a 2-minute timer for 5 minutes and watching when it ends. Fix: cap both alarms at a minute instead of an hour (`Math.min(left + 50, 60000)`), bounding the lateness to a minute at the cost of one wake-up a minute while a deadline runs; update the doc's "at most an hour at a time".
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:todo-pomodoro system

### An image sent without text to Anthropic carries a whitespace-only text block
- **Where:** `backend/internal/chat/send.go:284` (`anthropicRequest`)
- **What:** `send` allows a message with attachments and no text, and `anthropicRequest` always appends `{"type": "text", "text": orSpace(t.text())}`, so an image-only message sends the text `" "`. The Messages API rejects whitespace-only text blocks ("text content blocks must contain non-whitespace text"), so the reply fails as `bad_reply` where OpenAI-style and Gemini requests (which skip the text when there are images) succeed. PLAUSIBLE: one Anthropic request with an image and empty text settles it (not made: paid API). The shape came over unchanged from the old ChatProtocol. Fix: append the text block only when the text is non-empty or there's no image (`if text := t.text(); text != "" || len(content) == 0 { … orSpace(text) … }`), plus a TestBuild row with an image-only user turn.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the chat system

### Stop is ignored while chat.send still looks up the key
- **Where:** `backend/internal/chat/send.go:87` (`Send`), `backend/internal/chat/send.go:160` (`Stop`)
- **What:** `Send` looks the key up (`keyFor`: the environment, then `secret-tool lookup`, then secrets.json) before it registers its cancel in `s.running` (line 94), and `Stop` does nothing for an id not there. A Stop pressed during the lookup (a locked keyring's unlock prompt, a slow Secret Service) is lost: the request goes out afterwards and streams to the end while the shell shows it as stopping; the same for `newConversation`'s stop. PLAUSIBLE that users meet it: it needs a lookup slow enough to press Stop in. Fix: register the cancel first and do the lookup under the cancellable ctx (move `ctx, cancel := context.WithCancelCause(ctx)` and the registration above `keyFor`, and answer `Stopped` when `stopped()` after it), plus a TestStop case stopping before the lookup returns.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the chat system

### A folder name holding `#` or `?` opens the wrong folder in the note list
- **Where:** `qml/components/content/parts/notes/NoteBrowser.qml:87` (`folderModel`)
- **What:** The browser's `FolderListModel` is given `"file://" + NotesManager.absolute(…)` unencoded, so a `#` starts the URL's fragment and a `?` its query. Folder names come from the user (`createFolder` keeps both characters). Checked with qmltestrunner: a model given `file:///…/d/C#/` listed the contents of `d/C` (`names= ["x"]`), not `d/C#`. So opening a folder "C#" (or "Q&A?") shows another folder's notes, or nothing, under a breadcrumb saying "C#", and a notes folder set to such a path lists nothing at all; a `%20` in a name is read as a space. CONFIRMED. The wallpaper list isn't affected any more (WallpaperManager lists through `file.list` and escapes `%`, `#` and `?` in its image URLs). Encoding the URL doesn't fix it (checked with qmltestrunner on Qt 6.12, 2026-11-05): FolderListModel turns its folder into a local path and parses that as a URL again, so `file:///…/d/C%23/` still lists `d/C`; `C%2523` lists `C#`, but a `?` (`Q%253F`) or a literal `%xx` in a name can't be reached either way. Fix (a maintainer's call): escape twice for FolderListModel, which covers `#` and leans on Qt's double parse, or list the folder through the daemon (`file.list` with folders, plus a watch) instead of FolderListModel.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:notes system

### Typing in a note creates a linked notes folder that doesn't exist
- **Where:** `qml/services/apps/NotesManager.qml:409` (`flush`), `qml/services/apps/NotesManager.qml:302` (`refreshList`)
- **What:** notes.md: "A linked folder is never created", and the note list says "The notes folder doesn't exist" (`directoryMissing`). But a module still opens its last note (a missing file reads as an empty note) and `flush()` saves through `FileManager.write`, which writes the file "making its folders" (FileManager.qml's comment). With `Notes.directory` on a drive that isn't mounted yet (or mistyped), the first keystroke in an edge-menu scratchpad creates the whole path on the root disk; mounting the drive later hides that note under the mount. CONFIRMED by reading. Fix: waits on the decision below. A fix that keeps the edit dirty (tried in the features-10 branch) writes it over the real note once the folder returns: a document opened while the folder was missing read its note as empty, `_fromDisk` doesn't reload a dirty document, and the `find` that sees the folder again flushes the edits, so typing "x" in a scratchpad and then mounting the drive writes "x" over the vault's real scratchpad.md (changing `Notes.directory` away from a missing folder does the same to the new folder's note of that name). Found by reading; not run. So the fix waits on a maintainer decision: "Which should the kept edits become: dropped, saved as a conflict copy, or prevented by making the editor read-only while the folder is missing?"
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:notes system

### The panel's relative times go stale while Tailscale's state stays the same
- **Where:** `qml/components/content/Tailscale/Tailscale.qml:46` (`now`, `keyDays`), `qml/components/content/ClaudeUsage/ClaudeUsage.qml:22` (`now`)
- **What:** `now` and `keyDays` are re-read only when `TailscaleManager.peers` is reassigned (`void TailscaleManager.peers; return Date.now();`). The daemon's topic hub pushes a state only when its JSON changed (`backend/internal/topics/topics.go:344`, `if bytes.Equal(data, t.last)`), and `Parse` keeps only the peers' online/active/relay/last seen/traffic fields. On a quiet tailnet (all peers offline or idle), nothing changes between polls. A module left on the desktop or in an edge menu then keeps saying "Offline · seen 3m ago" for hours, and the key-expiry warning appears only at the next unrelated change after the 7-day mark. ClaudeUsage's `now` is built the same way, though its accounts' `fetchedAt` changes at every fetch, so it lags by one fetch interval at most. PLAUSIBLE: what's unproven is whether an idle tailnet's parsed state really repeats byte for byte; to settle it, compare two `tailscale status --json` runs parsed a minute apart on a connected, idle tailnet. Fix: drive the times from a minute clock, as Notifications does (`SystemClock { id: clock; precision: SystemClock.Minutes }`, `readonly property real now: clock.date.getTime()`), and compute `keyDays` from `root.now`.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the tailscale system

### An app reading the camera through V4L2 never shows as using it
- **Where:** `qml/services/system/PrivacyManager.qml` (cameraCaptures), `qml/components/bar/widgets/Privacy/Privacy.qml`
- **What:** Camera use is read only from PipeWire links into a `Stream/Input/Video` node. Chromium and Electron (Discord, Vesktop) open the camera through V4L2 (`/dev/video0`) by default; their PipeWire camera path is the opt-in `WebRtcPipeWireCamera` feature. The Discord and Vesktop flatpaks have `devices=all`, and logind's seat ACL (`crw-rw----+`) lets the user's processes open the device, so a call with the camera on shows nothing in the Privacy widget or the OSD's camera status. Checked 2026-11-01: inotify on `/dev/video0` reports `IN_OPEN` / `IN_CLOSE_*` from any process (event-driven, no polling), and `/proc/<pid>/fd` of a flatpak's processes is readable, with the app id in `/proc/<pid>/cgroup` (`app-flatpak-dev.vencord.Vesktop-….scope`). Fix: the daemon watches `/dev/video*` (and `/dev` for cameras plugged in) with inotify, and on each event lists the processes holding one open (skipping pipewire and wireplumber, whose use the links already show), pushed as `camera.state` `[{ pid, app }]` (flatpak id, else the desktop entry by `comm`); `PrivacyManager.cameraCaptures` merges it. Opening the device without streaming (a camera picker listing devices) also counts, briefly.
- **Size:** small
- **Found:** 2026-11-01, while asked why Vesktop's camera never showed in the OSD

### Tailscale's state is polled where it could be pushed
- **Where:** `backend/internal/tailscale/tailscale.go`, `qml/services/apps/TailscaleManager.qml` (acquire), `qml/services/system/VpnManager.qml` (acquire)
- **What:** Tailscale's state comes from `tailscale status --json` every `Tailscale.interval` (10 s default) while anything holds `TailscaleManager`: the Tailscale and Vpn widgets, the Network, WifiNetworks and VpnConnections cards, and now an OSD with the VPN status, which holds it for the whole session. A connect or drop shows up to 10 s late, while NetworkManager's VPNs are pushed (`vpn.state`). tailscaled's LocalAPI streams its changes (`/localapi/v0/watch-ipn-bus`, what `tailscale status --watch`-style clients use), so the daemon could watch that instead of running the CLI, with the interval left only for the peers' details if needed.
- **Size:** needs a plan
- **Found:** 2026-11-01, while adding the OSD's VPN status

### DockMenu draws its own menu rows and keys rather than StyledContextMenu's
- **Where:** `qml/components/surfaces/dock/DockMenu.qml`, `qml/components/reusable/StyledContextMenu.qml`
- **What:** The dock's right-click menu (Keep in dock / Remove from dock, New window, Close) builds its own rows, hover and click handling, the same items the shared right-click menu takes (`{ id, text, icon, enabled }`), with no keyboard. It's a `PopupWindow` beside the dock, where StyledContextMenu is a Popup in the page's window, so sharing them means pulling StyledContextMenu's rows and keys out into a part both draw in.
- **Size:** small
- **Found:** 2026-11-04, while building the bar editor's right-click menu (bar rewrite C17)

### Six x-auto settings still store Automatic as -1
- **Where:** `qml/config/schema/definitions/layout/EdgeMenu.yaml:129`, `qml/config/schema/definitions/layout/EdgeMenu.yaml:150`, `qml/config/schema/definitions/common/DockEntry.yaml:51`, `qml/config/schema/definitions/common/OSDEntry.yaml:52`, `qml/config/schema/sections/Notifications.yaml:56`, `qml/config/schema/sections/Notifications.yaml:215`
- **What:** `x-auto` now takes a `null` automatic value (validation lets it through, and the form's number keeps its whole range), which the bar's `floatingGap` uses. These six still store Automatic as `-1`, so their readers test `>= 0` / `< 0` and their minimum can't be 0 and Automatic at once without the sentinel. Moving them to `null` is a format-2 step per setting (`-1` → `null`) and a reader change each; nothing is broken meanwhile.
- **Size:** small
- **Found:** 2026-11-04, while building the bar rewrite (x-auto with a null value, A1)
