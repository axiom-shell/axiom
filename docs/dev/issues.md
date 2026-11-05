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

### A bar widget's elasticity is stated twice
- **Where:** `qml/components/bar/widgets/Window/Window.qml` (`sizePolicy`), `qml/components/bar/widgets/Media/Media.qml` (`sizePolicy`), `qml/config/BarsConfig.qml` (`availableWidgetTypes`)
- **What:** A widget that shrinks when crowded says so twice: `sizePolicy: "elastic"` in its QML (read by `BarWidgetHost`) and `elastic: true` in its `schema.yaml` (`x-elastic`, read by the editor to show the minimum and maximum). Nothing keeps them in step, so a new elastic widget that sets only one either shrinks with no min/max fields in the inspector, or shows fields that do nothing. Fix: a check that a type has `x-elastic` exactly when its QML's `sizePolicy` is `"elastic"`, or `BarWidgetHost` taking `elastic` from the type info.
- **Size:** trivial
- **Found:** 2026-11-05, while reviewing the bar rewrite

### BarContainer's two join openings repeat their stretch
- **Where:** `qml/components/bar/BarContainer.qml` (`joinOpening`, `_solidJoinOf`)
- **What:** Both work out the same `from` and `span` and make the same `EdgeAttach.joinOpening` call (the border's opening also passes the fillet). One private helper returning the stretch would leave each with only what differs.
- **Size:** trivial
- **Found:** 2026-11-05, while reviewing the bar rewrite

### A VPN bind ignores Tailscale unless a VPN widget is showing
- **Where:** `qml/services/system/VpnManager.qml` (`_tailscaleShown`, `toggleLast`)
- **What:** Tailscale joins `rows` only while something acquires the VPN state (`_registry.active`), so `axiom ipc vpn toggle` from a keybind, hot corner or `axiom vpn toggle` sees only NetworkManager VPNs: with Tailscale the only VPN it says "No VPN set up", and with Tailscale up it brings the last NetworkManager VPN up instead of taking Tailscale down. The IPC toggle should read Tailscale's state once (acquire, act, release) before choosing.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the bindable commands

### Included's hookup can put sway-only lines into a config i3 still runs
- **Where:** `backend/internal/compositor/manager/sway.go` (`userMain`)
- **What:** Since compositor-06, sway's include and autostart targets are the config sway runs (`userconf.SwayMain`), so an i3 migrant whose sway runs `~/.config/i3/config` gets **Add it for me**'s include line written there. If they still run i3 from that same file, i3 follows the include into axiom's sway module and reports its sway-only lines as errors. Rare (one file shared by both, included mode); found by the branch review, left logged rather than widening the batch. Fix when it comes up: the hookup notes, or refuses with a reason, when its target is under an `i3/` folder.
- **Size:** small
- **Found:** 2026-11-02, while reviewing roadmap row 20's compositor-06

### MediaManager's start-up pass throws: the engine has no Object.fromEntries
- **Where:** `qml/services/system/MediaManager.qml:228` (`_startedAt`)
- **What:** `Component.onCompleted` sets `root._startedAt = Object.fromEntries(…)`, but Qt's JS engine has no `Object.fromEntries` (qml-pitfalls.md › The JS engine). Every start and reload logs `TypeError: Property 'fromEntries' of object function Object() { [native code] } is not a function` (a nested niri run's log, 2026-11-02), and the `_pick()` after it never runs: the players already running at start get no start time, and nothing is picked until the player list changes. Fix: `reduce`, as the pitfall says; `check_structure` could refuse `fromEntries` and `flatMap` as it refuses an optional call on a computed member.
- **Size:** trivial
- **Found:** 2026-11-02, while fixing roadmap row 20's core-ui-theming-04

### A NowPlaying seek shows the old place until the next tick, and keeps it while paused
- **Where:** `qml/services/system/MediaManager.qml` (`setPositionByRatio`), `qml/components/content/NowPlaying/NowPlaying.qml` (`seek`)
- **What:** `setPositionByRatio` writes `activePlayer.position` but not `MediaManager.position`, which only `_positionTimer` copies over (every 500 ms, and only while playing). Released, the seek slider shows its `value` (`MediaManager.progress`, still the old place) and glides back to it, then jumps to the seek at the next tick; paused, it stays on the old place (and the time beside it) until playback resumes. The same before core-ui-theming-06 (the old slider put `targetValue` back on release). Found by reading; a seek while paused settles it. Fix: `root.position = seekPosition` in `setPositionByRatio`.
- **Size:** trivial
- **Found:** 2026-11-02, while reviewing roadmap row 20's core-ui-theming-06

### The text cursor keeps blinking with animations off
- **Where:** `qml/components/reusable/TextCursor.qml`
- **What:** its `SequentialAnimation on opacity` loops whenever the input has focus, whatever `Appearance.animations` says, against AGENTS.md › Config: "looping animations gate `running` on `Appearance.animations`" (`check_structure` doesn't check it). Carried over from StyledTextEntry's and StyledTextArea's copies. Fix: `running: root._focused && Appearance.animations`, and opacity back to 1 when it stops (a stop leaves it wherever the blink was, maybe 0).
- **Size:** trivial
- **Found:** 2026-11-02, while reviewing roadmap row 20's core-ui-theming-06

### The compositor facts' axiomPath is read by nothing
- **Where:** `backend/internal/compositor/manager/inputs.go` (`BindCtx`), `qml/services/compositor/CompositorConfigManager.qml` (`axiomPath`)
- **What:** The shell sends `ctx.axiomPath` (`Paths.axiomPath`, the QML dir) with the compositor facts, and `BindCtx.AxiomPath` decodes it, but no renderer reads it: the binds' commands use only `axiomBin`, `shellCommand` and `restartCommand` (`grep 'get(ctx, "' backend/internal/compositor`). A dead field both sides keep up, which the move to `qml/` had to update in `manager/testdata/facts.json` all the same. Fix: drop the field and the shell's key (and the fixture's).
- **Size:** trivial
- **Found:** 2026-11-03, while moving the backend to the qml/ layout

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

### The Vpn widget's icon and label are invisible on a filled bar
- **Where:** `qml/components/bar/widgets/Vpn/schema.yaml`, `qml/components/bar/widgets/base/BarIconWidget.qml` (`colors`)
- **What:** The Vpn widget's schema has no `foregroundColor` (no `colors` part, no own field), so `properties.foregroundColor` is undefined, `Theme.resolveColor` makes it transparent, and on a bar whose `widgetStyle` is `filled` (the default) `BarWidgetStyle.colors` draws its icon and label in that: an empty pill. Seen with the Drives widget, which was built from it (fixed there by adding the field as IdleInhibitor has it). Fix: the same `foregroundColor` field on Vpn; a `tst_Config` check that every `BarIconWidget` type has one would keep it from coming back.
- **Size:** trivial
- **Found:** 2026-11-01, while testing removable drives in a nested shell

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

### A tray menu logs an undefined menu handle
- **Where:** `qml/components/content/parts/TrayMenuList.qml` (`menuOpener`)
- **What:** Using the tray logged `@components/content/parts/TrayMenuList.qml[45:5]: Unable to assign [undefined] to qs::menu::QsMenuHandle*`: `QsMenuOpener.menu` is bound to `root.menu` while that's still (or again) undefined, likely as a menu opens or closes. Seen once in the live log (not reproduced).
- **Size:** small
- **Found:** 2026-10-30, while moving the Wi-Fi popout's buttons

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

### A shared file older than v71 resets niri's hot corner
- **Where:** `backend/internal/share/zz_generated_movedkeys.go` (`movedKeys`), `backend/internal/migrate/steps/v82.go`
- **What:** `movedKeys` lists `Compositor.niri.hotCorner` (moved into shared files at v71), but step v82 made niri's hot corner an axiom one and the key is gone from the schema. `KeepMovedKeys` looks it up in the user's current config, finds nothing, and a format-1 shared file older than v71 applies without keeping the user's hot corner. The v82 shape isn't a plain rename (it became a `HotCorners` item), so the list can't just name a new path.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the notifications revamp branch (its v83 rename had the same gap, fixed there)

### A custom Ring element logs an undefined `inside` on load
- **Where:** `qml/components/content/parts/custom/elements/Ring/CustomRing.qml` (`inside`)
- **What:** The live shell logs `CustomRing.qml[17:3]: Unable to assign [undefined] to QString` after a reload: `root.options.inside` is read before the element's options carry it (seen on main after row 17, with a custom widget's Ring element on screen). The ring draws once the options arrive, but the log isn't clean.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the hot corners branch (row 16)

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

### A fast chat reply can drop the shell's connection
- **Where:** `backend/internal/rpc/rpc.go` (`Conn.enqueue`, `Limits.QueueSize`), `backend/internal/daemon/chat.go` (`chat.send`'s `c.Notify`), `backend/internal/chat/send.go` (`Send`)
- **What:** Each piece of a reply is its own `chat.delta` notification (`Notify`, not latest-wins), and `enqueue` never waits: when the connection's 4096-message queue is full it logs `dropping a peer that stopped reading` and closes the connection, every topic and call in flight with it. So if the shell stops reading (its event loop busy) while a fast provider streams, once the socket buffer and 4096 deltas fill (seconds at the fastest servers' token rates, a delta per token or two), the shell's whole connection goes. Before stage 5 curl's pipe simply blocked. A fix would coalesce the deltas `Send` emits (text gathered while a push waits) or let `chat.send` wait for room instead of dropping the peer.
- **Size:** small
- **Found:** 2026-10-27, while reviewing the chat move to axiom (backend stage 5)

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

### Unbounded lists still built in full
- **Where:** `qml/components/content/parts/chat/ChatMessageList.qml`, `qml/components/content/parts/chat/ConversationList.qml`, `qml/components/content/Agenda/Agenda.qml`, `qml/components/content/Calculator/Calculator.qml` (history), `qml/components/content/Stopwatch/Stopwatch.qml` (laps), `qml/components/content/parts/TodoList.qml`
- **What:** Each builds one delegate per item in a Repeater, with no limit, as `DeviceList` did before it became a ListView (52 Wi-Fi networks took 1.8 s). None showed as slow on the test machine, but they grow with use: a long chat or note becomes a slow module and popout. ListViews (or streamed sections) would build only what's in view.
- **Size:** small
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
- **What:** In a floating edge menu a `StyledComboEntry` opens inline, capped by the Flickable around it. A card with no Flickable (Pomodoro as a card, its task picker) gets the two-row minimum, and the card's rows below it are pushed out of view while it's open.
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


### The Layouts canvas logs null reads as it's torn down
- **Where:** `qml/components/views/Layouts/CanvasModule.qml` (`editor`, `carried`, the label and icon bindings), `qml/components/views/Layouts/GridCanvas.qml` (its `CanvasModule` Loader)
- **What:** Tearing down a page with a layout canvas (a reload, or the overlay closing after moving between pages) logs a burst of `TypeError: Cannot read property 'editor' of null` from `CanvasModule.qml[25:-1]`, then `draggingKind`, `moduleIcon`, `moduleLabel`, `dragging` of null, once per module: `dragLayer` is gone before the modules' bindings stop. Likely `root.dragLayer?.editor` at the source (`editor`), with the other reads following it.
- **Size:** small
- **Found:** 2026-10-29, while screenshotting editor pages for the form row look

### A custom layout's element rect reads an undefined place
- **Where:** `qml/components/content/parts/custom/CustomLayout.qml` (the `CustomElement` delegate's `r`), `qml/components/methods/CustomWidgetData.qml` (`rect`)
- **What:** The live shell logs `CustomWidgetData.qml[649:-1]: TypeError: Value is undefined and could not be converted to an object` after a reload: the delegate passes `element.place` while its `element` is still the `({})` stand-in (or past the end of a shrunk `elements`), and `rect` reads `place.x`. `rect` returning an empty rect for no place, or the delegate waiting for one, would quiet it.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the bar display styles branch

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

### The monitor prompt's padding is a bare 18 px, and check_sizes misses it
- **Where:** `qml/components/surfaces/monitors/MonitorPromptWindow.qml` (`pad`), `scripts/check_sizes.py` (`SIZE_WORD`)
- **What:** `readonly property int pad: 18` (MonitorPromptWindow.qml:19, used at :50-51) stays 18 px at every Interface scale while the card's text scales; AGENTS.md has sizes outside the bars from `Widget.px(n)`. `check_sizes.py` doesn't flag it because its size words have no `pad`. Fix: `Widget.px(18)`, and add `pad` to `SIZE_WORD` (the check that would have caught it). The overlay's page navigator has the same gap: `readonly property real inset: 6` (`qml/components/hosts/overlay/OverlayPageNavigator.qml:38`) insets its arrows, tabs and pill in a bar whose height follows `Widget.height`. It should be `Widget.px(6)`, and `inset` belongs in `SIZE_WORD` too (found while reviewing the overlay system, 2026-10-31).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

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

### BarPopouts works out its slide distance itself
- **Where:** `qml/components/hosts/popout/BarPopouts.qml:251` (`underStart`), `qml/components/hosts/popout/BarPopouts.qml:510` (`detachedOffset`), `qml/components/methods/SurfaceContext.qml:399` (`layout`)
- **What:** `SurfaceContext.layout` now returns `slideDistance` (the bar's outer edge, past the border stroke a bar inside the border lies on), which EdgePopout reads. BarPopouts still works the same rule out itself: `underStart: barConfig.insideBorder ? Appearance.borderWidth : 0` and `detachedOffset: underBar ? attachAt - underStart : 0`. That breaks qml/components/hosts/popout/AGENTS.md: "Never add a rule in a host". Its `attachAt` is `placement.attachFromBar`, which carries `_attachShift`, so the two may differ where the followed panel isn't its own bar; check that before switching. Fix: BarPopouts reads `placement.slideDistance` (with the shift added if it belongs there) for `detachedOffset` and `surfaceFrom`, and `underStart` goes.
- **Size:** small
- **Found:** 2026-11-05, while reviewing bar-popouts-03 (EdgePopout's placement read from SurfaceContext)

### A tray submenu longer than the screen runs off it
- **Where:** `qml/components/content/parts/TraySubmenu.qml:14` (`implicitHeight`), `qml/components/content/parts/TrayMenuList.qml:29` (`implicitHeight`), `qml/components/hosts/popout/SubPopout.qml:133` (`maxContentHeight`)
- **What:** SubPopout gives submenu content the room it has (`maxContentHeight`, from `screenFrom`/`screenTo`), and submenus.md says "content that may be taller … scrolls past `maxContentHeight`". Only `Submenu/MenuSubmenu.qml:46` reads it. `TraySubmenu`'s height is `menuList.implicitHeight`, and `TrayMenuList` is a bare ColumnLayout with no Flickable. So a tray submenu with more entries than fit (about 25 or more on a 1080 px screen) is as tall as all its entries. `SurfaceContext.submenuPlace` clamps only its start, so the box runs past the screen's bottom and the last entries can't be reached. Fix: `TrayMenuList` takes a `maxHeight` (unbounded by default) and wraps `menuLayout` in a Flickable as MenuSubmenu does; TraySubmenu passes `root.wrapper.maxContentHeight`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### A pill's shadow run-on rectangles log stackAfter warnings
- **Where:** `qml/components/bar/BarContainer.qml` (the pill's `_runOnShadow` Repeater)
- **What:** With a bar shadow on and pills joined at an end, the log shows `QQuickItem::stackAfter: Cannot stack QQuickRectangle_QML_… after QQuickRectangle_QML_…, which must be a sibling` (seen in a nested Hyprland with the shadow on). The Repeater's delegates set `parent: shadowShape`, so a new delegate is stacked after one that has already left the Repeater's parent. Fix: build them in a Repeater inside `shadowShape` (as `_flushEnds` does), keyed by pill.
- **Size:** small
- **Found:** 2026-11-04, while making pill bars lie as solid ones (bar rewrite)

### A custom clock format without spaces spills past a vertical bar
- **Where:** `qml/components/bar/widgets/Time/Time.qml:108` (`_split`)
- **What:** On a vertical bar the clock is `thickness` wide, and a custom format is stacked one part per line, split only on whitespace and `:` (`text.split(/[\s:]+/)`). With `dateFormat: "yyyy-MM-dd"` (or `dd.MM.yyyy`, `HH.mm`) the whole value is one line ("2026-10-30" is about 70 px at font 14), centred in a ~26 px column. BarWidget doesn't clip, and the host clips only while resizing, so the text draws across the bar's edge onto the windows beside it. The file's header promises "On a vertical bar each is stacked into short lines". Fix: split on `/[\s:.\-\/,]+/`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### SystemStats copies ValueStyleWidget's pill colour and text-by-state rule
- **Where:** `qml/components/bar/widgets/SystemStats/SystemStats.qml:149` (`backgroundLevelColor`, `_textByState`), `qml/components/bar/widgets/base/ValueStyleWidget.qml:43` (`backgroundLevelColor`, `_textByState`)
- **What:** What's left of the style-fallbacks entry once `ValueGraphic.resolvedStyle` took the style rules: `Qt.alpha(colors.icon, 0.35)` and `appearance.colorText && colors.fill.a < 1` are still written in both widgets, so a change to the pill's colour or to when the text takes the state's colour would miss SystemStats. A ValueGraphic member doesn't reach them: SystemStats' root draws the pill and colours the text, and its graphics are one per segment, inside the Repeater. Fix: one shared place both roots can call (a `BarsConfig` or `BarWidgetStyle` function taking the widget's `colors` and `appearance`).
- **Size:** trivial
- **Found:** 2026-11-05, while reviewing bar-popouts-09

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

### Tailscale's PeerRow redraws DeviceRow without its buttons
- **Where:** `qml/components/content/Tailscale/Tailscale.qml:103` (`PeerRow`), `qml/components/content/parts/DeviceRow.qml`
- **What:** PeerRow (lines 103–167, 65 lines) is DeviceRow's row drawn again: the same `Rectangle` with `Widget.radius`, the hover colour with `ColorGlide`, the `RowLayout` margins, a `StyledIcon` at `Appearance.fontSize * 1.4` coloured by state, and a name (`fontSizeBy(-1)`) over a status (`fontSizeBy(-3)`), both elided. The only differences are that it has no connect or forget buttons, and that it shows "Copied" for 2 s. Fix: give DeviceRow `property bool connectable: true` to gate its connect button, and write PeerRow as a DeviceRow with `connectable: false` and its copy handler and timer. That is about 20 lines, so 45 fewer.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### WifiNetworks' WPA password form repeats WifiJoinForm's
- **Where:** `qml/components/content/WifiNetworks/WifiNetworks.qml:179` (`pskForm`), `qml/components/content/parts/WifiJoinForm.qml`
- **What:** For `row.kind === "psk"`, the row loads `pskForm` (lines 179–209, 31 lines): a password field (echo Password, Enter submits, Escape calls `NetworkingManager.cancelPassword()`, focused on load) and a connect button enabled while the field isn't empty. `WifiJoinForm { security: "psk" }` draws the same: only its password row and connect button, focused first, and complete when the password isn't empty. The only difference is where the password goes, Quickshell's `connectWithPsk` rather than `join`. Fix: drop `pskForm` and the `sourceComponent` switch, and make the join form's `onSubmitted` choose `NetworkingManager.connectWithPsk(row.network, fields.password)` for psk rows. That is 32 lines fewer. Check that WifiJoinForm's Escape also reaches `cancelPassword`.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### Login and Password each carry the same required-field report
- **Where:** `qml/components/content/Login/Login.qml:43` (`_report`), `qml/components/content/Password/Password.qml:41` (`_report`)
- **What:** Both modules hold the same 12 lines: `_reportedKey`, a `_report()` that unreports the old key and reports the new one through `SurfaceManager.reportRequiredField`, and `Component.onCompleted`, `onHostChanged` and `Component.onDestruction`. They differ only in the host test (`onGreeter` / `onLockscreen`). Fix: one small QtObject part in `content/parts/` holding the 12 lines, given the host and whether it applies. Each module keeps 1–3 lines, so about 20 lines fewer.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### WeatherForecast repeats the Weather card's current conditions
- **Where:** `qml/components/content/WeatherForecast/WeatherForecast.qml:23`, `qml/components/content/Weather/Weather.qml:70` (`Current`)
- **What:** The popout's place name, condition icon, temperature, condition and details (lines 23–57, 35 lines) are the card's `Current` component drawn again with its own sizes. `Current`'s own comment says "as in the bar's forecast popout". A change to how the current weather reads (units, details) has to be made twice. Fix: move `Current` into a part in `content/parts/` and use it in both, so the popout is about 30 lines shorter. Or make the Weather card a Panel that is also the popout (content-roots.md's one-file shape) and drop WeatherForecast (96 lines).
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### What a lock screen module may do is a list kept by hand in two docs that disagree
- **Where:** `qml/components/content/AGENTS.md:13`, `docs/dev/features/lockscreen.md:81`, `scripts/check_structure.py`, `qml/components/content/Power/schema.yaml`, `qml/components/content/NowPlaying/schema.yaml`, `qml/components/content/VolumeDials/schema.yaml`
- **What:** `qml/components/content/AGENTS.md` says a `lockscreen` module launches, dispatches and writes nothing, and "the one exception is `Power`"; lockscreen.md › Which modules may go here also allows NowPlaying (media transport) and VolumeDials (mute), which their schemas host there. Nothing checks what a module whose `x-hosts` list `lockscreen` calls, so a new action in such a module (or a new module added there) reaches the locked screen unnoticed, and the two lists drift.

  **Decided** (maintainer, 2026-10-31): "use reccomendation as described. Everything that has an action now keeps it (unless it actually is dangerous, but everything now should be okay). Note in that there should be settings for allowing/viewing notifications as well". Fix: a schema annotation on module types, `x-lockActions: [session | media | volume]` (Power `[session]`, NowPlaying `[media]`, VolumeDials `[volume]`). `check_structure` maps each action to the service methods it covers (`session`: `SessionManager.sessionAction`; `media`: `MediaManager.togglePlayPause|next|previous|setPositionByRatio|selectPlayer`; `volume`: `AudioManager.toggleMute|toggleSourceMute|stepNodeVolume`) and fails any `XManager.method(` call in a type whose hosts include `lockscreen` that is neither read-only (a small allowlist: `acquire`, `release`, `formatTime`, `wants`, …) nor covered. A call site that gates itself carries `// lock-inert: <reason>`. Both docs point at the annotation instead of listing modules. Breaking fixture: a lockscreen module calling `CommandManager.run`. Every module that acts today keeps its actions, VolumeDials' volume step included.

  Also asked: lock screen notification settings, filed and deferred as [The lock screen has no settings for allowing or viewing notifications](#the-lock-screen-has-no-settings-for-allowing-or-viewing-notifications).
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### Any custom widget reaches the lock screen past its Offer switch
- **Where:** `qml/components/content/CustomWidget/CustomWidget.qml:23` (`widgetId`), `qml/config/OverlayConfig.qml:108` (`customModuleTypes`), `qml/services/ui/SettingsManager.qml:370` (the `customWidgets` options), `qml/components/views/Layouts/EditorInspector.qml:244`
- **What:** `module.lockscreen` ("Offer on the lock screen": "what it prints shows to anyone at the screen: offer only what's fine to show") is checked only by the lock screen's library (`OverlayConfig.customModuleTypes` drops the `lockscreen` host when it's off). A placed module draws whatever its `properties.definition` names: (1) turning the switch off after placing one leaves it on the lock screen, its script running; (2) the lock screen's inspector shows the module's settings form (`EditorInspector.qml:244`), whose definition picker lists every definition (`x-options: customWidgets` → `CustomWidgetsConfig.items.map(item => item.id)`), so any definition can be switched in. Nothing in `CustomWidget.qml` reads `module.lockscreen` (grep: only `actionsEnabled` checks `host.kind`). Fix: on the lock screen, a definition without `module.lockscreen` is treated as none: `widgetId` empty when `root.host?.kind === "lockscreen" && !CustomWidgetsConfig.definition(id)?.module.lockscreen` (so nothing is acquired), with its EmptyState saying it isn't offered there.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A stale exec-if check can block a widget after its exec-if changed
- **Where:** `qml/services/apps/CustomWidgetsManager.qml:163` (`_checkIf`)
- **What:** The check's callback only asks whether the id is still watched (`if (!(id in root._watching))`), not whether its `execIf` is still the one checked. Editing Run only if on the page re-checks on every keystroke (`_wanted` changes, `_sync` calls `_checkIf`), and clearing it watches at once (`_watch`). A check that ends after a newer one, e.g. typing `ping -c1 -W1 myhost` (the partial `ping -c1 -W1 myh` waits its second to fail while the full one answers in milliseconds), sets `_blocked`, releases the watch the newer check started and shows `"ping -c1 -W1 myh" failed` until the next refresh. PLAUSIBLE: the order the checks end in; a slow failing prefix settles it. Fix: `if (root._watching[id]?.execIf !== def.execIf) return;` in place of the `in` check (`_watching` holds each id's `execIf`).
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A command naming a program shows the program as its script
- **Where:** `qml/components/views/CustomWidgets/DefinitionsPanel.qml:26` (`scriptText`), `qml/services/apps/CustomWidgetsEditor.qml:184` (`scriptPath`)
- **What:** `scriptPath` is the command's first word whenever it starts with `/` or `~/`, so a command like `/usr/bin/sensors -j` or `/opt/cuda/bin/nvidia-smi …` names a binary: `FileManager.read` (a blocking FileView, on the UI thread, of the whole file) reads the ELF into a string, The script group shows its first 40 "lines" of binary as the script, and `signalsWaybar` regex-scans it. A large binary stalls the page while it reads. Fix: show only a script, text starting with `#!` (`scriptText.startsWith("#!")` for `scriptHead` and `signalsWaybar`); reading only the head needs a size cap `FileManager.read` doesn't have.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### CustomElement's six Binding blocks are Qt.binding in its setSource
- **Where:** `qml/components/content/parts/custom/CustomElement.qml:33` (the `Binding` blocks), `qml/components/content/parts/custom/CustomElement.qml:21` (`_load`)
- **What:** `_load` hands the element its six properties as plain values, then six `Binding { when: root.item !== null … }` blocks (lines 33-68, 36 lines) keep them current. Passing each as `Qt.binding(() => root.element)` (and so on) in `setSource`'s properties, as `BarTab`'s `BarPreview` loads the bar widget, keeps them bound from creation, across a kind change (each `_load` binds the new item) and drops the 36 lines. Fix: wrap the six values in `Qt.binding`, delete the Binding blocks; the file goes from 69 to 33 lines.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A custom layout without elements rebuilds its default elements every sample
- **Where:** `qml/components/content/parts/custom/CustomLayout.qml:24` (`elements`)
- **What:** For a definition with no elements, `elements` reads `root.fields?.ratio`, so every push (4 a second for a stream, per surface showing it, plus the Module tab's five previews) runs `CustomWidgetsConfig.defaultElements` (two `ConfigManager.withDefaults` schema walks) and hands every element a new `element` object, re-evaluating its `place`, `bind`, `options` and `rect`. Only whether there is a value matters. Fix: `readonly property bool _hasValue: (root.fields?.ratio ?? -1) >= 0` read by `elements` (a bool that doesn't change doesn't notify), keeping the Icon/Ring switch.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### An integrated top or bottom menu's zone follows its growing modules
- **Where:** `qml/components/surfaces/edgemenu/IntegratedEdgeMenu.qml:49` (`depth`), `qml/components/surfaces/edgemenu/IntegratedEdgeMenu.qml:135` (`exclusiveZone`), `qml/components/surfaces/edgemenu/EdgeMenuBody.qml` (`maxGrownHeight`)
- **What:** hosts.md says of an integrated menu: "The zone is set once while it's open (windows retile in one step)". But `depth` is `Math.ceil(root.bodyDepth + root.pad * 2 + root.innerStroke)`, with `bodyDepth` the body's live `implicitHeight` on a top or bottom edge: `ModuleGrid.sizes.height`, from the grown places (`ModuleGrid.places`). `exclusiveZone` and the window's `implicitHeight` follow it. So a top menu holding a module with `grow` (Notifications, AudioMixer, WifiNetworks, …: nine modules have it) changes its exclusive zone each time that module grows or shrinks, e.g. when a notification arrives: the windows retile again, and the shown layer window grows (the squeezed flash growing popout windows show). FloatingEdgeMenu avoids this by reserving the most up front (`maxContentDepth: root._body.maxGrownHeight`). Proposed fix (not decided): reserve `maxGrownHeight` on a top or bottom integrated menu, so the zone is set once.

  **On hold** (maintainer, 2026-10-31): "put this on hold - note that growing modules kinda needs a re-work or removal". Growing modules as a whole (`grow`, [grow-expand](overlay/grow-expand.md)) need a rework or removal; this entry waits for that and is [deferred](roadmap.md#deferred). No design is recorded.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

### ToastStack logs a binding loop on _attachedShowing
- **Where:** `qml/components/surfaces/notifications/ToastStack.qml` (`_attachedShowing`)
- **What:** The live shell logged `Binding loop detected for property "_attachedShowing"` (`@shell/Notifications.qml[42:15]`, ToastStack.qml:485) on two reloads on 2026-11-01, not on the next. `_attachedShowing` reads `attached`, `covered`, `toasts` and `_leaving`, and its change handler calls `box.show()` / `box.hide()`; one of those likely writes back a value it reads during the same evaluation. Not traced.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the OSD's statuses

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

### The notification list's delegates animate with their own easing
- **Where:** `qml/components/content/parts/notifications/NotificationGroupDelegate.qml:124`, `qml/components/content/parts/notifications/NotificationGroupDelegate.qml:192`, `qml/components/content/parts/notifications/NotificationGroupDelegate.qml:301`, `qml/components/content/parts/notifications/NotificationItemDelegate.qml:80`
- **What:** AGENTS.md › Config: "a `duration:` is `Appearance.animFast` / `animNormal` / `animSlow` with `Appearance.easing`" (`check_structure` checks only the duration). Nine `easing.type: Easing.*` lines break it: `Easing.OutCubic` at NotificationGroupDelegate 124, 132, 195, 304 and NotificationItemDelegate 80, 88, 99, `Easing.InCubic` at NotificationGroupDelegate 147 and NotificationItemDelegate 117; and three opacity animations (NotificationGroupDelegate 153, NotificationItemDelegate 105, 123) have no easing at all, while the same snap-back in ToastItem uses `Appearance.easing`. (These nine are among the 24 literal easings outside the ui-kit that the ui-kit's own easing fix (`qml/components/reusable/`) left to their systems.) Two of them are whole `Behavior { NumberAnimation { duration; easing } }` blocks that `Glide` is for (shared-ui-pieces.md: "`Glide on width {}` ... `duration` for animNormal/animSlow"): the card's height (NotificationGroupDelegate 192–197) and the chevron's rotation (301–306), 12 lines. Fix: those two become `Glide on height { duration: Appearance.animNormal }` / `Glide on rotation { … }` (2 lines, 10 removed); the rest take `Appearance.easing` (or go with the shared swipe piece in [The history's group and entry delegates repeat one swipe-away mechanism](#the-historys-group-and-entry-delegates-repeat-one-swipe-away-mechanism)).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:notifications system

### The history's group and entry delegates repeat one swipe-away mechanism
- **Where:** `qml/components/content/parts/notifications/NotificationGroupDelegate.qml:76` (`swipe`, `snapBack`, `appear`, `slideOut`), `qml/components/content/parts/notifications/NotificationItemDelegate.qml:51` (`swipe`, `snapBack`, `appear`, `slideOut`)
- **What:** Both delegates carry the same DragHandler (sideways only, `shift.x` follows, opacity fades over twice the threshold, past `swipeThreshold` slides out else snaps back), the same `snapBack`, `appear` (fade in, drop 8 px) and `slideOut` (slide by the width the way it went, fade, then a script): NotificationGroupDelegate 76–163 (88 lines) and NotificationItemDelegate 51–129 (79 lines), differing only in what enables the swipe, the group's optional delay and what the end script dismisses. AGENTS.md › UI conventions: "a second copy of a pattern becomes a shared piece". Fix: one `parts/notifications/NotificationSwipe` (target item, `enabled`, `swipeThreshold`, `appear()`, `slideOut(delay)`, signal `out`) of about 60 lines; each delegate keeps about 8 lines (`NotificationSwipe { id: …; enabled: …; onOut: … }` and its calls). About 167 − 60 − 16 = 90 lines removed net, and the easing fix lands once.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:notifications system

### clearAll removes each cached image twice, one process per entry
- **Where:** `qml/services/system/NotificationManager.qml:132` (`clearAll`), `qml/services/system/NotificationManager.qml:422` (`_forget`)
- **What:** `clearAll` runs `_forget` for every entry, which spawns `rm -f <image>` for each entry with a cached image (`CommandManager.runDetached(["rm", "-f", …])`), then runs `sh -c 'rm -f "$1"*.png'` over the whole image folder anyway. With a full history (`maxEntries` up to 500) one Clear all starts up to 501 processes where the one glob does it all (and also catches orphans). Fix: `clearAll` unlinks and dismisses the live ones without the per-entry rm (e.g. `_forget(entry, keepFile)`, or `old.forEach(e => { const n = root._live[e.uid]; root._unlink(e.uid); n?.dismiss(); })` and `root._sources = {}`), keeping the glob.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:notifications system

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

### Skipping a focus session counts it as finished
- **Where:** `qml/services/apps/PomodoroManager.qml:71` (`skip`), `qml/components/methods/PomodoroCycle.qml:87` (`advance`), `qml/components/bar/widgets/Pomodoro/Pomodoro.qml:36`
- **What:** `skip()` calls `PomodoroCycle.advance`, which counts `completed + 1` whenever the phase was `work`, whether it ran out or was skipped. The doc and PomodoroCycle's header define `completed` as focus sessions *finished* ("Every `longBreakEvery`-th finished focus session is followed by a long break"). A right click on the idle Pomodoro widget (its skip) therefore counts a session that never started, lights a dot, and with `autoStartBreaks` (default on) starts a 5-minute break running; four stray right clicks bring a long break. Question for the maintainer: should a skipped focus session count (some apps count it), not count, or count only once started? Fix (if it shouldn't count): give `advance` a `finished` flag (true from `_finish`, false from `skip`) that gates the `+ 1`, with a `tst_PomodoroCycle` row.

  **Decided** (maintainer, 2026-11-01, on the recommendation "c) count only if the session had started"): "agree".
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:todo-pomodoro system

### A recent timer chip reads its label back as part of the duration
- **Where:** `qml/components/content/parts/CountdownTimer.qml:155` (`chipText`), `qml/components/content/parts/CountdownTimer.qml:233`
- **What:** A recent timer is kept as `{ ms, label }`, but its chip restarts it by turning it back into text (`formatShort(ms) + " " + label`) and re-parsing that through `started(text)`. A label that starts with a duration is read into the time. Run through `StopwatchClock.parse` as written: `90 5m` is 90 min labelled `5m`, its chip reads `1h30m 5m` and starts 1h35m with no label; `1:30 5m stretch` is 90 s labelled `5m stretch`, its chip `1m30s 5m stretch` starts 6m30s labelled `stretch`. Caffeine's popout shares the part. Fix: a recent chip emits the stored values (a `startedRecent(ms, label)` signal, or `started` carrying `{ ms, label }`), and the owners call `StopwatchManager.startTimer(ms, label)` / caffeine's equivalent instead of parsing text.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:todo-pomodoro system

### A todo.json deleted while unreadable blocks every save until restart
- **Where:** `qml/services/apps/TodoManager.qml:97` (`_load`)
- **What:** `_unreadable` is set when the file holds broken JSON and cleared only by a successful parse. When the file is then deleted (the obvious way out of a broken hand edit), `FileManager.read` returns null, `_load` sets only `_loaded`, and `_unreadable` stays true: every add, tick and delete is dropped with `Not saving over` warnings although there is nothing left to protect, until a valid file appears or the shell restarts. Fix: `if (text === null) { root._unreadable = false; root._loaded = true; }` (2 lines).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:todo-pomodoro system

### PomodoroDial redraws DialControls' ring and buttons
- **Where:** `qml/components/content/parts/PomodoroDial.qml:28` (`TimeRing`), `qml/components/content/parts/PomodoroDial.qml:58` (buttons), `qml/components/content/Pomodoro/Pomodoro.qml:39` (`dialSize`)
- **What:** `DialControls` (shared by the timer, caffeine and the stopwatch since #262) is "a TimeRing over (or beside, `horizontal`) three round buttons", sized to its card with `fill`. PomodoroDial builds the same thing by hand: a TimeRing (lines 28–35, 8 lines), stop / play-pause / skip FlatIconButtons (58–82, 25), its own `horizontal` / `dialSize` / grid columns (17–18, 24–26, 5), and Pomodoro.qml works out the dial size and width test itself (32, 39, 2): 40 lines. So the pomodoro's buttons look and size differently from the other three dials, and lack the keyboard (Space) they have. Fix: PomodoroDial becomes a `DialControls` (`leftIcon: "stop"`, `leftEnabled: !idle`, `mainIcon` play/pause, `rightIcon: "skip_next"`, `color: phaseColor`, `fill` from the card) with the session dots and the task picker under it, about 20 lines; Pomodoro.qml drops its dial sizing. The dots and picker then sit under the ring rather than beside it in a wide card. About 20 lines net.

  **Decided** (maintainer, 2026-11-01, on the recommendation "accept: the dots and picker move under the ring in a wide card"): "agree".
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:todo-pomodoro system

### Focus and Pomodoro build the parts their properties turn off
- **Where:** `qml/components/content/Focus/Focus.qml:68` (`PomodoroDial`), `qml/components/content/Focus/Focus.qml:81` (`TodoList`), `qml/components/content/Focus/Focus.qml:89` (`DayPane`), `qml/components/content/parts/PomodoroDial.qml:84` (task picker)
- **What:** qml/components/content/AGENTS.md: "a part shown in one mode only is a Loader gated on it, not `visible: false`". Focus's `showTimer`, `showTodos` and `showAgenda` only set `visible`, so a Focus card with the agenda off still builds a `DayPane` (its calendar list), and one with todos off the whole `TodoList`. PomodoroDial's task picker is `visible: root.showTask`, and Focus always passes `showTask: false`, so every Focus card builds a hidden `StyledComboEntry` whose `options` map the todo list again on each todo change. Fix: Loaders gated on each switch (`active: root.showAgenda` and so on), and the task picker in a Loader on `showTask`.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:todo-pomodoro system

### A Calendar card on the desktop or in an edge menu takes the page's request
- **Where:** `qml/components/content/Calendar/Calendar.qml:54` (`_takeRequest`), `qml/services/apps/CalendarManager.qml:297` (`openPage`)
- **What:** `openPage(request)` sets `CalendarManager.request` and opens the CalendarPage view (or the page with a Calendar module). Every embedded Calendar card listens (`onRequestChanged` → `_takeRequest`, gated only on `root.embedded`), and `embedded` is true in every module grid (`OverlaySlot.qml:56`), so a Calendar card on the desktop or in a pinned edge menu (both allowed: the module's schema leaves `hosts` out) takes the request synchronously, before the page is built. Then clicking the Next event bar widget or a reminder opens the Calendar page on today instead of the event's day, and `/event` or the `calendar newEvent` IPC opens the editor on the desktop card behind the overlay. A request no page shows (no page holds a Calendar, so Settings opens) also stays set until some Calendar card is next built, which then opens a stale new-event editor. Fix: `openPage` stores the page it opens in the request (`{ kind, key, page }`, and no request when it falls back to Settings); Calendar takes it only when it sits on that overlay page (its `host`), the view only when `page === "CalendarPage"`.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the calendar system

### A save conflict reloads nothing, so trying again conflicts again
- **Where:** `backend/internal/calendar/calendar.go:582` (`Save`), `backend/internal/calendar/calendar.go:618` (`Delete`), `qml/services/apps/CalendarManager.qml:325` (`errorText`), `qml/services/apps/EventDraft.qml:111` (`saveAs`)
- **What:** An event changed elsewhere (a phone) since the last sync: axiom's PUT gets 412 and `Save` returns `conflict` before `resync`, so objects.json and events.json keep the old copy and etag. The editor says "The event changed elsewhere. It has been reloaded: check it and try again." but nothing was reloaded, and Save again sends the same draft etag (`firstOf(r.Etag, obj.Etag)`, the draft's first) and conflicts again until the next timed sync, and even then the open editor keeps the stale etag. The same holds for a local calendar's file changed on disk, and for `cachedObject`'s conflict when the event is gone from the cache. Fix: on a `Conflict` from `put` or `cachedObject`, `Save` and `Delete` run `s.resync` for that calendar before returning the error; the editor, on `conflict`, reopens on the fresh event (`CalendarEvents.draftOf` of the occurrence with the same href and rid, or closes when it's gone), so what it says is true.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the calendar system

### Moving a recurring event to another calendar drops its earlier occurrences and exceptions
- **Where:** `qml/services/apps/CalendarManager.qml:205` (`save`, the move)
- **What:** Changing the calendar of an occurrence of a weekly series (not Custom: the picker is read-only for those) skips the "Change which?" question and saves as a move: a new event made from the draft, then the old one deleted as a series. The draft is `CalendarEvents.draftOf(event)` of the clicked occurrence, so the new series starts at that occurrence: every earlier one disappears (the old object, history included, is deleted), and its EXDATEs, overrides, attendees and unknown properties are lost (`NewEvent` builds from the payload). When the delete fails after the create (a conflict, the server down), both copies stay while the editor shows the error, and trying again creates a third. Fix: do the move in the daemon: `calendar.save` with a target calendar copies the cached object, applies the series edit (`ApplySeries`, keeping its first DTSTART, overrides and properties), PUTs it to the target with `If-None-Match: *` and the same UID, then deletes the old one, in one locked call that resyncs both calendars. The Custom rule's read-only picker then has no reason left.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the calendar system

### Enter in the editor's title saves again while busy and picks All events while asking
- **Where:** `qml/components/content/parts/calendar/EventEditor.qml:63` (`titleEntry`'s `onAccepted`), `qml/services/apps/EventDraft.qml:95` (`save`)
- **What:** Only the Save button is disabled while `busy`; the title's `onAccepted: root.save()` isn't, and `save()` doesn't check `busy`. A new event saved with Enter twice on a slow server queues two `calendar.save` jobs with no href: two identical events. And while the "Change which?" row shows for a recurring event, `save()` skips the question (`root.asking === ""` is false) and calls `saveAs("series")`: pressing Enter again after editing a title changes every occurrence without the user choosing. Fix: `if (root.busy || root.asking !== "") return;` at the top of `save()` (the row's own buttons pick the scope).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the calendar system

### Removing a CalDAV account deletes its password before the draft is saved
- **Where:** `qml/components/views/Settings/CalendarAccountsCard.qml:83` (`remove`)
- **What:** The account's removal goes through the settings draft (`SettingsManager.setValue`), which Reset changes or leaving without saving undoes, but `SecretsManager.clearSecret("calendar", root.accountId)` runs at the click. Removing an account and then resetting brings the account back with no password: every sync fails `no_password` until it's typed again. calendar.md keeps local calendars' folders for this very reason ("a draft can be reverted, so nothing is deleted"). Fix: leave the secret on remove, and clear the secrets of account ids gone from `Calendar.items` once a save lands (CalendarManager, on `CalendarConfig.accounts` changing).
- **Size:** small
- **Found:** 2026-11-01, while reviewing the calendar system

### Event titles from a feed render as styled text and load remote images
- **Where:** `qml/components/content/parts/calendar/MonthGrid.qml:296` (the title chips), `qml/components/content/Calendar/Calendar.qml:86` (the compact card's label), `qml/components/bar/widgets/NextEvent/NextEvent.qml:51` (`text`, `subtext`)
- **What:** `StyledText` leaves `textFormat` at Text.AutoText, so a title whose first tag is HTML (`Qt::mightBeRichText`) is rendered as styled text. An `.ics` subscription is anyone's content: an event titled `<img src="https://tracker.example/p.png"> Standup` makes the shell fetch that URL whenever the month's titles, the compact Calendar card or the Next event widget show it, telling the feed's author the user's address and when they look (events are private: calendar.md › Privacy). Tested: a Qt 6 `Text` with `"9:00 <img src=\"http://127.0.0.1:18765/pixel.png\"> Standup"`, run offscreen, made `GET /pixel.png` on a local server. `EventRow` already sets `textFormat: Text.PlainText`; these three don't. Fix: `textFormat: Text.PlainText` on the chip's StyledText, and through `CompactFigure`'s label and the bar widget's text for event titles (or plain text by default in `StyledText`, rich text opted into: a wider ui-kit change).
- **Size:** small
- **Found:** 2026-11-01, while reviewing the calendar system

### Idle dimming is forgotten across a shell reload
- **Where:** `qml/services/system/BrightnessManager.qml:92` (`_dimmed`)
- **What:** `dim` keeps each monitor's level before dimming in `_dimmed`, a plain property of the singleton. A QML reload while dimmed (an update or file change applied while the user is away, or the shell relaunched by `axiom run`) rebuilds the singleton: `_dimmed` starts empty and `detect` reads the backlight's dimmed level as its value. When the user returns, the daemon's idle resume calls `undim`, which loops over the empty `_dimmed` and does nothing: the screens stay dimmed until set by hand. Fix: keep `_dimmed` in a `PersistentProperties` that survives the reload, declared as a default child of a `Singleton` root (the root is a `QtObject` now, and a named property doesn't survive, as `DailySchedule` and `DeadlineTicker` show: [Todo and pomodoro](features/todo-pomodoro.md) › Shared plumbing).
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:brightness system

### Replacing the chat's conversation leaves its reply and attachments behind
- **Where:** `qml/services/apps/ChatManager.qml:70` (`newConversation`), `qml/services/apps/ChatManager.qml:77` (`open`), `qml/services/apps/ChatManager.qml:166` (`ask`), `qml/services/apps/ChatManager.qml:499` (`_finish`)
- **What:** `newConversation` and `open` replace the conversation but only half let go of what belonged to the old one:
  - **The reply in flight.** They call `stop()`, which sends `chat.stop` and returns; `busy` is `_replyId !== ""` and `_replyId` clears only when `chat.send` answers, later. So `ask` (`newConversation` then `send`) finds `root.busy` and `send` returns false: with a reply streaming, the launcher's `@question` (`LauncherManager.qml:451`) or `axiom ipc chat ask "…"` opens an empty new conversation and the question is gone, with no notice. When the old answer arrives, `_finish` returns at line 500 (no streaming placeholder in the new conversation) before clearing `streamingText` / `streamingThinking`, which keep the abandoned text until the next reply.
  - **Pending attachments.** A pasted image, screenshot or dropped file is copied at once into `chats/<current id>/` (with `Chat.keepConversations` > 0); both functions just set `root.attachments = []` (only `detach` runs `rm`). A conversation never sent is never in `index.json`, so neither `remove` nor the pruning in `_writeConversation` reaches its folder: paste a screenshot, click New conversation, and the screenshot stays in `~/.local/state/axiom/chats/<id>/` for good, a privacy leak as much as a disk one (the same for attachments pending at a reload, left as rare).
  Fix: one helper both call before replacing the conversation, `_letGo()`: `if (busy) { stop(); _replyId = ""; streamingText = ""; streamingThinking = ""; }` (the late answer and deltas then fail their id check) and `attachments.forEach(a => CommandManager.runDetached(["rm", "-f", "--", a.path]))`.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the chat system

### Images dropped together on the chat overwrite each other
- **Where:** `qml/services/apps/ChatManager.qml:367` (`_attachmentPath`), `qml/components/content/Chat/Chat.qml:141` (`onDropped`)
- **What:** An attachment's file is named `${Date.now().toString(36)}.${ext}` in the conversation's folder. The DropArea calls `attachFile` for each URL in one synchronous loop, and each `attachFile` computes its copy's path before its `cp` runs, so two images of one type dropped together get the same millisecond and the same path: both `cp`s write one file, the composer shows two chips of the last image, the first image is never sent, and removing either chip (`detach` → `rm -f`) deletes the file the other still points to. Fix: make the name unique as `_blank` does for ids: `${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}.${ext}` (or a counter property).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the chat system

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

### The chat builds its conversation lists and model picker while hidden
- **Where:** `qml/components/content/Chat/Chat.qml:58` (docked `ConversationList`), `qml/components/content/Chat/Chat.qml:116` (floating `ConversationList`), `qml/components/content/Chat/Chat.qml:126` (`ModelPicker`), `qml/components/content/parts/chat/ConversationList.qml:140` (`renameField`)
- **What:** qml/components/content/AGENTS.md: "a part shown in one mode only is a Loader gated on it, not `visible: false`". Chat.qml always builds two `ConversationList`s, the docked one (`visible: root.listDocked`) and the floating one (`visible: !root.listDocked && root.listOpen`), so one is always hidden and usually both; each builds a row per saved conversation (`Chat.keepConversations` defaults to 50), each row with a hidden rename `StyledTextEntry` (`visible: item.editing`). The `ModelPicker` (`visible: root.pickerOpen`) builds every preset and model row while closed. Fix: wrap the three in Loaders with `active` on their conditions (`listDocked`, `!listDocked && listOpen`, `pickerOpen`), and the rename field in a Loader on `item.editing`.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the chat system

### An attachment's thumbnail pokes past its rounded corners
- **Where:** `qml/components/content/parts/chat/AttachmentChip.qml:23` (`clip`)
- **What:** The chip is a Rectangle with `radius: Widget.radius / 2` and `clip: true`, which clips to the bounding box, so the `PreserveAspectCrop` image (inset 1 px) draws its square corners over the rounded border, in the composer and in every sent message. qml-pitfalls.md: "Rounded clipping is Quickshell.Widgets' `ClippingRectangle`". Fix: make the root a `ClippingRectangle` (with its `color` set) in place of the Rectangle and drop `clip: true`.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the chat system

### Renaming a note whose new name holds a dot drops its extension and hides it
- **Where:** `qml/services/apps/NotesManager.qml:253` (`rename`), `qml/services/apps/NotesManager.qml:236` (`createNote`)
- **What:** `rename` keeps the old extension only when the new name has no dot at all (`if (ext && !isFolder && !/\.[^.]+$/.test(base)) base += ext[0];`), while `createNote` asks whether the name ends in one of `NotesConfig.extensions`. The rename field shows the title without its extension (`NotesManager.titleOf`), so renaming "Meeting 31.10.md" to "Meeting 1.11" (or opening its rename field and pressing Enter unchanged, "Meeting 31.10") moves the file to "Meeting 1.11" with no `.md` (checked by running those two lines in node: `Meeting 1.11`). The file then matches no name filter: it leaves the note list, `allNotes`, the settings' note picker and the search, and once the module shows another note it can't be opened again from axiom. CONFIRMED. Fix: decide "has an extension" one way for both, `NotesConfig.extensions.some(ext => base.toLowerCase().endsWith("." + ext))`, in a small helper `createNote` and `rename` share.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:notes system

### A folder name holding `#` or `?` opens the wrong folder in the note list
- **Where:** `qml/components/content/parts/notes/NoteBrowser.qml:87` (`folderModel`), `qml/services/core/ThemeManager.qml:34` (the wallpaper folder's FolderListModel)
- **What:** The browser's `FolderListModel` is given `"file://" + NotesManager.absolute(…)` unencoded, so a `#` starts the URL's fragment and a `?` its query. Folder names come from the user (`createFolder` keeps both characters). Checked with qmltestrunner: a model given `file:///…/d/C#/` listed the contents of `d/C` (`names= ["x"]`), not `d/C#`. So opening a folder "C#" (or "Q&A?") shows another folder's notes, or nothing, under a breadcrumb saying "C#", and a notes folder set to such a path lists nothing at all; a `%20` in a name is read as a space. The wallpaper folder (`Appearance.wallpaperPath`, a user path too) is built the same way. CONFIRMED. Fix: build the URL from encoded segments, a new Paths helper, `fileUrl(path)`, returning `"file://" + path.split("/").map(encodeURIComponent).join("/")`, used by both models.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:notes system

### A changed notes folder keeps showing the old folder's note and saves it into the new one
- **Where:** `qml/services/apps/NotesManager.qml:440` (`_read`), `qml/services/apps/NotesManager.qml:398` (`_file`), `qml/services/apps/NotesManager.qml:366` (`onDirectoryChanged`)
- **What:** An open document's `_file` is bound to `root.absolute(doc.path)`, so when `Notes.directory` changes every open document follows to the same relative path in the new folder (`on_FileChanged: doc._follow()`). Where the new folder has no such file, `_read` keeps the old text (`if (text === null) doc.loaded = true;`, meant for a new note). A Notes module in an edge menu or on the desktop showing "notes.md" thus keeps showing the old folder's notes.md after the folder is switched to a synced vault, and the first keystroke writes all of it into the vault as notes.md. The order against `onDirectoryChanged`'s `flushAll()` is not stated either: if the binding updates first, edits less than 600 ms old are flushed into the new folder (PLAUSIBLE: QML's notify order). CONFIRMED for the kept text. Fix: on a directory change, flush every document to its old file, then reload each from the new one with a missing file reading as empty (`_file` a plain property set by `_follow()`, called from `onDirectoryChanged` after `flushAll()`; `_read` empties the text when it follows to a missing file); or have the modules release their documents and show their place's note again.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:notes system

### Typing in a note creates a linked notes folder that doesn't exist
- **Where:** `qml/services/apps/NotesManager.qml:409` (`flush`), `qml/services/apps/NotesManager.qml:302` (`refreshList`)
- **What:** notes.md: "A linked folder is never created", and the note list says "The notes folder doesn't exist" (`directoryMissing`). But a module still opens its last note (a missing file reads as an empty note) and `flush()` saves through `FileManager.write`, which writes the file "making its folders" (FileManager.qml's comment). With `Notes.directory` on a drive that isn't mounted yet (or mistyped), the first keystroke in an edge-menu scratchpad creates the whole path on the root disk; mounting the drive later hides that note under the mount. CONFIRMED by reading. Fix: when `NotesConfig.linked`, `flush()` checks the folder first (`[ -d "$1" ]` through `_run`) and keeps the edit dirty with `_fail(I18n.tr("The notes folder doesn't exist: {0}", …))` when it's gone, refreshing `directoryMissing` on the way.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:notes system

### Two toolbar edits skip the re-parse, so the editor's blocks aren't what parse() gives
- **Where:** `qml/components/methods/NoteMarkdown.qml:507` (`toggleBullet`), `qml/components/methods/NoteMarkdown.qml:447` (`toggleTask`)
- **What:** notes.md: "Every structural edit re-parses (`reparse`), so the blocks are always what `parse()` would give." `toggleBullet`'s text branch and `toggleTask`'s "add a task at the end" branch return the edited copy without `reparse`. Checked with qmltestrunner: the bullet button on a line "[ ] foo" gives a text block "- [ ] foo" that parses as a task (no checkbox, `progress` uncounted until the next structural edit); the checklist button with nothing focused in a note ending in an unclosed code fence shows a checkbox row that is plain "- [ ] " inside the fence once the note reloads. CONFIRMED. Fix: return `root.reparse(copy, focus)` from both branches, and a `tst_NoteMarkdown` row asserting, for each edit, `parse(serialize(result.doc))` equals `result.doc` (it would have caught both).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:notes system

### NotesConfig expands ~ by hand where Paths.expandHome does it
- **Where:** `qml/config/NotesConfig.qml:15` (`directory`), `qml/config/NotesConfig.qml:12` (`defaultDirectory`)
- **What:** AGENTS.md: "A path setting may hold `~`: expand it (`Paths.expandHome`) before use." `directory` trims, expands `~` and `~/` itself and keeps a `defaultDirectory` member read only there. Fix: `readonly property string directory: root.linked ? Paths.expandHome(_c.directory).replace(/\/*$/, "/") : Paths.defaultNotesPath` (expandHome trims and strips trailing slashes; `defaultNotesPath` ends in "/" already): lines 10–11 and 14–21 (10) become 1, 9 lines removed.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:notes system

### Two Bluetooth menus share one discovery scan, and one closing stops the other's
- **Where:** `qml/components/content/BluetoothDevices/BluetoothDevices.qml:44` (`updateScan`), `qml/services/system/BluetoothManager.qml:41` (`setDiscovering`)
- **What:** Each BluetoothDevices instance starts discovery when its Discover tab opens, and only if none runs (`if (want && !BluetoothManager.discovering) { BluetoothManager.setDiscovering(true); _startedScan = true; }`), and stops it when it leaves the tab or is destroyed (`Component.onDestruction: if (_startedScan) BluetoothManager.setDiscovering(false)`). With two instances (the Bluetooth widget's popout and a BluetoothDevices card on the overlay or an edge menu, or cards on two monitors): A opens Discover and starts the scan; B opens Discover, sees `discovering` and doesn't mark it as its own; A closes or goes back to Devices and stops the adapter's discovery. B stays on Discover with no scan and no scanning indicator, and nothing restarts it (`updateScan` runs only on a tab or power change), so new devices never appear. Wi-Fi solved the same problem with a consumer registry (`NetworkingManager.acquireScan` / `releaseScan`, a `ConsumerRegistry` driving a `Binding` on `scannerEnabled`). Fix: the same in BluetoothManager: `acquireDiscovery(owner)` / `releaseDiscovery(owner)` over a `ConsumerRegistry`, and a `Binding` on `adapter.discovering` with `value: _discoveryRegistry.active && enabled`; BluetoothDevices acquires while `currentTab === 1` and releases otherwise and on destruction, dropping `_startedScan`, `updateScan`'s bookkeeping and the `onEnabledChanged` Connections (about 20 lines there, about 14 added in the service). CONFIRMED by reading; not run with two menus open.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the networking-bluetooth system

### The join form stays incomplete when CA file is picked without a file and the security changed
- **Where:** `qml/components/content/parts/WifiJoinForm.qml:42` (`complete`)
- **What:** `complete` ends with `&& (root.caMode !== "file" || root.caCert !== "")`, whatever the security. In the Hidden network form: pick Enterprise, open More, pick CA file (no file chosen yet), then pick WPA (or WEP, or None). The CA row is gone (`visible: root.enterprise && root.more`), but `caMode` is still "file" with no certificate, so Connect stays disabled and Enter does nothing, with nothing on screen saying why; only switching back to Enterprise and choosing another CA mode frees it. Fix: `&& (!root.enterprise || root.caMode !== "file" || root.caCert !== "")`. CONFIRMED by reading.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the networking-bluetooth system

### The VPN list's Tailscale row misreads Tailscale's errors, actions and login
- **Where:** `qml/services/system/VpnManager.qml:42` (`rows`), `qml/services/system/VpnManager.qml:44` (`rows`), `qml/services/system/VpnManager.qml:105` (`up`), `qml/services/system/VpnManager.qml:234` (`statusText`), `qml/services/apps/TailscaleManager.qml:133` (`openLogin`), `qml/services/apps/TailscaleManager.qml:163` (`_run`, `lastError`)
- **What:** VpnManager builds the Tailscale row from TailscaleManager by its own rules, and gets three of them wrong. (1) Errors: the row's error is `TailscaleManager.lastError !== "" ? "failed" : ""`, which `statusText` reads as "Couldn't connect". `lastError` is set by any Tailscale call (`tailscale.up`, `down`, `switch`, `set`, …) and kept until the next one, and it already holds the reason in the user's words ("Your user can't change Tailscale: allow it with Grant access.", "Access wasn't granted.", "Tailscale isn't available."). So on a machine where the user isn't Tailscale's operator (Tailscale's default), clicking the row in the VPN popout, the Wi-Fi menu or `/vpn` reads "Couldn't connect" with no hint that Grant access (only in the Tailscale module) fixes it; and a refused exit-node change in the Tailscale module while connected shows the row "Connected" in the error colour (`VpnRow.failed` is `error !== ""`, unlike the NetworkManager rows, whose error counts only while off) until the next Tailscale call. (2) Actions: the row's state is `TailscaleManager.busy ? (connected ? "disconnecting" : "connecting") : …`, and `busy` is true for every action (`pending !== ""`): switching account, Add account (`tailscale login`, up to 15 s), an exit node, a pref, Grant access (until the polkit dialog closes). During any of these the row reads "disconnecting" while nothing disconnects, and `toggle` ignores clicks on it (`row.state === "disconnecting"`, line 92). (3) Login: `up` calls `TailscaleManager.openLogin()` whenever `needsLogin`, and `openLogin` opens only a non-empty `authURL`. After a logout tailscaled is `NeedsLogin` with no `AuthURL` until a login starts, so clicking the row in the VPN popout, the Wi-Fi menu or the Vpn widget does nothing; the Tailscale panel handles that very case (`onTriggered: TailscaleManager.authURL ? TailscaleManager.openLogin() : TailscaleManager.connect()`, `qml/components/content/Tailscale/Tailscale.qml:440`). CONFIRMED by the code. Fix, in the row and TailscaleManager together: (1) set the row's error only while it's off (`!TailscaleManager.connected && TailscaleManager.lastError !== ""`), carry the text (`"message": TailscaleManager.lastError`) and let `statusText` end with `return row.message || I18n.tr("Couldn't connect")`; (2) read the action itself (`TailscaleManager.pending === "tailscale.down" ? "disconnecting" : TailscaleManager.pending === "tailscale.up" ? "connecting" : …`), or have TailscaleManager expose `connecting` / `disconnecting`; (3) move the panel's choice into TailscaleManager (`function logIn() { authURL ? openLogin() : connect() }`) and call it from both places.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:vpn and tailscale systems

### The panel's relative times go stale while Tailscale's state stays the same
- **Where:** `qml/components/content/Tailscale/Tailscale.qml:46` (`now`, `keyDays`), `qml/components/content/ClaudeUsage/ClaudeUsage.qml:22` (`now`)
- **What:** `now` and `keyDays` are re-read only when `TailscaleManager.peers` is reassigned (`void TailscaleManager.peers; return Date.now();`). The daemon's topic hub pushes a state only when its JSON changed (`backend/internal/topics/topics.go:344`, `if bytes.Equal(data, t.last)`), and `Parse` keeps only the peers' online/active/relay/last seen/traffic fields. On a quiet tailnet (all peers offline or idle), nothing changes between polls. A module left on the desktop or in an edge menu then keeps saying "Offline · seen 3m ago" for hours, and the key-expiry warning appears only at the next unrelated change after the 7-day mark. ClaudeUsage's `now` is built the same way, though its accounts' `fetchedAt` changes at every fetch, so it lags by one fetch interval at most. PLAUSIBLE: what's unproven is whether an idle tailnet's parsed state really repeats byte for byte; to settle it, compare two `tailscale status --json` runs parsed a minute apart on a connected, idle tailnet. Fix: drive the times from a minute clock, as Notifications does (`SystemClock { id: clock; precision: SystemClock.Minutes }`, `readonly property real now: clock.date.getTime()`), and compute `keyDays` from `root.now`.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the tailscale system

### The Network card shows Tailscale's raw state, untranslated
- **Where:** `qml/components/content/Network/Network.qml:24` (`tailscale`), `qml/components/content/Tailscale/Tailscale.qml:36` (`stateLabels`)
- **What:** With `VpnConfig.showTailscale` off, the Network card writes "Tailscale · Running 100.x.y.z" from `TailscaleManager.backendState` as is: "NeedsLogin", "NoState" and the like appear in English camel case. Only the Tailscale panel maps the states to `I18n.tr` labels (`stateLabels`), and only the panel can use that map. Fix: move `stateLabels` and `stateText` into `TailscaleManager` and read the manager's `stateText` in both.
- **Size:** trivial
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

### Hot corners' action list is a hand-kept copy of the keybind one
- **Where:** `qml/config/schema/sections/HotCorners.yaml:30` (`action`), `qml/config/schema/sections/HotCorners.yaml:104` (`argument`), `qml/config/schema/definitions/common/Keybind.yaml`, `tests/tst_BindActions.qml:83` (`test_hotCornerActionsAreTheAxiomActions`)
- **What:** The hot corner's `action` enum (35 lines) is the actions table's `ipcActions` keys plus `exec`, its `x-enumLabels` (35 lines) are word for word the Keybind definition's labels for those actions (a script comparing the built schema found no difference), and the argument's `x-showIf` list (15 lines) is the actions whose template has `{0}`, plus `exec`. All three are kept by hand and only a test (7 lines) catches drift, so every new axiom action is added in three more places. AGENTS.md: "Prefer a new schema annotation to a hand-kept list". Fix: let the schema assembler (`backend/internal/schema/yamlsrc`) fill an `action` marked e.g. `x-axiomActions: true` from `table.json` (`ipcActions` + `exec`, labels from the Keybind definition's `x-enumLabels`) and its argument's `x-showIf` from the templates; this removes the 85 schema lines and the test, for an assembler rule and its Go test.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the hot-corners system

### Re-applying a community setup over its edited copy never shows Applied
- **Where:** `qml/services/apps/CommunitySetupsManager.qml:37` (`applied`), `backend/internal/saved/saved.go:651` (`apply`)
- **What:** Apply setup `foo` (saved as the copy `community-foo`), change the look, then apply `foo` again to get it back: `keep` saves the edits into `community-foo` as the user's (`s.save(into, "", "")`, no longer `kindCopy`), so `freeName(Sanitize(snapshot), true)` skips it and saves the result as `community-foo 2`, active with `activeSource` `foo`. `applied` requires `SavedConfigsManager.active === _snapshotPrefix + source`, so it stays "" and the tile never shows **Applied**, though the doc says the chip shows while the setup's saved config is active and unchanged. CONFIRMED by reading both sides. Fix: accept the numbered copy, `const name = SavedConfigsManager.active; return source !== "" && (name === _snapshotPrefix + source || name.startsWith(_snapshotPrefix + source + " ")) && !SavedConfigsManager.modified ? source : "";` (an example or import never has a `community-` name, so the prefix still keeps them apart).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the community-setups system

### IPC community apply does nothing until the catalog was read
- **Where:** `qml/services/apps/CommunitySetupsManager.qml:331` (`apply`), `qml/services/apps/CommunitySetupsManager.qml:125` (`apply`)
- **What:** The doc says the `community` target "exists before the gallery is opened", with `apply <id>`. But only `list` calls `root.open()`; `apply` goes straight to `root.apply(id, false)`, where `root.setup(id)` searches `_setups`, which is `[]` until `open()` or `refresh()` read an index. So `qs ipc call community apply foo` in a fresh session (gallery and launcher not used yet) returns silently, sets no status and logs nothing, even with the catalog cached; an unknown id is equally silent. CONFIRMED. Fix: in the IPC `apply`, call `root.open()` first (it reads the cached index synchronously through `FileManager.read`), and `console.warn` an id `setup()` doesn't find.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the community-setups system

### Turning the gallery on while its card is shown leaves it empty
- **Where:** `qml/components/views/Settings/CommunitySetupsCard.qml:37` (`Component.onCompleted`), `qml/services/apps/CommunitySetupsManager.qml:46` (`open`)
- **What:** The card calls `CommunitySetupsManager.open()` once, when built; with `CommunitySetups.enabled` off, `open()` returns at once. The card's description then says "Turn on Browse community setups below to see the gallery." Doing so shows the search field and the empty grid, but nothing calls `open()` again (the card is a `StreamedLoader` built once per page, `always: true`, and nothing watches `enabled`), so no catalog is read, `loading` and `loaded` stay false and the status line is empty: a blank gallery until **Refresh** or reopening the page. CONFIRMED from the code (the card isn't rebuilt by a setting change); a screenshot would show it. Fix: in the card, `Connections { target: CommunitySetupsManager; function onEnabledChanged() { CommunitySetupsManager.open(); } }` (open() is a no-op while off).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the community-setups system

### community.fetch isn't sent again after a daemon re-exec, and blanks every thumbnail
- **Where:** `qml/services/apps/CommunitySetupsManager.qml:258` (`_fetch`), `qml/services/apps/CommunitySetupsManager.qml:237` (`_fetchThumbs`)
- **What:** `BackendManager.call` documents `{ repeatable: true }` for "a call the caller knows is safe to send twice: a whole-file write, a fetch"; `community.fetch` is exactly that (hash-checked atomic writes, the cache skips what landed) but `_fetch` doesn't pass it. A daemon re-exec (self-update, dev rebuild) during a download fails the call `unavailable`: an apply ends "could not be downloaded", and a thumbnails run sets `root._thumbs = thumbs` with none ok, so every thumbnail already shown disappears until the next Refresh. CONFIRMED (BackendManager.qml:402-423 fails non-repeatable calls on a lost connection). Fix: pass `{ "repeatable": true }` as `_fetch`'s fourth argument.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the community-setups system

### The apply's wallpaper rides in a property instead of the callback
- **Where:** `qml/services/apps/CommunitySetupsManager.qml:172` (`_applyWallpaper`), `qml/services/apps/CommunitySetupsManager.qml:140` (`apply`)
- **What:** `apply` stores the wallpaper file in `_applyWallpaper` only for `_finishApply` to read it from the callback it starts; its comment ("set once SavedConfigsManager has applied it") is also wrong (it's set before the download). Fix: `root._fetch(downloads, fetched => root._finishApply(fetched.failures, wallpaper))` and `_finishApply(failures, wallpaper)`: removes the property with its comment (3 lines) and the assignment (1). 4 lines.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the community-setups system

### Switching an open picker between screenshot and recording keeps the first kind's folder and sound
- **Where:** `qml/services/apps/ScreenshotManager.qml:227` (`setRecordMode`), `qml/services/apps/ScreenshotManager.qml:135` (`_start`), `qml/services/apps/ScreenshotManager.qml:295` (`record`), `qml/services/apps/ScreenshotManager.qml:306` (`record`)
- **What:** `_start` picks the save folder once, from the kind it starts with: `root._directory = kind.startsWith("record") ? root.recordingFolder : root.folder;` (line 135). `setRecordMode` (R or the picker's Screenshot / Record switch) only rewrites `request.kind` (lines 231-233), and both `finish` (line 189) and `record` (line 295) save into `_directory`. With `Screenshots.recordingFolder` set: take a region screenshot, press R, pick: the recording is saved in the screenshot folder, so the ScreenRecord card's recent list (which lists `recordingFolder`) never shows it, against the doc's "Recordings go to `recordingFolder`". The other way, `/record` then R then a pick saves the PNG into the recordings folder. The sound leaks the same way: `_recordAudio` is reset only inside `record` (line 306), so a ScreenRecord card's region recording with System sound that is switched to a screenshot leaves `"system"` set, and the next screenshot picker switched to Record records the system's sound though nobody asked for it this time; a recording picker cancelled with Escape leaves it the same way (`cancel` doesn't reset it either). CONFIRMED by reading (no shell needed). Fix: drop `_directory`: `finish` saves into `root.folder` and `record` into `root.recordingFolder` (`_start` mkdirs both), and `_start` sets `_recordAudio` (`startRecording` passes its choice, every other start `"none"`), so no picker inherits an earlier one's sound, a cancelled one's included. Removes line 80 (`property string _directory`).
- **Size:** small
- **Found:** 2026-11-01, while reviewing the screenshots-recording system

### Clicking an older capture's notification opens the newest capture
- **Where:** `qml/services/apps/ScreenshotManager.qml:500` (`Component.onCompleted`, the handler), `qml/services/apps/ScreenshotManager.qml:194` (`finish`), `qml/services/apps/ScreenshotManager.qml:426` (`_recorded`)
- **What:** Every screenshot and recording notification carries the same desktop entry (`axiom-screenshot`), and its one handler opens `root._lastPath`, which each new capture overwrites (lines 194 and 426): `CommandManager.runDetached(["xdg-open", root._lastPath])`. Take screenshot A, then screenshot B (or finish a recording), then click A's notification in the notification centre: B opens. The doc promises "(click opens it)" for each. CONFIRMED by reading. Fix: open what the clicked notification names: the handler gets the entry (`NotificationManager.openApp` passes it to `root._handlers[id]`), whose `appIcon` already is a screenshot's path (`"icon": path`); a recording passes its path the same way (or as a body/hint the handler reads); `_lastPath` and its two assignments go (3 lines).
- **Size:** small
- **Found:** 2026-11-01, while reviewing the screenshots-recording system

### ScreenRecord's recording time repeats StopwatchClock.format, and the bar's differs past an hour
- **Where:** `qml/components/content/ScreenRecord/ScreenRecord.qml:49` (`durationText`), `qml/components/bar/widgets/ScreenRecord/ScreenRecord.qml:17`, `qml/components/methods/StopwatchClock.qml:283` (`format`)
- **What:** The card formats `recordingElapsed` with its own `durationText` ("1:05", "1:02:03"; lines 48-54, 7 lines), the bar widget with a third inline copy that has no hours: `${Math.floor(root.elapsed / 60)}:…` shows "65:00" where the card shows "1:05:00" for the same recording. `StopwatchClock.format(ms)` already makes "mm:ss" / "h:mm:ss" and is tested. Fix: both use `StopwatchClock.format(ScreenshotManager.recordingElapsed * 1000)`; `durationText` goes (7 lines) and the bar matches the card (both then pad the minutes, "01:05", as the timer and stopwatch do).
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the screenshots-recording system

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
