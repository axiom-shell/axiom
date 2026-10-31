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

### A tray menu logs an undefined menu handle
- **Where:** `components/content/parts/TrayMenuList.qml` (`menuOpener`)
- **What:** Using the tray logged `@components/content/parts/TrayMenuList.qml[45:5]: Unable to assign [undefined] to qs::menu::QsMenuHandle*`: `QsMenuOpener.menu` is bound to `root.menu` while that's still (or again) undefined, likely as a menu opens or closes. Seen once in the live log (not reproduced).
- **Size:** small
- **Found:** 2026-10-30, while moving the Wi-Fi popout's buttons

### The onboarder's Integrations page names Hyprland's tools everywhere
- **Where:** `components/surfaces/onboarding/pages/IntegrationsPage.qml`
- **What:** Under sway and niri the Idle cards say "Remove any hypridle you start yourself" and "such as hypridle", the hint for your own idle daemon shows a `~/.config/hypr/hypridle.conf` block, and the polkit cards name hyprpolkitagent. These should name the compositor's usual tools (swayidle, …) or stay neutral.
- **Size:** small
- **Found:** 2026-10-30, while reworking the onboarder

### The onboarder's Integrations page is too long for one step
- **Where:** `components/surfaces/onboarding/pages/IntegrationsPage.qml`, `services/session/OnboardingManager.qml` (`_pages`)
- **What:** One step holds updates, clipboard history, idle (with its four timeouts), the lock screen, polkit, the login screen (with its install), then every theme integration with its hookups: by far the longest page, mixing decisions that take something over with optional app colours. Proposal: split it into a "System" step and an "App colours" step (a page id, and `version` stays, since nothing new is asked).
- **Size:** small
- **Found:** 2026-10-30, while reworking the onboarder

### The Look page offers Hyprland's wallpapers under any compositor
- **Where:** `components/surfaces/onboarding/pages/LookPage.qml`, `services/ui/WallpaperManager.qml` (`hasHyprlandWallpapers`)
- **What:** With the wallpaper folder missing, the Look page offers "Use Hyprland's wallpapers" (and the notice names them) whenever Hyprland's package left its wallpapers in a data dir, under sway and niri too. Harmless (the images work), but it reads oddly off Hyprland.
- **Size:** trivial
- **Found:** 2026-10-30, while reworking the onboarder

### A VPN's password request can go unseen
- **Where:** `services/system/VpnManager.qml` (`secretRequest`), `backend/internal/daemon/vpn.go` (`OnSecret`)
- **What:** axiom takes NetworkManager's secret request whenever the shell is connected, but only a `VpnRow` shows it: the Wi-Fi menu (with its VPN section), the VPN popout or a VPN card. A VPN needing a password brought up from `/vpn` in the launcher, or by a click on a `Vpn` widget in an edge menu, shows its field nowhere: the row reads "Connecting…" until NetworkManager gives up, and nm-applet is never asked. Open: whether the request opens the VPN popout, sends a notification that opens it, or axiom answers `NoSecrets` while no row is shown (so another agent asks).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the VPN branch

### BlurManager.paused reads undefined on a reload
- **Where:** `services/ui/BlurManager.qml` (`paused`)
- **What:** A hot reload logged `@services/ui/BlurManager.qml[36:3]: Unable to assign [undefined] to bool` once (2026-10-30, after saving QML files under `components/content/`; neither file the binding reads had changed). `paused` is a `&&` chain whose last term is `General.outputs.some(…)`; something in it (likely a singleton not ready yet during the reload, or `Appearance.blurPauseFullscreen`) reads undefined for a moment. Harmless (it settles at once), but it's log noise; `=== true` on the term that can be undefined, or `!!` on the chain, would silence it once the term is found.
- **Size:** trivial
- **Found:** 2026-10-30, while building the network popout's VPN fold and connection details

### A dev build during a branch switch re-execs onto the defaults
- **Where:** `backend/internal/daemon/dev.go` (`watchSource`, `build`), the re-exec's config load
- **What:** On 2026-10-30, `git switch main` followed 3 s later by `git pull` (main at config version 82, then 84). The source watch kicked a build of the v82 tree. The pull's changes reached the old process while that build ran, and its kick died with the process when the build re-exec'd. The new image (`the tree's schema isn't the one this binary was built with (fine in dev mode)`) knew version 82, refused the v84 config.json (`version: 84 is newer than this axiom knows (82): update axiom`) and logged `the config doesn't load: running on the defaults, saves blocked until it's fixed`. The shell came up on the defaults until the next build. config.json itself stayed untouched. Two gaps: a kick that arrives during a build should build again rather than re-exec into the stale binary (or the new image should check whether the source is newer than itself), and a re-exec that can't read the config should keep the config the old image had running (the shell's message already claims it keeps the last good config).
- **Size:** small
- **Found:** 2026-10-30, while investigating the shell on default config after merging the notifications revamp

### A shared file older than v71 resets niri's hot corner
- **Where:** `backend/internal/share/zz_generated_movedkeys.go` (`movedKeys`), `backend/internal/migrate/steps/v82.go`
- **What:** `movedKeys` lists `Compositor.niri.hotCorner` (moved into shared files at v71), but step v82 made niri's hot corner an axiom one and the key is gone from the schema. `KeepMovedKeys` looks it up in the user's current config, finds nothing, and a format-1 shared file older than v71 applies without keeping the user's hot corner. The v82 shape isn't a plain rename (it became a `HotCorners` item), so the list can't just name a new path.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the notifications revamp branch (its v83 rename had the same gap, fixed there)

### A custom Ring element logs an undefined `inside` on load
- **Where:** `components/content/parts/custom/elements/Ring/CustomRing.qml` (`inside`)
- **What:** The live shell logs `CustomRing.qml[17:3]: Unable to assign [undefined] to QString` after a reload: `root.options.inside` is read before the element's options carry it (seen on main after row 17, with a custom widget's Ring element on screen). The ring draws once the options arrive, but the log isn't clean.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the hot corners branch (row 16)

### A hot corner can't close what covers it
- **Where:** `shell/HotCorners.qml` (its layer, `LayerStack`), `docs/dev/features/hot-corners.md`
- **What:** Hot corners sit on the Top layer, so a surface on the `Overlay` layer (axiom's workspace overview, a full-screen overlay page) covers the corner pixel: a toggling action opens it from a corner but can't close it there. niri's own corner toggles its overview; the migrated corner (v82) does that only while `WorkspaceOverlay.compositorOverview` is on. Whether a corner should stay live over Overlay-layer surfaces is the maintainer's call.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the hot corners branch (row 16)

### Close on outside click differs on Hyprland since the overlay ignores its grab ending
- **Where:** `components/hosts/overlay/OverlayPanel.qml` (`grab`, `onClickedOutside`), `services/compositor/FocusGrab.qml` (`clickedOutside`)
- **What:** With `Overlay.closeOnOutsideClick` on, the overlay now closes on its empty background (`backgroundClicks`) everywhere, and, without a native grab (sway, niri), on a press on any screen's backdrop: another monitor, the screen border (its mask is empty), a floating bar's gap. On Hyprland those clicks only end its native grab, which it no longer closes on (that also fires when a popout's or the dock menu's own grab starts over it, one native grab at a time), so they leave it open, where before this change they closed it on every compositor. The maintainer decided on #211 "only where the blur backing would be": whether those places count (another monitor has no backing; the border covers it; a bar's gap shows it) decides the fix: none on sway and niri dropping `clickedOutside`, or on Hyprland a backdrop that takes the click.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the overlay and popouts plan's build (row 16)

### An open-only workspace overview bind calls a function that doesn't exist
- **Where:** `backend/internal/compositor/actions/table.json` (`calls.workspaceOverview`), `shell/WorkspaceOverlay.qml` (its `IpcTarget`)
- **What:** The bind table maps the `workspaceOverview` action's `open` call to the IPC function `show` (`render.Tables.CallFunction`), so a bind with call `open` runs `axiom ipc workspaceOverlay show`; the `workspaceOverlay` target has only `toggle`, `open` and `hide` (`docs/dev/generated/ipc.md`), so the bind does nothing. The default bind (`toggle`) is unaffected. Fix: the table's `open` names `open`.
- **Size:** trivial
- **Found:** 2026-10-29, while adding niri's own overview (row 16)

### The overlay's gaps can't be adjusted
- **Where:** `components/methods/GridPlacement.qml` (`cardSpacing`, `baseCard`, `gapOf`), `config/OverlayConfig.qml` (`boxPadding`)
- **What:** The maintainer's note: "the overlay's gaps become adjustable". The gaps are one design value, `GridPlacement.cardSpacing` = 20: the gap between modules, the margin around the grid, the overlay box's padding and the tool pages' spacing; through `baseCard` and `gapOf` edge menus, the desktop, the lock screen and the greeter are drawn as the overlay's grid scaled. Answered so far (2026-10-29): "one setting, gaps between modules and edges of the overlay page look the same". Open: the overlay's alone, or one Look & Feel setting for the overlay, lock screen, greeter and desktop with edge menus kept at today's value (the maintainer: "Menus already seem smaller"); a bigger gap shrinks the cards on a page fitted to its screen. Deferred: "defer for now, still unsure".
- **Size:** small
- **Found:** 2026-10-29, while splitting Phase 13 step 2 (row 16)

### Submenus don't always get their blur backing
- **Where:** `components/hosts/popout/SubPopout.qml` (the surface's `backed`, `parentOrigin`)
- **What:** The maintainer sees submenus (a popout's or an edge menu's) open without the blur behind them some of the time; not reproduced yet. A lead: `backed` also needs `parentOrigin` (`slot.popupScreenOrigin`, where the parent's window is on screen), so a submenu opened before that's known stays unbacked until something re-evaluates it; `onOverlayLayer` follows its host too.
- **Size:** small
- **Found:** 2026-10-29, while building custom widgets (reported by the maintainer)

### config.json replaced by rename isn't always read by the live daemon
- **Where:** `backend/internal/store/store.go` (`Watch`, `reload`)
- **What:** Twice on 2026-10-29 (dev mode on, the daemon re-exec'd between them) a config.json written to a temp file and renamed over the old one, as AGENTS.md asks, wasn't read: `axiom config status` kept its revision for 15 s and longer, and the daemon log said nothing, neither a reload nor `the config was edited into one that doesn't load`. Rewriting the same bytes in place was read at once (the revision went up). The watch is on the folder and filters by name, so a rename should reach it; not yet reproduced in a test. Related: `axiom config validate` checks against the installed binary's schema, not the running daemon's, so under dev mode it calls a config with new types invalid that the daemon accepts.
- **Size:** small
- **Found:** 2026-10-29, while testing custom widgets on the live config

### After a refused save, a draft's edits show unsaved but not live
- **Where:** `services/core/ConfigDraft.qml` (`_refusals`), `services/ui/SettingsManager.qml` (`_clearPreviews`), `services/ui/BarManager.qml` (`applyChanges`)
- **What:** When axiom refuses a save, `ConfigManager.saveRefused` makes the draft dirty again, but the editor's previews were cleared when it saved (the settings page's `draft.load()` → `_clearPreviews`; `BarManager` clears its preview once clean) and nothing sets them again: the running config shows the value read back while the editor shows the edits as unsaved, until the next edit previews them. Rare (a save axiom refuses), so left after the minimal fix (row 12).
- **Size:** small
- **Found:** 2026-10-28, while reviewing row 12's refused-save fix (backend stage 7)

### A protocol bump in dev mode leaves the installed CLI on the old protocol
- **Where:** `backend/cmd/axiom`, `config/json/backend.json` (`protocol`)
- **What:** In dev mode a Go change rebuilds and re-execs the live daemon (into `~/.local/state/axiom/dev/axiom`), but the installed `~/.local/bin/axiom` stays as it was. After a change that bumps `protocol`, every `axiom ipc` call (keybinds, scripts) fails with `this axiom speaks protocol 5, the client 4` until the user rebuilds it by hand (`go -C backend build -o ~/.local/bin/axiom ./cmd/axiom`). Dev mode's rebuild could rebuild the CLI too, or the CLI could run the dev binary when the daemon says it's newer. The live shell is hit too (seen 2026-10-28, bumping to protocol 8): the re-exec'd daemon speaks the new protocol before qs reloads `backend.json`, so every call fails (`this axiom speaks protocol 8, the client 7`) until a QML reload.
- **Size:** small
- **Found:** 2026-10-28, while sending config saves as path ops (backend stage 7)

### A word passed to an int IPC parameter is 0
- **Where:** `services/core/BackendManager.qml` (`_callTarget`), `backend/internal/ipcroute/ipcroute.go` (`Router.Call`)
- **What:** Since `IpcTarget` stopped being an `IpcHandler`, `axiom ipc` sends the command line's text and the target's typed parameters convert it: JavaScript can't read a function's parameter types, so nothing refuses a word where a number belongs. `axiom ipc brightness set loud` sets 0 % (QML turns `"loud"` into 0 for an `int`), where qs's typed call refused it with `bad_request`. Only `int` and `string` parameters exist today (`brightness` `set` / `dim` / `dimBy`, `workspaces` `nth`); a `bool` parameter would take `"false"` as true. A fix: the functions check their own input, or a parameter-type table generated from the source as `ipc.md` is.
- **Size:** small
- **Found:** 2026-10-28, while retiring the `qs ipc` fallback (backend stage 6)

### A fast chat reply can drop the shell's connection
- **Where:** `backend/internal/rpc/rpc.go` (`Conn.enqueue`, `Limits.QueueSize`), `backend/internal/daemon/chat.go` (`chat.send`'s `c.Notify`), `backend/internal/chat/send.go` (`Send`)
- **What:** Each piece of a reply is its own `chat.delta` notification (`Notify`, not latest-wins), and `enqueue` never waits: when the connection's 4096-message queue is full it logs `dropping a peer that stopped reading` and closes the connection, every topic and call in flight with it. So if the shell stops reading (its event loop busy) while a fast provider streams, once the socket buffer and 4096 deltas fill (seconds at the fastest servers' token rates, a delta per token or two), the shell's whole connection goes. Before stage 5 curl's pipe simply blocked. A fix would coalesce the deltas `Send` emits (text gathered while a push waits) or let `chat.send` wait for room instead of dropping the peer.
- **Size:** small
- **Found:** 2026-10-27, while reviewing the chat move to axiom (backend stage 5)

### AGENTS.md's funnel rule doesn't name FileManager.write and watch
- **Where:** `AGENTS.md` (Services › Quickshell.Io's side effects), `services/core/FileManager.qml` (`write`, `watch`)
- **What:** The rule lists the funnels new code uses (`CommandManager.run` / `runDetached`, `FileManager.read`, `StateManager`, `IpcTarget`) but still says to ask the daemon for "a file to watch or write", though #157 added `FileManager.write` (atomic, through `file.write`) and `FileManager.watch` (through `file.watch`) for exactly that. An agent following it could call `BackendManager` directly instead of the funnel. The line should name both, as it names `FileManager.read`.
- **Size:** trivial
- **Found:** 2026-10-28, while reviewing row 11's PRs (#155 to #158)

### With no takeovers kept, a broken config.json can still release the compositor's config
- **Where:** `backend/internal/store/store.go` (`loadInitial`, `write`, `holdTakeovers`), `backend/internal/compositor/manager/manager.go` (`ConfigChanged`)
- **What:** The store reads the takeover values from `$XDG_STATE_HOME/axiom/takeovers.json` when config.json isn't JSON at the start. With none kept (the first start of this version on a file already broken, the state folder wiped) they're unknown: a restore, import or reset is refused (`write`; decided 2026-10-28: "Refuse, clearer message", which the Saved configs page shows), and the first hand fix that loads sets them as it reads, so a fix saying detached gives back a managed config applied before. The compositor manager's own hold, deleted in row 12, kept the mode applied in that case (`AppliedMode`, or `configIsOurs` / `moduleLoaded` after a reboot) and saved it back. Accepted by the maintainer (2026-10-28, #163): with no takeovers kept, a restore is refused and a hand fix sets the takeovers as it reads.
- **Size:** needs a plan
- **Found:** 2026-10-28, while reviewing row 12's third batch

### Setting an awww wallpaper never starts awww's daemon
- **Where:** `scripts/setWallpaper.sh`, `services/core/ThemeManager.qml` (`_showWallpaper`)
- **What:** With `Appearance.wallpaperBackend` `awww` and no `awww-daemon` running, the script runs `awww query || awww init`, but awww has no `init` (`error: unrecognized subcommand 'init'`), so the wallpaper isn't set (`set -e` stops it). `ThemeManager` now runs the script through the daemon (`CommandManager.runDetached`, backend stage 6), so starting `awww-daemon` from it would no longer inherit qs's transparent huge pages opt-out ([memory](core/memory.md) › Transparent huge pages): only the script's `awww init` is left to fix.
- **Size:** small
- **Found:** 2026-10-27, while reviewing what the shell still starts as its own children (row 9)

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

### The schema root's description contradicts the annotations doc
- **Where:** `config/schema/index.yaml` (root `description`), `docs/dev/core/schema-annotations.md` (`x-hosts`)
- **What:** The root `description` is a hand-kept prose copy of the annotations list, and it has drifted: it says `x-hosts` defaults to "the first two" (overlay, edgeMenu) and that the desktop only takes modules listing it, while `schema-annotations.md` says overlay, edgeMenu and desktop are the default. It also predates many annotations in `config/schema/annotations.yaml`. It reaches `config/json/config.schema.json`, so editors showing the schema's description show the stale text. Generating it from `annotations.yaml`, or dropping it, removes the copy (planned in [config v2](core/config-v2.md)).
- **Size:** trivial
- **Found:** 2026-10-23, while reviewing the config v2 proposal

### Compact cards still build their full layout
- **Where:** `components/content/base/Card.qml` (`full`), `components/content/base/Panel.qml` (`column`, `background`)
- **What:** A module's children go into `Card.full` / `Panel.column` (a default property alias), which is only hidden while `compactContent` shows, so a compact card builds its whole layout as well as its figure. On the Tiny page (34 modules in quarter-card slots) this is most of what's left of its build: WifiNetworks about 65 ms, each ClockCalendar about 45 ms (`Built overlay module <Type> in X ms` with `--debug`). It also slows the bar popouts using those panels. A fix is an optional `fullContent: Component` on both roots, loaded only while not compact, then moving the heavy modules to it one by one (their ids are referenced from the module root, so each needs its own pass): see [streamed-building](core/streamed-building.md). The modules review (2026-10-31) found the same in Tailscale, VpnConnections, BluetoothDevices, AudioMixer, Palette, Pomodoro, Focus, Todo, Battery and TopProcesses; Notes always builds both its `tiny` figure and its editor; Disks, SystemGraphs and VolumeDials already skip part of their layout while compact. Parts hidden by mode rather than by compactness are [their own entry](#parts-shown-in-one-mode-are-built-hidden-in-every-mode-in-ten-modules-and-parts).
- **Size:** needs a plan
- **Found:** 2026-10-21, while benchmarking the overlay's opening (overlay performance overhaul)

### Unbounded lists still built in full
- **Where:** `components/content/parts/chat/ChatMessageList.qml`, `components/content/parts/chat/ConversationList.qml`, `components/content/Agenda/Agenda.qml`, `components/content/Calculator/Calculator.qml` (history), `components/content/Stopwatch/Stopwatch.qml` (laps), `components/content/parts/TodoList.qml`
- **What:** Each builds one delegate per item in a Repeater, with no limit, as `DeviceList` did before it became a ListView (52 Wi-Fi networks took 1.8 s). None showed as slow on the test machine, but they grow with use: a long chat or note becomes a slow module and popout. ListViews (or streamed sections) would build only what's in view.
- **Size:** small
- **Found:** 2026-10-21, while benchmarking the overlay's opening (overlay performance overhaul)

### Nineteen windows stay mapped on one monitor
- **Where:** `components/surfaces/border/RoundedBorders.qml`, `components/surfaces/border/BorderPanel.qml`, `components/surfaces/backdrop/ScreenBackdrop.qml`, `shell/BlurBackingWindow.qml`, `components/hosts/popout/SubmenuHost.qml`, `components/hosts/popout/EdgePopout.qml`, `components/hosts/overlay/OverlayPanel.qml`
- **What:** Each window has its own render thread and GL context (19 `QSGRenderThread`s on one niri monitor). 9 are the border (4 strips, 4 corners, the shadow); the backdrop, blur backing and border shadow are `held` only for niri's map-order stacking. About 25 more (overlay, launcher, a submenu per popout host, edge-popout bodies, power menu, overview, switcher, prompts) keep their context for the session once shown. Options: strips drawing their own corners, windows unloaded a while after they hide, one stacking anchor instead of three held windows ([layer arrangement](compositor/layer-arrangement.md)).
- **Size:** needs a plan
- **Found:** 2026-10-27, while measuring the shell's memory

### Images decoded at full size or more than once
- **Where:** `components/surfaces/wallpaper/WallpaperWindow.qml`, `components/surfaces/screenlayout/ScreenLayoutView.qml`, `components/content/NowPlaying/NowPlaying.qml`
- **What:** The wallpaper window keeps two screen-size decodes (the previous one past its crossfade, `cache: false`), about 20 MB each at 3440×1440; the desktop's `ScreenLayoutView` decodes it a third time (`cache: false`) and keeps screen-size frost captures. NowPlaying decodes album art with no `sourceSize`, twice (once under a blur layer), and a third time in its hidden strip layout's `Art` (`NowPlaying.qml:338`; popouts audit, 2026-10-30: [NowPlaying builds its strip layout and a second transport hidden in every mode](#nowplaying-builds-its-strip-layout-and-a-second-transport-hidden-in-every-mode) brings it back to two).
- **Size:** small
- **Found:** 2026-10-27, while measuring the shell's memory

### An edge menu can be bigger than its screen
- **Where:** `config/EdgeMenusConfig.qml` (`cardUnitOf`), `components/methods/GridPlacement.qml` (`menuPlacement`)
- **What:** A menu's cards are the card size on its screen (`OverlayConfig.cardUnitOn`, `Widget.cardSize` up to 150 %) times its own `moduleScale` (up to 200 %), and nothing caps the result to the screen: `menuPlacement` sizes the menu from its modules (`trackSizes`) and only places it along the edge. With a high card size and Module size (a 1080 px screen at 150 % × 200 %: cards of about 1350 px), a menu's depth or length passes the screen and the rest is cut off. A fix would shrink its cards to fit, as `screenArrangement` does for screen layouts.
- **Size:** small
- **Found:** 2026-10-21, while reviewing the sizing revamp (overlaySettingsRevamp)

### Text clips on 1080p screens
- **Where:** `components/views/Layouts/MenuOpening.qml` (the Show on screen / Show other menus buttons)
- **What:** On a 1920×1080 monitor at the default Interface scale, the edge menu editor's two buttons side by side ("Show on screen", "Show other menus", and their Hide labels) don't fit their halves of the inspector and their labels clip. Likely not the only place: much of the UI was laid out on a 1440 px screen, and since the sizing revamp text keeps its size on every monitor while panels and cards follow the screen. Wants a pass over the overlay pages and inspectors at 1080p (`scripts/dev/nested.sh` with a 1080p output), wrapping or stacking what doesn't fit.
- **Size:** needs a plan
- **Found:** 2026-10-21, while checking the sizing revamp on 1080p (overlaySettingsRevamp)

### A popout taller than the screen runs off it
- **Where:** `components/hosts/popout/BarPopouts.qml` (`popoutRoom`), `components/content/Calendar/Calendar.qml`
- **What:** Nothing keeps a bar popout's content within the screen: content taller than the room past the bar (the Calendar popout with its event editor open on a short screen, 1080 px or less with a top bar) draws its box past the screen's far side, and what's there is cut off. `popoutRoom` measures the room left, and only `StyledComboEntry`'s inline list keeps to it. A general guard would hand the content a most height (as `SubPopout.maxContentHeight` does for submenus) for it to scroll within. The tray's own menu (`content/SystemTray`, a `TrayMenuList` with no height cap or Flickable) is another case (popouts audit, 2026-10-30); [A tray submenu longer than the screen runs off it](#a-tray-submenu-longer-than-the-screen-runs-off-it) gives `TrayMenuList` the `maxHeight` this guard could set.
- **Size:** needs a plan
- **Found:** 2026-10-20, while making dropdowns in popouts open inline

### A dropdown in an edge menu card with nothing scrolling gets two rows
- **Where:** `components/reusable/StyledComboEntry.qml` (`_roomBelow`), `components/content/parts/PomodoroDial.qml`
- **What:** In a floating edge menu a `StyledComboEntry` opens inline, capped by the Flickable around it. A card with no Flickable (Pomodoro as a card, its task picker) gets the two-row minimum, and the card's rows below it are pushed out of view while it's open.
- **Size:** small
- **Found:** 2026-10-20, while making dropdowns in popouts open inline

### Surfaces touch a dead screen after the outputs go away
- **Where:** `config/General.qml` (`outputs`: whatever is built on it while no monitor is connected)
- **What:** After the monitors drop out (`qt.qpa.wayland` `There are no outputs - creating placeholder screen`, e.g. DPMS off), the log fills with `attempted to use dangling screen object` (68 lines in one session, no file named). Something holds a `ShellScreen` past its removal and reads it. Which surface it is hasn't been found yet: next step, reproduce with a nested compositor dropping its output and bisect by commenting out surfaces in `shell.qml`.
- **Size:** needs a plan
- **Found:** 2026-10-20, while reviewing the popouts system

### Saving a profile that names a new monitor can move other monitors' blocks
- **Where:** `components/methods/WorkspaceGeometry.qml` (`blockBases`), `services/compositor/CompositorManager.qml` (`_bases`, `_remapWorkspaces`)
- **What:** Blocks are numbered over the monitors the saved profiles name, sorted by output identity, so saving a profile that names a monitor no profile named before puts it among them: every monitor sorting after it gets a new base, its workspaces sit outside its block, and in the `perMonitor` and `grid` layouts its list and steps miss them (the scrolling layout lists them as borrowed, which compaction leaves) until `axiom ipc workspaces reconcile`. The same happens once on updating to row 13 where the profiles name a monitor that isn't connected. Nothing remaps when `_bases` changes; a remap from the old block order to the new one would (`remapWorkspaces` takes each monitor's `block`, one per layout today). Rare: a per-monitor layout, a newly saved monitor, and its identity sorting before a connected one. Less rare than that (the hyprland review, 2026-10-30): the Monitors inspector's Primary switch (`components/views/Monitors/MonitorInspector.qml:99`, committed at once) is a common trigger, as `WorkspaceGeometry.orderMonitors` puts the primary first.
- **Size:** small
- **Found:** 2026-10-29, while reviewing row 13 (stable workspace blocks)

### A remap runs at startup, from the layout before the config loaded
- **Where:** `services/compositor/CompositorManager.qml` (`_appliedLayout`, `_remapTimer`, `onBlockSizeChanged`)
- **What:** `Component.onCompleted` records `_appliedLayout` before the config has arrived, so the config's arrival changes `blockSize` and the timer remaps from that pre-config layout to the configured one, though nothing changed. With no windows to move, the plan still sends every output to its block's matching workspace. Seen 2026-10-30 under Hyprland with a 3×3 grid: the session came up on workspace 10, with `[CompositorManager] remapping workspaces: 0 windows, outputs to DP-1:10` in the debug log (10 from the next entry). Fix: record the applied layout once the config is loaded, so only a real layout change remaps.
- **Size:** small
- **Found:** 2026-10-30, while investigating Hyprland starting on workspace 10

### A monitor a profile names by description gets the next block until its description arrives
- **Where:** `components/methods/WorkspaceGeometry.qml` (`blockBases`), `components/methods/HyprState.qml` (the output's `description`), `services/compositor/CompositorManager.qml` (`_bases`)
- **What:** Under Hyprland an output's description comes from Quickshell's `lastIpcObject`, which is empty until the monitors are refreshed. Until then a profile rule naming the monitor by `desc:` matches nothing: the rule keeps block 0 as an unplugged monitor and the connected monitor falls in among the unknown ones, block 1. With one monitor and a 3×3 grid that's ids 10–18 instead of 1–9, so anything going to the output's workspaces in that window lands in the wrong block (the startup remap above sent DP-1 to 10, and it stayed there when the base went back to 1). Fix: refresh the monitors before `_bases` is trusted, or match an unplugged rule's `label` against the connector name while the description is empty.
- **Size:** small
- **Found:** 2026-10-30, while investigating Hyprland starting on workspace 10

### Calendar times in a Windows zone name with no VTIMEZONE read as local time
- **Where:** `backend/internal/calendar/ical/zone.go` (`Zones.With`), `backend/internal/calendar/calendar.go` (`New`'s `Lookup`)
- **What:** A TZID the zone database doesn't know is read only from the object's own VTIMEZONE. The Python helper this replaced (icalendar's `tzp.timezone`) also mapped a Windows zone name (`Pacific Standard Time`, about 140 of them in its `WINDOWS_TO_OLSON` table) and a "globally unique" `/vendor/…/Europe/Berlin` TZID to the IANA zone without one. An event naming such a zone with no VTIMEZONE beside it (rare: Outlook's feeds and invitations carry theirs) now shows at its wall time read as local time, off by the zones' difference. A fix is the CLDR windowsZones table and the prefix strip in `Lookup`; whether the rare case is worth the table is the maintainer's call.
- **Size:** small
- **Found:** 2026-10-27, while reviewing the calendar port (roadmap row 8)

### The calendar doc's Files header leaves out its page
- **Where:** `docs/dev/features/calendar.md` (its `Files:` header), `components/views/CalendarPage/CalendarPage.qml`
- **What:** `CalendarPage.qml` is the only code file no doc's `Files:` header lists (`.claude/skills/review-system/scope.py --orphans`), though `calendar.md` describes it in its text. So `check_doc_drift.py` never flags the doc when the page changes, and a review of the calendar feature doesn't see the page.
- **Size:** trivial
- **Found:** 2026-10-19, while building the review-system skill

### A bar popout's stroke flashes off its fill switching content on niri
- **Where:** `components/hosts/popout/BarPopouts.qml` (`shownBoxWidth`/`shownBoxHeight`, the box gliding to new content), `shell/BlurBackingWindow.qml` (its fill), `components/hosts/popout/SwitchStill.qml`
- **What:** With blur on under niri, a bar popout switching to another widget's content in the same window shows its old stroke cutting into the box for a frame or two as it resizes: the stroke is the popout's window's, the fill the blur window's, and niri shows the two windows' frames out of step (no `supports.layerFrameSync`). Tried and reverted (2026-10-18), neither changing what the maintainer saw: holding the switch until the popout's window had drawn the new content twice (`SwitchStill`, its window's `frameSwapped`), and drawing the popout's stroke in the blur window with its fill (a stroke-only `AttachedSurfaceCopy` over the fills, the popout's own stroke transparent). That the second didn't help suggests the stroke isn't what's late: perhaps the popout's content, its clip, or the blur region. Next: log each window's `frameSwapped` with what it drew, during a switch.
- **Size:** small
- **Found:** 2026-10-18, while adding niri's blur


### The Layouts canvas logs null reads as it's torn down
- **Where:** `components/views/Layouts/CanvasModule.qml` (`editor`, `carried`, the label and icon bindings), `components/views/Layouts/GridCanvas.qml` (its `CanvasModule` Loader)
- **What:** Tearing down a page with a layout canvas (a reload, or the overlay closing after moving between pages) logs a burst of `TypeError: Cannot read property 'editor' of null` from `CanvasModule.qml[25:-1]`, then `draggingKind`, `moduleIcon`, `moduleLabel`, `dragging` of null, once per module: `dragLayer` is gone before the modules' bindings stop. Likely `root.dragLayer?.editor` at the source (`editor`), with the other reads following it.
- **Size:** small
- **Found:** 2026-10-29, while screenshotting editor pages for the form row look

### Keybind sections log null reads as they're torn down
- **Where:** `components/content/parts/KeybindSection.qml` (`section`, `items`, the folded count), `components/methods/KeybindFilter.qml` (`sectionKey`)
- **What:** Tearing down the Keybinds page or the Cheatsheet (a reload) logs a burst of `TypeError: Value is null and could not be converted to an object` from `KeybindSection.qml` (lines 20, 62, 67, 75, 82, 145) and `KeybindFilter.qml[14:-1]`, about 200 lines: the delegates' `section` goes null before their bindings stop. Guarding the reads of `root.section` (and `sectionKey`'s `section`) at the source would quiet it.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the bar display styles branch

### A custom layout's element rect reads an undefined place
- **Where:** `components/content/parts/custom/CustomLayout.qml` (the `CustomElement` delegate's `r`), `components/methods/CustomWidgetData.qml` (`rect`)
- **What:** The live shell logs `CustomWidgetData.qml[649:-1]: TypeError: Value is undefined and could not be converted to an object` after a reload: the delegate passes `element.place` while its `element` is still the `({})` stand-in (or past the end of a shrunk `elements`), and `rect` reads `place.x`. `rect` returning an empty rect for no place, or the delegate waiting for one, would quiet it.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the bar display styles branch

### Read-only daemon calls fail across a dev re-exec
- **Where:** `services/compositor/NiriManager.qml` (`_request`), `services/session/GreeterManager.qml` (`check`), `services/core/BackendManager.qml` (`call`'s `repeatable`)
- **What:** A dev-mode re-exec (a rebase touching `backend/` test files under the live session, 2026-10-29) logged `[NiriManager] "Outputs": the connection to axiom closed` and `[GreeterManager] check: the connection to axiom closed`: both are reads, safe to send twice, but don't pass `{repeatable: true}`, so the call in flight fails instead of waiting for the next hello. Passing it for read-only niri requests and `greeter.status` would quiet it.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the bar display styles branch

### Nested Hyprland acknowledges a lock too late for axiom lock
- **Where:** `backend/internal/lockscreen/lockscreen.go` (`Options.Confirm`, `Locker.Lock`)
- **What:** In a nested Hyprland (`scripts/dev/nested.sh hyprland`) the compositor takes about 5 s to acknowledge the session lock (`WlSessionLock.secure`), past `Lock`'s 3 s wait, so `axiom lock` restarts the shell locked and then fails: `the shell didn't confirm the lock: starting it locked`. Pre-existing; seen while fixing the lock surviving a reload (2026-10-29). Unknown whether a real Hyprland session is ever that slow; check, then either wait longer under Hyprland or confirm on the lock surfaces alone.
- **Size:** small
- **Found:** 2026-10-29, while fixing the lock screen surviving a reload

### Quickshell's wlr screencopy crashes the shell on niri
- **Where:** `services/apps/ScreenshotManager.qml` (`grimFrames`, the workaround), `components/surfaces/screenshot/ScreenshotPickerWindow.qml` (its `ScreencopyView`); the bug is Quickshell's
- **What:** Without ext-image-copy-capture (niri 26.04 has only wlr-screencopy), Quickshell's wlr screencopy binds a second `wl_output` of its own (`WlrScreencopyContext::OutputTransformQuery`, a `QtWayland::wl_output`; still so in upstream master). niri then sends `wl_surface.enter` for it to every surface; Qt takes it for one of its screens (`QWaylandScreen::fromWlOutput` casts it) and keeps a bogus screen in each surface's list. The next `enter`/`leave` on such a surface crashes in `QWaylandWindow::handleScreensChanged` → `QPlatformScreen::screen()` (at once with a popout open, which unmaps as the picker opens). WAYLAND_DEBUG: `bind(46, "wl_output", 3, …)` beside `zwlr_screencopy_manager_v1.capture_output`, `wl_surface.enter(wl_output#198)` on every surface, then `axiom-edge-popout`'s surface `leave(wl_output#19)` and the crash. Worked around: niri has no `supports.outputCapture`, so the picker's frame is grim's. Left: report it upstream (awaiting a second person to confirm), then drop the workaround once fixed. Sway and Hyprland 0.55 keep `outputCapture` (Hyprland checked by hand: no crash with a popout open).
- **Size:** small
- **Found:** 2026-10-18, while debugging the screenshot crash with a popout open

### WorkspaceStrip's Grid briefly has more items than cells
- **Where:** `components/bar/widgets/Workspaces/WorkspaceStrip.qml` (the `Grid`, `id: layout`)
- **What:** The log shows `Grid contains more visible items (2) than rows*columns (1)` after a reload. `shown` counts `activeStrip.visible`, so for a moment the Grid's `rows`/`columns` lag a child becoming visible; likely harmless (the next layout pass fits), but it warns.
- **Size:** small
- **Found:** 2026-10-18, while auditing the community setups gallery

### A model of size -1 when the overlay grid resizes
- **Where:** `components/hosts/overlay/OverlayPages.qml` (around the `grid` unit change; the model itself not found yet)
- **What:** The log shows `Model size of -1 is less than 0` right after `Overlay card unit 572 for 3376x1231` (the overlay's first sizing on a monitor), five times in one session. Opening the Themes or Settings page again didn't repeat it, so it's likely a Repeater or Grid whose count is worked out from a size that is still 0 or unset at that moment.
- **Size:** small
- **Found:** 2026-10-18, while adding the community setups gallery

### install.sh still installs the rest of a feature whose COPR was declined
- **Where:** `install.sh` (the declined-COPR loop after the COPR prompts)
- **What:** Declining a COPR on Fedora marks each feature with a package from it as skipped, but drops only that COPR's packages: the feature's other packages stay in the one `dnf install`. Declining `nett00n/hyprland` while setting up niri skips the login screen's feature yet still installs `greetd`. Rebuilding `packages` from the features left (and the required keys) after the prompts would fix it; test with `--dry-run` in a `fedora:latest` container.
- **Size:** small
- **Found:** 2026-10-17, while reviewing the distro-support branch for merge

### Quickshell's I3 socket warns on every reload
- **Where:** `services/compositor/SwayManager.qml` (Quickshell.I3)
- **What:** Under sway every reload of the shell logs `I3 event socket disconnected` twice (category `quickshell.I3.ipc`); events still arrive afterwards (checked in nested sway). Both come from Quickshell 0.3.2's `I3IpcListener` deleting its own connected socket, which its `stateChanged` handler reports as a disconnect: once when the old generation's listener is destroyed, once when the new one, already connected by setting `subscriptions` at creation, starts over in its `onPostReload` (so a cold start logs it once too). Axiom can't avoid it: any teardown of a connected listener logs it, and `I3.rawEvent` (the process-wide connection, which survives reloads) subscribes only to `workspace` and `output`. Nor is a log rule honest: the category also carries real faults, and sway drops an IPC client whose buffer fills, which Quickshell never reconnects, so this warning is then the only sign the event stream is dead. The fix is upstream: `I3Ipc` disconnecting its socket's signals before deleting it, and `I3IpcListener` not restarting with unchanged subscriptions.
- **Size:** trivial
- **Found:** 2026-10-16, while writing the sway backend

### niri reports no position for a tiled window, nor other apps' layers
- **Where:** `components/methods/NiriState.qml` (`windows`, `outputs`)
- **What:** niri's IPC gives no layer surface geometry, so an output's `reserved` counts only axiom's own layers (`LayerArrange.arrange`): another app's bar on niri isn't in it, and the dock centres as if it weren't there. Nor, in 26.04, does it give a position for a tiled window (`tile_pos_in_workspace_view` is null; only floating windows have one; checked 2026-10-28). So tiled windows are laid out from their column and place in it from the output's edge, without niri's scroll (`windowGeometry` stays off: no screenshot window mode; the dock hides behind a window's `cover`, its column or the whole output, which ignores struts, reserved space and `center-focused-column`).
- **Size:** small
- **Found:** 2026-10-17, while adding the niri backend

### A side edge's submenus always open away from the edge
- **Where:** `components/hosts/popout/SubmenuSide.qml` (`openToLeft`)
- **What:** On a left or right edge a submenu always opens away from that edge (`openToLeft` is `edge === ScreenEdge.Right`), so a floating menu on the right edge opens every submenu to its left, across the menu's own content side. The maintainer finds that unexpected for a right-edge menu: which way it should open there (and whether by the box's place on screen, as top and bottom edges do) needs deciding. Seen with a `Submenu` module in a right-edge floating menu in nested niri.
- **Size:** small
- **Found:** 2026-10-18, while checking shadow seams on side-edge menus

### A pill bar's end reach trails a sliding popout's wall
- **Where:** `components/hosts/popout/PillBarJoin.qml`, `components/hosts/popout/EdgePlacement.qml` (`_slideLead`), `components/bar/BarContainer.qml` (`_endReach`)
- **What:** Seen on niri with a solid bottom bar (border off) whose SystemStats popout joins the left pill bar: while the popout slides in or out, the left bar's end pill, run on to the popout's top wall, trails it by about 8px for two or three frames (below the wall while opening, above it while closing), so the two strokes and their shadows step at the left bar's inner edge. At rest they line up. Probably the other bar's window committing a frame or so after the popout's (as `AttachedSurface`'s fillet opening is taken a stroke ahead for). The end pill leads the wall by a stroke there (niri has no `supports.layerFrameSync`, `EdgePlacement._slideLead`), which helps but doesn't close the gap; sway and Hyprland move the two as one without it.
- **Size:** small
- **Found:** 2026-10-18, while fixing shadow seams where a wall runs on into another surface

### Readers read files through a service
- **Where:** `config/Paths.qml` (`packagedVersion`), `config/I18n.qml`
- **What:** Readers read only the data owners and each other (AGENTS.md › Layering), but `Paths.packagedVersion` calls `FileManager.read`, and `I18n` reads with both `FileManager.read` and a FileView of its own. Either the rule names `FileManager` as allowed in readers, or the reads move to a data owner.
- **Size:** small
- **Found:** 2026-10-26, while reviewing the repository's organization

### Three reader members nothing reads
- **Where:** `config/HyprlandConfig.qml` (`managed`), `config/LauncherConfig.qml` (`clipboardMaxEntries`), `config/WindowBehaviourConfig.qml` (`behaviour`), `scripts/config-usage-baseline.json`
- **What:** `scripts/gen_docs.py` lists them as reader members with no user (the daemon reads those settings itself: Compositor.hyprland and WindowBehaviour through `x-compositor`, the clipboard's limit by name). `HyprlandConfig` has no other member, so the whole reader can go; `WindowBehaviourConfig` too. They sit in `scripts/config-usage-baseline.json`, which only shrinks: deleting one means dropping its line there. Deletion candidates for the audits' deletion pass.
- **Size:** trivial
- **Found:** 2026-10-30, while making gen_docs.py see readers of ConfigManager.live (roadmap row 18)

### The guard reads the branch from the session's folder, not a `cd` before the push
- **Where:** `.claude/hooks/guard.py` (`check_git`, `current_branch`), `tests/scripts/test_guard.py`
- **What:** `git push … origin HEAD` (or a push with no refspec) is refused when `current_branch` of the hook's `cwd` is main, and that `cwd` is the session's folder: a `cd` earlier in the same command isn't followed (`git -C` is). An agent whose session sits in a checkout on main and pushes a branch from a worktree with `cd <worktree> && git push -q -u origin HEAD && gh pr create --label roadmap --base main --body "$(cat <<'EOF' … EOF)"` gets `don't push to main; open a PR from a branch.` (refused once on 2026-10-30, autopilot for #232; reproduced 2026-10-30 by feeding `guard.check` that command with `cwd` a scratch repository on main: refused; with `cwd` the worktree, or `git -C <worktree> push`: allowed). The plain shape from the branch's own folder passes since #241 (a heredoc body with rule-like text passes too). The workaround is an explicit `branch:branch` refspec or `git -C`. Fix: follow a leading `cd <dir> &&` into the cwd `check_git` uses, with a test case.
- **Size:** trivial
- **Found:** 2026-10-30, while recording the size before the audits (roadmap row 19)

### The daemon picks a compositor the shell may not run under
- **Where:** `backend/internal/compositor/manager/manager.go` (`New`), `backend/internal/compositor/manager/outputs.go` (`OutputsFromEnv`, `Outputs.Read`), `backend/internal/daemon/compositorsocket.go` (`greeterHandlers`, `outputHandlers`, `applyGreeter`), `components/methods/CompositorKind.qml`
- **What:** The shell picks its compositor with `CompositorKind`: with more than one of `HYPRLAND_INSTANCE_SIGNATURE` / `SWAYSOCK` / `NIRI_SOCKET` set (one left in the systemd user environment by an earlier session), the one whose process still runs wins. The daemon doesn't: `manager.New` takes the first set in a fixed order (Hyprland, niri, sway; the shell's is Hyprland, sway, niri) and `Outputs.Read`/`Apply` switch on the same order, with no process check. Under niri with a stale `HYPRLAND_INSTANCE_SIGNATURE` (or under sway with a stale `NIRI_SOCKET`) the manager is Hyprland's: `live()` needs the shell's facts to name its kind, so the layer is never applied (no binds, look or input in any mode), the status card stays on Checking, monitor profiles and `outputs.apply` go to a dead socket, and idle's `ScreenPower` fails. `applyGreeter` takes the same order. A stale variable is a case `docs/dev/compositor/README.md` names; the live session (sway) has none, so it isn't seen there. Both the compositor and the niri audits found this from the code; the niri one adds that `outputs.apply` (the Monitors page's Apply, profile switching) then fails with "no reply from Hyprland". Fix: one Go `Detect(getenv)` (CompositorKind's rule, `/proc/<pid>/comm`, as `userconf.NiriMain` and the sway reader already check their pid) used by all three, or the daemon passes the kind it picked to all three; then the daemon can start qs with only the running compositor's variable set, and `CompositorKind.qml` (68 lines), `tests/tst_CompositorKind.qml` (73) and `CompositorManager._running` go.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system (and again reviewing the niri system)

### The Translucency card reads the window look's blur object as a switch
- **Where:** `components/views/Settings/TranslucencyStatus.qml`, `config/WindowLookConfig.qml` (`look`)
- **What:** `WindowLook.blur` is the `Blur` object (`{ enabled, windowBlur, size, … }`), but the card tests `WindowLookConfig.look.blur` as a bool, so it's always truthy: the status always ends "Set in Compositor → Window look." even when the blur comes from the user's own config, and the "Set the compositor's blur" button (`root.off && !look.blur`) is never offered. Its branch would also `setValue(["WindowLook", "blur"], true)`, writing `true` over the whole object. Fix: read `blur.enabled` (a new reader property on `WindowLookConfig`, `blurSet`) and set `["WindowLook", "blur", "enabled"]`; `look` and `_lookJson` (5 lines, whose comment about applying it again is stale since the daemon applies the look) then have no reader and go.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### A failed cursor theme call keeps the theme's own name all session
- **Where:** `services/ui/CursorThemeManager.qml` (`_resolve`)
- **What:** When `cursor.theme` fails, `_resolve` takes the theme's own name as resolved and sets `_resolvedOnce`, and nothing asks again until the theme or size changes. The log has it three times across dev re-execs (`[CursorThemeManager] cursor.theme: the connection to axiom closed`): `xcursorTheme` is then the plain theme, so for a theme that needs its companion (Oxygen) the compositor, `XCURSOR_THEME` and GTK get the name without it, the very fallback the companion exists to stop, and the companion of the theme is never made. Related to, not covered by, Read-only daemon calls fail across a dev re-exec (this call writes, but is idempotent). Fix: pass `{ repeatable: true }`, and on an error keep `_resolved` as it was and retry on `BackendManager.ready`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### Backends keep stubs for calls the facade gates
- **Where:** `services/compositor/SwayManager.qml` (`withCursorPos`, `warpCursorToLayer`, `withLayerRects`, `scrollStrip`, `leaveSwitcher`), `services/compositor/NiriManager.qml` (`withCursorPos`, `warpCursorToLayer`, `withLayerRects`, `applyRemap`, `leaveSwitcher`), `services/compositor/CompositorManager.qml` (`withLayerRects`), `services/compositor/WindowSwitcherManager.qml` (`pick`), `docs/dev/compositor/contract.md`
- **What:** Deletion pass. `CompositorManager.withCursorPos` and `warpCursorToLayer` call the backend only with `supports.cursorPos` / `cursorWarp`, which only Hyprland sets, so sway's and niri's `withCursorPos` (calls back null) and empty `warpCursorToLayer` are never reached. `withLayerRects` is called ungated, but both only call back null, which the facade's no-backend branch already does. About 22 lines over the two backends. The sway review (2026-10-30) adds sway's `scrollStrip` (3 lines): the facade calls it only past `if (!root.supports.strips …) return;`, and sway has no `strips`. The compositor-parity review (2026-10-30) adds niri's empty `applyRemap` (3 lines with its comment): the facade returns before calling it when `root.supports.outputWorkspaces === true`, which niri sets. It also adds sway's and niri's empty `leaveSwitcher` (5 + 4 lines with their comments, which say "Nothing to let go"): `WindowSwitcherManager.pick` calls it under `supports.switcher`, which all three set, but only Hyprland holds the switcher's keys in a mode to leave (its `axiom_switcher` submap, `switcherRelease`). Fix: delete the six gated stubs; gate `pick`'s call on `CompositorManager.supports.switcherRelease` and delete the two `leaveSwitcher` stubs (list `leaveSwitcher()` under `switcherRelease` in contract.md); make `withLayerRects` optional in the facade (`root.backend?.withLayerRects ? … : callback(null)`) and delete its two stubs; mark the three optional in contract.md › Session and input and the compositor-backend recipe.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### Small shrinks in the compositor layer
- **Where:** `services/compositor/CompositorManager.qml` (`stepWorkspace`), `services/compositor/CompositorConfigManager.qml` (`copyIncludeLines`, `copyAutostartLines`), `config/WindowLookConfig.qml` (`shadowSoft`), `components/views/Settings/CompositorStatusCard.qml`
- **What:** Deletion pass, about 12 lines. `stepWorkspace` re-derives `WorkspacesConfig.columns` and `rows` (`grid ? columns : size`, `grid ? rows : 1` equal them in every layout: `columns` is `count` and `rows` 1 outside the grid), a re-derivation of a reader's decision. `copyIncludeLines` / `copyAutostartLines` each wrap one `ClipboardManager.copyText` for one caller (the status card, which can call it itself). `WindowLookConfig.shadowSoft` is `_shadowMatched` under a second name, read once by `CompositorConfigManager._look`. Fix: use the readers' `columns`/`rows`; have the card call `ClipboardManager.copyText(CompositorConfigManager.includeLines)` and drop the wrappers; send `_shadowMatched` as a public `shadowMatched` (or keep one name).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### A trial monitor Apply that turns a monitor off drops its Keep/Revert
- **Where:** `services/compositor/MonitorManager.qml` (`onOutputsHotplugged`, `apply`, `revert`), `services/compositor/HyprlandManager.qml` (`_announce`)
- **What:** `apply()` evaluates the trial rules and sets `pending`; the hotplug handler (MonitorManager.qml:451-456) ends any pending trial (`pending = false; _countdown.stop()`), assuming the hotplug means the daemon already switched profiles. A trial whose rules disable or mirror a monitor makes Hyprland remove that output (`monitorremoved` → `outputsHotplugged`), so the trial ends itself: the prompt goes, the 15 s auto-revert is cancelled, `axiom ipc monitors revert` does nothing (`revert()` returns while `!pending`), and the trial layout stays live, unsaved. Turning the wrong monitor off is the case the revert exists for. Code path confirmed; that Hyprland sends `monitorremoved` for a rule-disabled monitor wants one nested Hyprland run (`scripts/dev/nested.sh hyprland`). Fix: end the trial only on a hotplug the trial's own rules don't explain (record the outputs `apply()` expects to stay enabled), or keep the countdown running. That makes a prompt window created while shown reachable, and `MonitorPromptWindow.qml:33` registers as modal only in `onVisibleChanged`: the fix should also register in `Component.onCompleted` (`PolkitWindow.qml:53` has the same pattern) (the hyprland review, 2026-10-30).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### A shell reload during a trial monitor Apply loses the way back
- **Where:** `services/compositor/MonitorManager.qml` (`pending`, `_revertRules`, `_revertDetails`, the `monitors` IPC `revert`)
- **What:** The trial state is plain properties (MonitorManager.qml:303-308), no `PersistentProperties`. A QML reload or a crash `axiom run` restarts within the 15 s leaves `pending` false and the snapshot gone: the countdown never reverts, and `axiom ipc monitors revert` (documented as the recovery from a layout that can't be seen) is a no-op. The unsaved trial layout stays until the next hotplug or config reload. PLAUSIBLE as a scenario (needs a reload or crash in the window; a monitor change is a common crash trigger). Fix: keep `pending`, `secondsLeft` and the two snapshots in `PersistentProperties`; for a crash, the daemon could own the trial (`outputs.apply` with a trial flag it reverts itself unless `outputs.keep` arrives).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### Restoring a saved keybind preset marks every bind new, and Revert deletes it
- **Where:** `services/compositor/KeybindEditor.qml` (`_completeBind`, `restorePreset`, `_matchOrigins`, `changedBinds`, `revertBind`), `services/core/ConfigDraft.qml` (`changed`)
- **What:** `_completeBind` (KeybindEditor.qml:101-114) builds a template and `Object.assign`s the bind onto it, so keys the template lacks (`id`, `compositor`) move to the end. Origins, the unsaved dots and the draft's dirty check all compare `JSON.stringify` text, which depends on key order. Save a preset, then Restore it unchanged: no bind matches its saved twin, every row gets an unsaved dot and origin -1, Save lights up with nothing changed, and Revert on any row calls `removeBind` ("origin < 0 → new"), deleting a bind the user never touched. Fix: keep the bind's own key order in `_completeBind` (`Object.assign({}, bind, <missing fields only>)`), or compare order-insensitively (`Utils.deepEqual`, or a key-sorted stringify) in `_matchOrigins` and `changedBinds`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### The Keybinds page goes stale after a detached-mode Save
- **Where:** `services/compositor/KeybindManager.qml` (`refreshSoon`, `_appliedBinds`, `userKeyCounts`), `backend/internal/compositor/manager/hypr.go` (`runtimeApply`)
- **What:** In detached mode the daemon re-applies binds by eval only (`runtimeApply`, no reload, so no `configreloaded`). The page re-reads Hyprland's binds only on `configReloaded`, on open, and through `refreshSoon`, whose one caller is the merge (KeybindEditor.qml:500); the Go port (dd773ed) dropped the two `refreshSoon()` calls the QML runtime layer (`RuntimeLayer.qml`) made after each apply. `_appliedBinds` follows the daemon's state at once, so the two disagree until the page reopens: move a bind from SUPER + Q to SUPER + W and Save, and SUPER + Q shows as the user's own bind (reference, key map colour, "Your compositor config uses this key" on a new bind there) while SUPER + W is missing. Fix: `on_AppliedBindsChanged: refreshSoon()` in KeybindManager (its debounce and `_readAgain` guard already absorb bursts).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The bind merge deletes an hl.bind inside a helper, losing binds it never read
- **Where:** `backend/internal/compositor/binds/hyprlua.go` (`callSite`), `backend/internal/compositor/binds/hypr.go` (`extractHypr`)
- **What:** A bind's site is the line of its `hl.bind` call (`callSite`: `GetStack(1)`, `CurrentLine`), not the top-level statement that ran it. A `user/*.lua` file binding through its own helper (`local function bindx(k, c) hl.bind(k, hl.dsp.exec_cmd(c)) end`, then `bindx("SUPER + A", "foo")` and, in a `hl.define_submap` handler, `bindx("x", "bar")`) gives one site, the helper's body, holding only the binds extract saw. Everything it saw maps, so the merge moves it and `remove` deletes the helper's `hl.bind` line: the submap's `x` bind (and any bind the helper makes from an `hl.on` handler or an untaken branch) is silently gone, with only the dated backup to recover it. Reproduced against `extractHypr`/`removeHypr` with an overlay test (no tree edits). bind-merge.md › What can move doesn't cover it. Fix: record on each `luaBind`/`luaUnbind` whether the call ran in the file's main chunk (`L.GetInfo("S", …)`'s `What` at level 1) and keep a site that didn't, with a new reason (e.g. `inFunction`); a top-level loop still moves. A test row with the file above, and a line in bind-merge.md.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### The bind merge removes an hl.unbind whether or not its bind went
- **Where:** `backend/internal/compositor/binds/hypr.go` (`extractHypr`'s unbind sites), `backend/internal/compositor/manager/manager.go` (`left`)
- **What:** Extract adds an `hl.unbind(K)` site, with no binds, when K is a moved bind's key (hypr.go:459-474), and `remove` handles it on its own, per file. `left()` takes back only the binds of failed sites, matched by file and line, so the two outcomes split: the bind goes but the unbind's file fails (`syntax`, `io`, `changed`), and the user's surviving `hl.unbind(K)` runs after axiom's module and unbinds the moved bind (the key does nothing); or the unbind goes but the bind's file fails, the re-commit restores axiom's bind on K, and the user's `hl.bind(K)` fires alongside it, which bind-merge.md › Committing and removing says can't happen. Rare: needs one file of a merge to fail. Fix: give each unbind site the keys it covers; remove an unbind site only when its keys' bind sites all went, and treat a failed unbind site in `left()` as failing those binds.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### A failed monitor profile apply is never retried for the same outputs
- **Where:** `backend/internal/compositor/manager/outputs.go` (`profileSwitch.apply`, `ProfileWatch`)
- **What:** `p.applied = key` is set (outputs.go:170) before `p.io.Apply` (:171). When Apply fails (a 5 s socket timeout from a busy Hyprland, a refused rule), the same outputs and rules count as applied, and later calls return early until a hotplug, a rules edit or a compositor reload changes the key. Both callers only log the error. In the greeter nothing resets `applied`, so its monitors keep Hyprland's own layout until something is replugged. Fix: set `p.applied = key` only once Apply returns nil.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### One refused line stops the rest of a Hyprland eval
- **Where:** `backend/internal/compositor/manager/hypr.go` (`runtimeApply`), `backend/internal/compositor/manager/outputs.go` (the Hyprland branch of `apply`)
- **What:** Two chunks are sent as one eval with no `pcall`, unlike `addLayerRules`, which wraps each rule for exactly this. `runtimeApply` (hypr.go:221-228) puts the binds, required settings, look/input/blur and strips lines first and `AXIOM_RUNTIME_KEYS = {…}` last: a look or strips line Hyprland raises on (an option this version doesn't know) leaves the binds live but unrecorded, so the next apply unbinds nothing, reads axiom's own binds as the user's, reports them in `skippedKeys` and stops managing them until Hyprland reloads (and `AXIOM_STRIPS` stays unset). `outputs.apply` joins every `hl.monitor` call into one eval (outputs.go:52), so the first refused rule leaves the monitors after it unlaid; niri's branch below sends them one at a time for that reason. PLAUSIBLE: whether `hl.config`/`hl.monitor` raise on a bad value wants one nested Hyprland run. Fix: emit `AXIOM_RUNTIME_KEYS` right after the binds and wrap the look/input/blur and strips groups each in `pcall`; wrap each `hl.monitor` in `pcall`, collect the errors and `error(table.concat(e, "; "))` at the end so the refusal is still reported.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### A user/ file with a dot in its name never loads
- **Where:** `backend/internal/compositor/render/hyprconfig.go` (`UserFilesLua`), `backend/internal/compositor/binds/hypr.go` (the extract's module name)
- **What:** The managed and released files load each `user/*.lua` as `require("user." .. name)`, and the bind extract uses the same module name. Lua's `require` turns every `.` into `/`, so `user/my.binds.lua` is looked for as `user/my/binds.lua`: it never loads (Hyprland's config errors say module not found) and the merge reports an error for it. Reproduced against the extract. Nothing warns about dotted names (docs/installation.md only says `require("user.<name>")`). Fix: load such files with `dofile` (or skip them with a reported error), and say so in config-modes.md › managed. The `dofile` fix should skip dot-files, which the managed file's `ls *.lua` never loads: `hyprFiles` (binds/hypr.go:336) has no hidden-file filter, unlike sway's and niri's (the hyprland review, 2026-10-30).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### A moved raw bind with a Lua keyword key compiles to nothing
- **Where:** `backend/internal/compositor/binds/hyprlua.go` (`luaSource`)
- **What:** `luaSource` writes a table key that looks like a name bare, keywords included (hyprlua.go:467): `{ ["end"] = 1 }` becomes `{ end = 1 }`, and NaN/Inf come out as `nan`/`inf` (nil globals). A dispatcher the merge maps to `raw` keeps that source as its argument; `DispatcherLua`'s `raw` case compiles it with `load`, which fails, so the moved bind becomes `hl.dsp.no_op()` while the user's original call is already deleted. Reproduced (`{["end"]=1}` → `{ end = 1 }`). Rare. Fix: exclude Lua's keywords from the bare form; better, `load`-check the rebuilt source at extract time and keep the site when it doesn't compile.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### A failed options read sets Hyprland's gaps to 0
- **Where:** `services/compositor/HyprlandManager.qml` (`_readOptions`, `_gapSides`)
- **What:** `_readOptions` keeps every option's old value when its reply is missing, except the gaps: `gapsOut = _gapSides(gaps) ?? gapsOut` relies on `_gapSides(null)` being null, but `String(option?.css ?? "").trim().split(/\s+/)` is `[""]` → `[0]`, so it returns `{0,0,0,0}`. A failed batch (the 5 s `unavailable` while Hyprland is busy, e.g. right after a reload) gives null for every option, so `gapsOut` drops to 0 and bars that subtract it jump until the next good read. Fix: `if (typeof option?.css !== "string") return null;` first; better, move `_gapSides` into `HyprState` with test rows for a null reply and 1, 2 and 4 values.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### A workspace slide throws when animations go off between its legs
- **Where:** `services/compositor/HyprlandManager.qml` (`_nextSlide`, `travel`, `travelingTo`)
- **What:** `travel` checks `_workspaceAnim` for the first leg only; `_nextSlide` re-reads it per leg and uses `anim.bezier`/`anim.style` unchecked (HyprlandManager.qml:517-534). An options read landing in the timer gap between the two legs of a diagonal grid switch with animations now off (`animations:enabled` false, the `instant` preset) makes the second leg throw a TypeError: the switch stops at the corner workspace, and `travelingTo` keeps the first leg's id, so `CompositorManager` plans the next switch from it and `_compaction` keeps deferring (`travelingTo > 0`) until another travel resets it. Rare. Fix: snapshot `anim` into each step in `travel`, or in `_nextSlide` dispatch the rest directly and reset `_slideSteps`/`travelingTo` when it's null.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Direct Hyprland dispatches can overtake queued Lua
- **Where:** `services/compositor/HyprlandManager.qml` (`sendWindowToWorkspace`, `activateWindow`, `travel`, `_eval`)
- **What:** Workspace and window actions use two routes nothing orders: `Hyprland.dispatch` (Quickshell's socket, at once) and `_eval` (queued behind any Lua, through the daemon). A slide's chunk queued behind a compaction or remap chunk, followed by a quick `moveSilent` that dispatches at once, moves the focused window first; the queued chunk's focus-relative `hl.dsp.window.move({ workspace })` then acts on whatever window is focused by then. The same for an un-animated leg after a sliding one. PLAUSIBLE: the window is one `hypr.request` round trip, longer while a long chunk or a 5 s timeout holds the queue. Fix: while `_evaluating || _evalQueue.length > 0`, send direct dispatches through `_eval` too.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### Recording two keys within 30 s can end the second recording early on Hyprland
- **Where:** `services/compositor/HyprlandManager.qml` (`_enterCaptureLua`, `captureKeys`), `services/compositor/KeybindEditor.qml` (`startRecording`)
- **What:** Each `captureKeys(true)` arms a 30 s `hl.timer` that leaves `axiom_record` if it's the current submap, and nothing cancels it when the recording stops. Record a key at t=0, finish at t=3, Add bind at t=10: the first timer leaves the second recording's submap at t=30, while QML still shows "Press a combo…" until its own 25 s timeout (`_recordTimeout`) ends it at t=35. Each start also redefines the submap, adding another copy of its unreachable bind (redefining a submap adds to it, as window-switcher.md notes). PLAUSIBLE and likely softened: the recorder's `ShortcutInhibitor` (KeyRecorder.qml) should keep Hyprland's binds from firing while it has focus. Sway already avoids the race by naming each mode anew. Fix: a generation in Lua (`AXIOM_CAPTURE_GEN`) checked by the timer and bumped on leave, and define the submap once.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Two keybind reference paths drop a key's binds
- **Where:** `services/compositor/KeybindsPageState.qml` (`_bindMods`), `components/methods/BindRows.qml` (`collapseDirections`)
- **What:** `_bindMods` decodes a bind's modifiers from its `BindKeys.keyId`, which leaves a tap's own modifier out, so a hand-written or merged `SUPER + Super_L` bind has no modifiers and the SUPER chip filters it out (the recorder's plain `Super_L` is unaffected). `collapseDirections` keeps only the first row per direction and merges only those (`_merged(ordered, …)`, BindRows.qml:107-119), while `_buildKeybindings` keeps rows whose labels differ in case apart ("Focus Left" next to "Focus left"), so the second row's `ids`, `user` and `overrides` are lost and the key map and combo lookup miss its key. Both rare. Fix: take the modifiers from `KeyNames.split(bind.key).mods`; pass all `members` to `_merged` and keep `ordered` for the cluster, with a test row of two "left" rows.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The monitor prompt's padding is a bare 18 px, and check_sizes misses it
- **Where:** `components/surfaces/monitors/MonitorPromptWindow.qml` (`pad`), `scripts/check_sizes.py` (`SIZE_WORD`)
- **What:** `readonly property int pad: 18` (MonitorPromptWindow.qml:19, used at :50-51) stays 18 px at every Interface scale while the card's text scales; AGENTS.md has sizes outside the bars from `Widget.px(n)`. `check_sizes.py` doesn't flag it because its size words have no `pad`. Fix: `Widget.px(18)`, and add `pad` to `SIZE_WORD` (the check that would have caught it). The overlay's page navigator has the same gap: `readonly property real inset: 6` (`components/hosts/overlay/OverlayPageNavigator.qml:38`) insets its arrows, tabs and pill in a bar whose height follows `Widget.height`. It should be `Widget.px(6)`, and `inset` belongs in `SIZE_WORD` too (found while reviewing the overlay system, 2026-10-31).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### HyprlandManager keeps members only it reads
- **Where:** `services/compositor/HyprlandManager.qml` (`withAnimations`, `_optionsWaiting`, `runLua`, `withBinds`, `layerApplied`, `refreshOptions`, `animations`, `animationsEnabled`, `_compaction`, `applyRemap`, `_bases`), `docs/dev/hyprland/ipc.md`, `docs/recipes/service.md`
- **What:** Deletion pass, about 40 lines. `withAnimations` has no caller, and `_optionsWaiting` serves only it (about 11 lines). `runLua` is a public wrapper whose only callers are its own `captureKeys` and `leaveSwitcher` (7 lines; `_eval` there). `withBinds` is used only by `withMainBinds` (inline, about 4). `layerApplied` only forwards to `refreshOptions` under two stacked comments (one function, about 4). `animations`/`animationsEnabled` are public but feed only `_workspaceAnim` (compute it in `_readOptions`, about 6). `_compaction` and `applyRemap` wrap their lines in the same animation-off/on prelude and epilogue (one `_runPlan(lines)`, about 4). `_bases` is recomputed on every output change though only the scrolling layout reads it (gate on `dynamicByLayout`, 2; the copy itself is by design, workspaces.md › Layouts). ipc.md's list of what `CompositorManager` uses ("`runLua`, `withOutputs`, `withBinds`, `refreshOptions`, `animations`, `switcherKey`") names a `withOutputs` that doesn't exist and four members no other file calls, leaves out `WindowSwitcherManager` (`leaveSwitcher`, `switcherKey`) and `CompositorConfigManager` (`layerApplied`) reaching the backend, and says the runtime layer's unbind goes through `runLua` (it's the daemon's now); service.md:109 also names `runLua`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### A bind description's section is parsed three ways
- **Where:** `services/compositor/KeybindsPageState.qml` (`_bindSection`), `services/compositor/KeybindManager.qml` (`bindLabel`, `_buildKeybindings`), `components/methods/BindActions.qml` (`hasOwnSection`)
- **What:** "Section: Label" is split three ways: `indexOf(": ")`, `indexOf(":")` and `split(":")[0]`. Only the editor's (`_bindSection`) doesn't trim, so `" Media: Play"` or `"Media : Play"` passes `hasOwnSection` (which trims) and gets its own " Media"/"Media " section and chip in the editor, while the reference shows it under Media. Fix: one `BindActions.splitDescription(text) → { section, label }` (trimmed), with test rows for a leading space and `a:b: c`, used by all three.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### KeybindManager keeps tables the methods helpers already hold
- **Where:** `services/compositor/KeybindManager.qml` (`_modifiers`, `decodeMods`, `_keyNames`, `_appliedBinds`, `userKeyCounts`), `components/methods/BindKeys.qml` (`_modBits`), `components/methods/KeyMap.qml` (`labelOf`), `services/compositor/KeybindsPageState.qml` (`_bindMods`)
- **What:** Deletion pass, about 36 lines. `_modifiers` (33 lines) is a second name↔mask table, the inverse of `BindKeys._modBits`, and `_bindMods` parses keyId's string (`parseInt`) to get a mask back: one `decodeMods(mask)` in BindKeys, built from `_modBits`, replaces it (net about -25), and the two can't disagree (its other caller is Hyprland's `modmask`, KeybindManager.qml:395; `_bindMods` stops decoding a mask with the fix in "Two keybind reference paths drop a key's binds"). Nine `_keyNames` entries (`mouse:272/273/274`, `mouse_up/down`, `left/right/up/down`) return what `KeyMap.labelOf` already does, which `_formatKey` asks next (about 9 lines). The skipped-key list is computed twice (KeybindManager.qml:230 and :245; one property, -2).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### The workspace strips repeat ActiveStrip's loader
- **Where:** `components/bar/widgets/Workspaces/WorkspaceStrip.qml`, `components/bar/widgets/Workspaces/WorkspaceGridStrip.qml`, `components/bar/widgets/Workspaces/ActiveStrip.qml` (`hasWindows`)
- **What:** Both strips hold the same `Loader { active: stripDirection !== ""; visible: hasWindows; ActiveStrip { 12 bindings } }` (only the text colour differs) and the same `stripOnly` expression but for the id count; `ActiveStrip.hasWindows` also calls `CompositorManager.stripWindows` again beside its `StripWindows`. Deletion pass: move the loader into ActiveStrip (it sets its own `active`/`visible` and exposes `stripOnly(count)`), about 20 lines. The two strips also repeat about 15 more lines each (the five resolved colours, `monitor`/`output`/`base`/`activeId`/`stripDirection`, `cell`/`cellRadius`/`cellLength`); the shared piece can take those too (bar-widgets audit, 2026-10-30).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The managed file's catch-all monitor line is copied into M.monitors
- **Where:** `backend/internal/compositor/render/hyprlua.go` (`HyprFileMonitorCalls`), `backend/internal/compositor/manager/hypr.go`
- **What:** Until the outputs are read, `M.monitors()` is refilled from the file: every line starting `hl.monitor({ output = "`. In managed mode that matches the managed file's fixed catch-all `hl.monitor({ output = "", mode = "preferred", … })` (hyprconfig.go:531) too, so each write made before the first read adds one more copy inside `M.monitors()`. Harmless (each replaces the default rule; the next write after a read cleans up) but the file churns and the layer key changes. Fix: read only the lines inside `function M.monitors()`, or skip `output = ""`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Hyprland's exit command is kept in two packages
- **Where:** `backend/internal/compositor/binds/hypr.go` (`exitCommand`), `backend/internal/compositor/render/hyprconfig.go` (`exitLua`)
- **What:** The merge maps `exec_cmd(<exitCommand>)` to `exitSession` and the writer emits `exitLua` for `exitSession`: the same string, kept by hand in two places (hypr.go:44, hyprconfig.go:30), with no test tying them. Changed alone, a written exit bind merges back as a plain `exec`. Fix: one constant (e.g. in `actions`) used by both; deletion pass 1 line.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### noteReload counts every compositor reload a second time
- **Where:** `backend/internal/compositor/manager/manager.go` (`seenReload`, `noteReload`), `backend/internal/compositor/manager/runtime.go`, `backend/internal/compositor/manager/hypr.go`, `backend/internal/compositor/manager/sway.go`, `backend/internal/compositor/manager/niri.go`, `docs/dev/hyprland/config-modes.md`
- **What:** `watchReloads` calls `seenReload()` from its forwarder as the event arrives (the count `runtimeLayer.read`'s retry relies on); the manager's reload handler then calls `noteReload()` (manager.go:1184), adding 1 to the same counter on the goroutine that also runs the read, where it can't land mid-read. Deletion pass, about 9 lines: drop `noteReload` from the writer interface, its three implementations, `runtimeLayer.noteReload` and the call; config-modes.md › detached names `noteReload()` and should name `seenReload`. Before deleting it, keep sway's unbind reset: `swayWriter.noteReload` also clears `state.SwayUnbind` (sway.go:256), and without that a user binding `Mod4+x` themselves after axiom bound it at runtime gets their bind removed by the stale `unbindsym` on the next `runtimeApply`; move the reset into `swayWriter.configReloaded` first (the compositor review, 2026-10-30). The sway review (2026-10-30) found an apply between the count and that reset still sends the old list: [The detached layer's unbind list can drift from what sway holds](#the-detached-layers-unbind-list-can-drift-from-what-sway-holds) wants the reset where the reload is counted; fix the two together.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The Hyprland Go code keeps dead and doubled helpers
- **Where:** `backend/internal/compositor/takeover/kinds.go` (`record`), `backend/internal/compositor/takeover/takeover.go`, `backend/internal/compositor/render/hyprlua.go` (`SwitcherLeaveLua`), `backend/internal/compositor/render/keys.go` (`UserKeyCounts`), `backend/internal/compositor/binds/hyprlua.go` (`quoteLua`), `backend/internal/daemon/compositor.go`, `backend/internal/daemon/compositorsocket.go`
- **What:** Deletion pass, about 65 lines. `Kind.record` is true for all three kinds, so the field and its `!record` halves are dead (about 13; the `err != nil` fallback for claims older than `.axiom-claimed` stays, and whether that fallback can go too is the maintainer's call, about 6 more). `render.SwitcherLeaveLua` has no Go caller (HyprlandManager.qml hard-codes the same Lua; 1). `render.UserKeyCounts` has only `shared_test.go`'s op row as caller (the shell counts user keys itself; about 18, with its row; the op row there for BindKeys' `runtimeBinds` replays a JS function that no longer exists). `binds.quoteLua` (31 lines) is a second Lua string quoter beside `render.LuaString`; `binds` can import `render` with no cycle (moved `raw` arguments would keep raw control bytes instead of `\ddd`, which no test pins). `daemon/compositor.go` spells the anonymous `struct{ Only string }` six times (a named type, about -15). The `hyprctl setcursor` request is built twice (`manager/hypr.go`, `daemon/compositorsocket.go`): one `ipc` helper. `render.SoftShadow`, `LeaveSubmap` and `AnimationSet` are exported but used only inside `render`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### Bind helpers keep JS halves the daemon owns now
- **Where:** `components/methods/BindActions.qml` (`descriptionFor`), `components/methods/BindKeys.qml` (`withIds`), `tests/tst_BindKeys.qml`, `backend/internal/compositor/manager/manager.go` (`withIDs`)
- **What:** `BindActions.descriptionFor` has no QML caller (only a comment in KeybindEditor.qml and its test): Go's `DescriptionFor` renders every description, so its test rows belong in a Go test and the function can go (deletion pass, 4 lines plus the test). `BindKeys.withIds` and Go's `withIDs` follow one rule (bind-merge.md › Duplicates), but tst_BindKeys.qml says "withIds has no Go counterpart to replay it", no shared case pins them, and they already differ on a bind with no `key` (`bind` in QML, `null` in Go). Fix: record `withIds` as a shared case and replay it against `withIDs` (nil key → "").
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Stale lines in the Hyprland docs and comments
- **Where:** `docs/dev/hyprland/window-switcher.md`, `components/methods/WorkspaceGeometry.qml` (`orderMonitors`), `components/methods/BindKeys.qml`, `backend/internal/compositor/render/keys.go` (`RuntimeBinds`), `components/hosts/popout/EdgePopout.qml`
- **What:** window-switcher.md › Events and the manager says the list is "limited to the focused monitor", but with `scope: all` `DockLayout.inScope` keeps every monitor's windows; what's tied to the focused monitor is where it shows. `orderMonitors`' comment says CompositorManager fills its keys; `blockBases` does. BindKeys' header still lists "which of axiom's binds a runtime layer applies and which it skips", gone from QML, and keys.go's comment calls `RuntimeBinds` the copy of BindKeys' `runtimeBinds`, which no longer exists. EdgePopout.qml (outside the system, lines 89 and 383) twice credits "HyprlandManager's layer rules", which are the daemon's now (`render.LayerRulesLua`).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The unused reader member check counts a member named after its key as used
- **Where:** `scripts/gen_docs.py` (the reader-member usage count), `scripts/config-usage-baseline.json`, `config/WindowSwitcherConfig.qml` (`compositorSwitcher`)
- **What:** gen_docs.py (around line 334) counts a reader member as used inside its reader when its name appears more than once there. `(?<![\w])name\b` also matches the `.name` in the member's own `_c.name` binding, so every member named after its config key passes, read or not: `WindowSwitcherConfig.compositorSwitcher` has no QML reader (the daemon reads the setting itself, `manager/niri_test.go` pins it) and isn't listed. Fix: don't count a match preceded by `.`, or count `<Reader>.<member>` uses outside the reader; then delete what it newly finds (the baseline only shrinks): `compositorSwitcher` is 3 lines.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### A user's blur off overrides axiom's blur on niri
- **Where:** `backend/internal/compositor/render/niri.go` (`NiriLookNodes`), `backend/internal/compositor/userconf/niri.go` (`NiriInfo`)
- **What:** `niri-backend.md` says axiom's look wins over the user's files, and a boolean is written both ways so axiom's choice wins. The look's blur isn't: with blur on, `NiriLookNodes` writes `blur { passes; offset; noise }` but never `on`. A `blur { off }` in the user's config (included mode) or in a `user/*.kdl` (managed mode, e.g. the adopted `00-previous.kdl`) stays in effect, since niri merges a later definition per field, so axiom's window and surface blur silently does nothing. `niri validate` (niri 26.04) accepts `blur { on }`. `NiriInfo` has the mirror gap: it sets `enabled` false on any `off` and never back on a later `on`, so `NiriManager.blur` would read wrong once the writer writes `on`. Fix: `KdlSetPath(nodes, "blur.on", …)` with blur on; `NiriInfo` takes the last of `on` / `off`; a frozen render case.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the niri system

### niri started on a broken config reads as loaded
- **Where:** `backend/internal/compositor/ipc/niri.go` (`Reloads`), `backend/internal/compositor/manager/niri.go` (`checkLoaded`, `lastFailed`), `backend/internal/compositor/manager/manager.go` (`configReloaded`)
- **What:** `Reloads` drops the event stream's first `ConfigLoaded` (the state niri starts the stream with), its `failed` flag included, so `niriWriter.lastFailed` is only ever set by a later reload. When niri starts on a config it can't load (a broken `user/*.kdl` at login), it runs its defaults; the stream opens with `ConfigLoaded { failed: true }`, the daemon ignores it, and managed mode's `checkLoaded` reports loaded (the managed file is there, header and all). The Compositor settings show no problem while none of axiom's binds, look or input apply, until the next reload. The shell sees it (`NiriState.reduce` keeps `configFailed` from every `ConfigLoaded`) but nothing reads it (`NiriManager.lastLoadFailed` has no reader). PLAUSIBLE: niri running its defaults after a failed start and the first event carrying `failed: true` are to be confirmed in `scripts/dev/nested.sh niri --managed` with a broken user file. Fix: `Reloads` hands the first `ConfigLoaded`'s `Failed` over as the initial state, not as a reload; the writer sets `lastFailed` from it.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the niri system

### Nothing reads userBindsRead or lastLoadFailed
- **Where:** `services/compositor/CompositorConfigManager.qml` (`userBindsRead`), `backend/internal/compositor/manager/writer.go` (`userBindsRead`), `backend/internal/compositor/manager/manager.go` (`state`), `services/compositor/NiriManager.qml` (`lastLoadFailed`)
- **What:** Deletion pass. `CompositorConfigManager.userBindsRead` has no reader in QML (grep: its declaration only). In Go it's a writer interface method whose three implementations always return true: Hyprland's and sway's are the constant, and niri's `userEntries != nil` is set by `newNiri` before the first state is sent. About 9 lines (QML property, interface method, three implementations, the fake's, the state field) plus the doc comment. `NiriManager.lastLoadFailed` (2 lines plus a sentence in `niri-backend.md` › State) has no reader either, unless the fix for "niri started on a broken config reads as loaded" gives it one.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the niri system

### The niri writer's runtimeOn and unread-binds guards are dead
- **Where:** `backend/internal/compositor/manager/niri.go` (`runtimeOn`, `runtimeApply`, `entries`, `readUserConfig`)
- **What:** Deletion pass. `niriWriter.runtimeOn` is set in `runtimeApply` and `runtimeClear` and never read (sway's is; niri's was copied along): 3 lines. `newNiri` calls `readUserConfig`, which always leaves `userEntries` non-nil (an empty array when the config can't be read), so `runtimeApply`'s and `entries`' `if w.userEntries == nil` returns and `readUserConfig`'s own nil guard can't happen: about 9 more lines, and `entries` never returns nil on niri.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the niri system

### Three listings of niri's user files
- **Where:** `backend/internal/compositor/manager/niri.go` (`userFiles`), `backend/internal/compositor/binds/niri.go` (`niriFiles`), `backend/internal/compositor/takeover/kinds.go` (`left`)
- **What:** Deletion pass. The managed config's `user/*.kdl` (regular `.kdl` files, no hidden ones, by name) is listed three times: the writer's `userFiles` (12 lines), the merge's `niriFiles` (21, with `--only`), and the takeover's `left` (13), which counts what a restored config doesn't include. The copies disagree: `left` counts hidden `.kdl` files (an editor's swap file, a staged write) that the writer never includes, and skips a symlinked `.kdl` (`DirEntry.Type`) that the writer includes (`os.Stat`), so a release can report files left out that were never in. One `userconf.NiriUserFiles(dir)` used by all three saves about 25 lines and makes them agree.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the niri system

### RunningNested has its own niri socket client
- **Where:** `backend/internal/compositor/userconf/niri.go` (`RunningNested`), `backend/internal/compositor/ipc/niri.go` (`Outputs`)
- **What:** Deletion pass. `RunningNested` dials `$NIRI_SOCKET`, writes `"Outputs"` and parses the reply by hand (28 lines), which `ipc.NiriFromEnv(getenv).Outputs(ctx)` already does with the shared dial and timeout (`userconf` can import `ipc`: `ipc` depends only on `render`, `actions` and `jsonx`). As one `Outputs` call, a single output named `winit`: about 8 lines.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the niri system

### NiriManager queues actions the daemon could order
- **Where:** `services/compositor/NiriManager.qml` (`_command`, `_next`), `backend/internal/daemon/compositorsocket.go` (`niriHandlers`)
- **What:** Deletion pass. `NiriManager` keeps its own queue (`_command`, `_queue`, `_running`, `_next`: about 30 lines) so a chain of actions can't overtake itself, sending each only after the last one's reply came back through the daemon: one full round trip per action. The daemon already has the mechanism, `rpc.Registry.InOrder` (used for `outputs.apply`). A `niri.command` method registered in order, alongside `niri.request` for state, lets `_action` / `_command` send at once and drops the queue: about 30 QML lines for about 5 Go lines.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the niri system

### A second KDL writer in the kdl package
- **Where:** `backend/internal/compositor/kdl/kdl.go` (`ValueText`, `PyFloat`, `NodeText`, `Str`), `backend/internal/compositor/render/niri.go` (`KdlValue`, `KdlString`, `KdlSerialize`)
- **What:** Deletion pass. The niri system's Check is that KDL is written by one module; `niri-backend.md` names `render`'s serializer. The parser package carries a second writer from the Python port: `ValueText` (its own escapes, without `\r`), `PyFloat` (floats as Python's `str` spells them, "1e+16"), `NodeText` (no quoting of names), and `Str`'s Python spellings ("True", "None"). They're used only for a moved bind's `raw` text and a bind's description (`binds/niri.go`, `userconf/niri.go`), where `render`'s writer gives the same text for the values niri's binds hold. Writing those through `render` (or one shared value writer) removes about 50 lines and the second set of escaping rules.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the niri system

### Setting names that still confuse
- **Where:** `config/schema/sections/`
- **What:** From the maintainer's notes: "still confusing option names in settings" (after the look-and-feel renames). The plan lists the settings whose titles or keys read wrong, with a proposed name for each, for the maintainer to decide; a renamed key is a migration step.
- **Size:** needs a plan
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The monitor editor shows changes nobody made
- **Where:** `services/compositor/MonitorManager.qml` (`draft`, `ensureLoaded`), `components/views/Monitors/Monitors.qml`
- **What:** From the maintainer's notes: the monitors page shows unsaved changes when nothing was changed (likely a value the draft normalises on load differing from the saved one).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Typing in modules on the overlay and the desktop
- **Where:** `components/hosts/overlay/OverlayPanel.qml` (`keyboardFocus`), `components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`, `wantsKeyboard`)
- **What:** From the maintainer's notes: modules that take typing can't be used while they're on the overlay, and a click outside a desktop module stops its typing.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Modules inside borders aren't sized evenly
- **Where:** `components/hosts/overlay/ModuleGrid.qml`, `components/hosts/overlay/OverlaySlot.qml`
- **What:** From the maintainer's notes: module sizing within borders isn't even (the space around modules framed by a border differs from side to side or between modules). Seen while reviewing the overlay system (2026-10-31), two likely causes. First, `GridPlacement.rectPx` returns unrounded px (`unitOf` is `(card - 3 × gap) / 4`, fractional for most card sizes), and `OverlayPages` then scales the whole page by `contentZoom`, so the slots' edges and `Card`'s border fall on fractional pixels and are drawn a pixel apart unevenly. Snapping each slot's edges (not its size) to whole drawn px would settle that. Second, `Card` doesn't pad its content (`full` fills the box), while `Panel`'s column takes `pad`, so each of the 25 `Card` modules applies `pad` itself, some once and ColorSwatch not at all. PLAUSIBLE: a screenshot at a non-1 zoom, compared with one at 100 %. Seen again while reviewing the modules system (2026-10-31): the `Card` modules padding differently are ColorSwatch (not at all), KeyboardLayout (width only), Greeting (`anchors.margins`) and Session (its own `margin`, 0 when tight); and padding also skews which layout a slot gets, since `SlotContext.compact` compares `fullMin*` with the slot padding included ([its entry](#fullminwidth-and-fullminheight-are-compared-with-the-slots-size-padding-included)).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### High module padding clips edge menu modules
- **Where:** `components/surfaces/edgemenu/EdgeMenuBody.qml`
- **What:** From the maintainer's notes: on an edge menu, a module padding too high for the menu clips the modules instead of making them smaller.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### An edge popout doesn't size itself consistently
- **Where:** `components/hosts/popout/EdgePopout.qml`, `components/hosts/popout/EdgeSurface.qml`
- **What:** From the maintainer's notes: an edge popout doesn't consistently size itself (the same content opens at different sizes).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The keybinds page on a small monitor with large binds
- **Where:** `components/views/Keybinds/BindListRow.qml`, `components/views/Keybinds/BindSection.qml`
- **What:** From the maintainer's notes: the keybinds page needs checking on a small monitor with long binds (combos and commands): rows that don't fit. Take it with the 1080p pass of [Text clips on 1080p screens](#text-clips-on-1080p-screens).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Shift+Enter on an emoji doesn't type it on niri
- **Where:** `components/surfaces/launcher/LauncherPanel.qml` (`activate`), `services/apps/EmojiManager.qml` (`type`)
- **What:** From the maintainer's notes: under niri, Shift+Enter on an emoji in the launcher doesn't type it into the focused window (typing goes through `input.type` on the daemon's virtual keyboard). Not reproduced (2026-10-28): in a nested niri on the live binary, `axiom launcher search ";grinning"` then Shift+Enter typed it into foot, kitty and a GTK entry every time, with fcitx5 and mozc running too; the live logs show no typing error, and the last emoji uses predate typing moving to the daemon. Untested: a physical Shift+Enter, Electron or Xwayland windows, the live focus-follows-mouse. Waits for the maintainer: which app, and does it still fail.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### A window takes the keyboard from a desktop module on niri
- **Where:** `components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`), `services/ui/DesktopManager.qml`
- **What:** From the maintainer's notes: under niri, as soon as the mouse leaves a desktop module that takes typing, the window under the pointer takes the keyboard focus (niri's focus follows the mouse onto it), so typing in the module stops. How to hold the focus there is still open ("idk how to handle this").
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Hyprland's default workspace doesn't highlight its first window
- **Where:** `components/bar/widgets/Workspaces/StripWindows.qml` (`focused`), `services/compositor/HyprlandManager.qml`
- **What:** From the maintainer's notes: on the workspace Hyprland starts on, the first window opened isn't highlighted as focused until a workspace move. Checked 2026-10-29 (code read, nested Hyprland): Hyprland's own data is right (the first window on workspace 1 has `focusHistoryID` 0 and is `activewindow`), and `StripWindows` highlights `CompositorManager.lastFocused` of the workspace's windows, which for one window is always it; so the cause isn't in either. Which highlight it is (bar strip, dock `DockManager.focusedId`, overview `WindowPreview.focused`) and under which layout (`StripWindows` shows only under scrolling, whose workspace ids `DynamicWorkspaces` renumbers until `_compaction` runs) needs the maintainer to reproduce it.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The shell's hello can be refused across a dev re-exec
- **Where:** `backend/internal/daemon/methods.go` (`daemon.hello`, `isShell`), the re-exec's shell hand-over (`supervising the shell started before the re-exec`)
- **What:** On 2026-10-29 a rebase replaced QML and Go files under the live session: qs reloaded at 18:18:32, dev mode re-exec'd the daemon at 18:18:33.871, and the reloaded shell's hello at 18:18:34.200 was refused, `only the shell axiom runs may connect as the shell`, one millisecond after the new daemon logged `supervising the shell started before the re-exec` for that same pid (433649). From then on every call failed (`[FileManager] Could not write …selfupdate.json`, `[SelfUpdateManager] Check failed`) until the shell was started again. So the re-exec'd daemon answers a hello before it knows the shell's pid, or matches the wrong one.
- **Size:** small
- **Found:** 2026-10-29, while rebasing the custom widgets branch onto main

### A greeter-only module validates on any page
- **Where:** `components/content/Session/schema.yaml` (`hosts`), `components/content/Login/schema.yaml`, `components/content/Password/schema.yaml`
- **What:** `hosts: {only: [greeter]}` keeps Session out of the layouts editor's library elsewhere, but the built schema still lists it in every host's `oneOf`: a config with Session in an edge menu and on an overlay page passed `axiom config validate`, and it drew as a bare "Session" field on an empty card. So an import, a community setup or a hand edit can put a greeter- or lock-only module (Session, Login, Password) where it can't work.
- **Size:** small
- **Found:** 2026-10-29, while building the revamped example setups

### Opening a hover-closing edge menu by IPC closes it at once
- **Where:** `services/ui/EdgeMenuManager.qml` (the `edgeMenu` `IpcTarget`'s `open`), `components/surfaces/edgemenu/EdgeMenuSync.qml` (`autoDismiss`)
- **What:** `axiom edge-menu open <id>` on a menu with `close.onLeave` (the default) shows it for one close delay and closes it, since the pointer isn't in it: the IPC `open` calls `open`, not `reveal`, so it's never `revealing`. `pin` on a closed menu doesn't open it either; only `pin` then `open` keeps it up. A bind or script can't open such a menu.
- **Size:** small
- **Found:** 2026-10-29, while building the revamped example setups

### Bar widget hosts settle after they're gone
- **Where:** `components/bar/BarWidgetHost.qml` (`Component.onCompleted`'s `Qt.callLater`), `components/bar/widgets/Workspaces/ActiveCellIndicator.qml` (`_placed`), `components/bar/BarContainer.qml` (the inline `Section`'s `Component.onCompleted`)
- **What:** Restoring a saved config that rebuilds the bars logs `TypeError: Value is null and could not be converted to an object` (8–12 per rebuild) and `Cannot read property 'index' of null` from `ActiveCellIndicator`: the `Qt.callLater` closures run after their item was destroyed. Also on the same swaps, `Button.qml` logs `Unable to assign [undefined] to QString` for `icon`/`text` while its properties are being replaced. BarContainer's inline `Section` settles through the same `Qt.callLater`; the fix should cover it too (bar audit, 2026-10-30).
- **Size:** small
- **Found:** 2026-10-29, while building the revamped example setups

### No caps lock warning when typing a password
- **Where:** `components/content/Password/Password.qml`, `components/surfaces/lockscreen/`, `components/surfaces/greeter/`
- **What:** Neither the lock screen's nor the greeter's password field shows that Caps Lock is on (grep for caps lock in both finds nothing), so a password typed with it on just fails with no hint. Also open: where the state comes from (the compositor's keyboard LEDs, or the daemon reading the LED), and whether other password fields (Wi-Fi, polkit) show it too.
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### Removable drives aren't handled
- **Where:** `services/system/` (no service yet)
- **What:** Nothing in services, components or the schema uses udisks: plugging in a USB stick or SD card gives no notification, no mount or eject, and no list of drives (the Disks module shows only mounted filesystems). Also open: automount or ask, the notification's actions, where the drive list lives (a bar widget, a popout, the Disks module), and running udisks through the daemon.
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### Bluetooth pairing that asks for a PIN or a passkey
- **Where:** `services/system/BluetoothManager.qml` (`_connectAfterPair`), `components/content/BluetoothDevices/`
- **What:** Pairing trusts, pairs and connects, but no pairing agent asks the user to confirm a passkey or type a PIN, so a keyboard or phone needing one may not pair unless another agent runs. Not tested on such a device. Also open: whether Quickshell's Bluetooth registers an agent, or the daemon does, and the prompt's surface.
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### No OSD for caps lock or the keyboard layout
- **Where:** `config/schema/definitions/common/OSDEntry.yaml` (bar kinds), `components/surfaces/osd/OSDTriggers.qml`, `services/system/KeyboardLayoutManager.qml`
- **What:** The OSD's bars are only master, other, microphone, brightness and app: toggling Caps Lock or Num Lock, or switching the keyboard layout, shows nothing. These aren't levels, so they need a different OSD shape than a bar. Also open: the lock key state's source (shared with [No caps lock warning when typing a password](#no-caps-lock-warning-when-typing-a-password)).
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### No keyboard backlight control
- **Where:** `services/system/BrightnessManager.qml`
- **What:** Laptops' keyboard backlights (`kbd_backlight` LEDs) have no slider, OSD bar or keys: nothing in services reads them. Also open: whether `BrightnessManager` takes them as another device, the OSD bar kind, and writing the LED through the daemon.
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### A file mode that stops loading keeps the saved monitor profile off
- **Where:** `backend/internal/compositor/manager/manager.go:1177` (`configReloaded`), `backend/internal/compositor/manager/manager.go:631` (`checkLoaded`)
- **What:** `m.loaded` is set when the included module or the managed config is in effect (631) and cleared only in `modeChanged` (728) and `syncFile`'s "isn't axiom's any more" branch (1151); `checkLoaded`'s not-loaded and `failed` paths leave it true. Scenario: Hyprland or sway, included mode, module loaded; the user takes the include line out and the compositor reloads. `configReloaded` tests `!m.loaded` (1177) before `checkLoaded` runs, so it skips the profile; `checkLoaded` then puts the runtime layer in (which carries no monitor rules: `hyprWriter.runtimeApply` has binds, required settings, live lines and strips only), but `m.loaded` stays true. The reload set the outputs from the user's own lines, and every later reload skips the saved profile the same way, until a hotplug or a Monitors edit. No test covers it (`TestHotplugsApplyTheSavedProfile` reloads in detached mode only). Fix: `m.loaded = false` in `checkLoaded`'s not-loaded and `failed` paths, and in `configReloaded` re-apply the profile after the mode branch has run `checkLoaded`; a test row (included, loaded, then a reload with the file no longer loaded re-applies the profile).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

### Leaving included between sessions leaves the full module loaded
- **Where:** `backend/internal/compositor/manager/manager.go:705` (`apply`), `backend/internal/compositor/manager/manager.go:942` (`leave`)
- **What:** `emptyModule` runs only from `leave`, which runs only when `previous != "" && previous != m.mode` (705); `previous` is `m.st.AppliedMode`, kept in `compositor.json` for one compositor instance only, so each new session starts with `""`. Managed has a cover for "a mode changed while axiom wasn't running" (`configIsOurs`, 698); included has none. Scenario: the last session ran included and the user's config still loads the module; config.json says detached at the next start (synced, or edited while axiom wasn't running). `apply` skips `leave`, the module keeps its old binds, look, input and monitor rules, and the runtime layer skips every axiom key as taken by the user's config, so Keybinds edits to those keys do nothing until the include line goes. config-modes.md › Leaving a mode: "Leaving included, or leaving managed for detached, empties the module if it exists". Fix: in `apply`, call `m.emptyModule(ctx)` whenever `m.mode != "included"` (outside the hold), not only from `leave` (it does nothing when the file is missing or already empty).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### A failed takeover leaves no layer and no problem
- **Where:** `backend/internal/compositor/manager/manager.go:837` (`claim`), `backend/internal/compositor/manager/manager.go:845` (`claim`), `backend/internal/compositor/manager/manager.go:606` (`writeIfChanged`)
- **What:** In managed mode, approved (or nothing of the user's to take over), `claim` can fail: `edit.LockDir` (837: the lock held over 10 s by a command line's `axiom compositor …`, or a read-only config dir) or `takeover.Claim` (845: `MkdirAll` of user/, a backup copy, `setAside`). Both branches only log and return: no runtime layer goes on, `problem` stays "", the status reads `pending` with no reason, and the session has none of axiom's binds, look or input until a compositor reload happens to run `checkLoaded`. The `blocked` branch beside them already does it right (`m.warnOnce(m.w.problems(m.in).Blocked); m.runtimeApply(ctx)`). config-modes.md › The layer: "Whenever a file isn't loaded … the runtime layer stands in and `problem` says why". `writeIfChanged`'s write error (606) is the same in small: logged, no problem shown. Fix: in both `claim` error branches `m.warnOnce("Couldn't take over " + path + ": " + err.Error()); m.runtimeApply(ctx)`; in `writeIfChanged` `m.warnOnce("Couldn't write " + path + ": " + err.Error())`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

### A failed takeover check reuses the last answer and can adopt without approval
- **Where:** `backend/internal/compositor/manager/manager.go:800` (`check`), `backend/internal/compositor/manager/manager.go:813` (`claimIfApproved`)
- **What:** When `takeover.Check` errors (its `edit.LockDir` giving up while `axiom compositor claim|release|binds remove` holds the lock), `check` logs and returns, keeping `m.managedCheck` from an earlier call; `claimIfApproved` decides on that stale word. Scenario: the check said `released`/`new`/`stock` earlier in the session, the user then puts their own config back (now `adopt`), and an `apply` runs while the lock is held and is freed before `claim` takes it: the stale word lets `claim` run, and `takeover.Claim` adopts whatever is there without the user's Allow. config-modes.md › Approving a takeover: "Allowed only by `allowTakeover()` … `adopt` waits". `compositor.checkManaged` returns the stale word too. Narrow race. Fix: on error set `m.managedCheck = ""`, so `claimIfApproved`'s default branch waits (pending, runtime layer standing in).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### Claim keeps writing a symlinked or git-tracked config that release refuses to give back
- **Where:** `backend/internal/compositor/takeover/takeover.go:179` (`Claim`), `backend/internal/compositor/takeover/takeover.go:241` (`Release`), `backend/internal/compositor/manager/manager.go:862` (`claim`)
- **What:** `Claim` returns `ours` before it checks `blocked` (179-184); `Release` checks `blocked` after `ours` and refuses (241-246). managed-takeover.md › Release: "A symlinked or git-tracked file is refused, as `claim` refuses it". Scenario: in managed mode the user moves `~/.config/hypr` (or sway, niri) into a dotfiles repo, by git or a stow symlink. Every apply then runs `Claim` → `ours` → `writeIfChanged(ManagedPath, …)`, and `fsx.WriteFile` follows the link, so axiom rewrites the file in their repo on every settings change; leaving managed, `Release` answers `blocked:link`/`blocked:git` and the manager retries from 10 s up to every 5 min, telling them to make it a plain file. Fix: one rule; the smaller is `blocked` before `ours` in `Claim` (and `Check`), so managed stops writing and the runtime layer stands in with `problems().Blocked`, as release already assumes; a test row for claiming an `ours` symlinked file.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

### sway's hookup and takeover use ~/.config/sway/config whatever config sway runs
- **Where:** `backend/internal/compositor/manager/sway.go:57` (`files`), `backend/internal/compositor/userconf/sway.go:17` (`SwayMain`), `backend/internal/compositor/takeover/kinds.go:106` (`sway`)
- **What:** The sway writer reads the user's binds from the config sway runs (`userconf.SwayMain`: the running sway's `-c`, else sway's search order `~/.sway/config`, `$XDG_CONFIG_HOME/sway/config`, `~/.i3/config`, `$XDG_CONFIG_HOME/i3/config`, `/etc/sway/config`), but `files()` points `IncludeTarget`/`AutostartTarget` at `managed := w.dir() + "config"`, and the takeover's file is the same fixed path. niri's writer uses `w.mainConfig`. Scenario: an i3 migrant on `~/.config/i3/config` (or `sway -c ~/dotfiles/sway.conf`) picks included; **Add it for me** creates `~/.config/sway/config` holding only the include line; nothing changes this session, but at the next login sway finds that file before `i3/config` and runs an almost empty config. Managed: `check` says `new` (no approval asked), `claim` writes the managed config there, `checkLoaded` fails all session, and the next login runs axiom's config with the user's neither adopted nor loaded. With `~/.sway/config` (searched first) neither mode ever loads. Fix: build sway's targets from `SwayMain` as niri's use `mainConfig`; in managed, `blocked` (or adopt) when `SwayMain` isn't the managed path; a test row running sway from `~/.config/i3/config`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

### A relative -c is read from the daemon's folder
- **Where:** `backend/internal/compositor/userconf/niri.go:88` (`NiriMain`), `backend/internal/compositor/userconf/sway.go:22` (`SwayMain`)
- **What:** `startedWith` returns the compositor's `-c` as written. After `cd ~/.config/niri && niri -c test.kdl`, `NiriMain` returns `test.kdl`, which `ResolveNiri` opens relative to the daemon's working folder: "Can't read your niri config", no user binds known, included reported as not loaded, and a wrapper including `test.kdl` relative to `$XDG_STATE_HOME/axiom/`. `SwayMain` checks `isFile` against the daemon's folder and silently falls back to the default places, a config sway doesn't run. Fix: when the path isn't absolute, join it to `os.Readlink("/proc/<pid>/cwd")`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### Gaps to the edges are wider on sway than the setting says
- **Where:** `backend/internal/compositor/render/sway.go:468` (`SwayLookLines`), `backend/internal/compositor/render/niri.go:456` (`NiriLookNodes`), `services/compositor/SwayManager.qml:38` (`gapsOut`)
- **What:** `WindowLook.gaps.outer` is "Gaps to the edges". Hyprland writes it as `gaps_out` (the edge gap); niri's writer writes struts of `outer - inner` so its edge comes out at `outer`; the sway writer writes `"gaps inner "+inner, "gaps outer "+outer` unchanged (468-469), and sway(5) says "Outer gaps are in addition to inner gaps. To reduce or remove outer gaps, outer gaps can be set to a negative value." (sway-backend.md and `SwayManager.gapsOut` read it back as outer + inner). At the defaults (inner 3, outer 6) Hyprland and niri leave 6 px at the edge, sway 9, and Automatic bars follow the 9. niri's writer also clamps the struts at 0 (`math.Max(0, …-inner)`), so with inner 10 and outer 0 niri keeps 10 px where Hyprland keeps 0 (`niri validate` 26.04 accepts a negative strut; PLAUSIBLE that niri draws it narrower: a nested niri with inner 10, outer 0 settles it). Fix: sway writes `outer - inner` (`gaps outer`, and `gaps outer all set` live), `SwayManager.gapsOut`'s live branch becomes `_liveGaps.outer`; drop niri's `math.Max(0, …)` around the edge; regenerate the sway and niri goldens.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

### A $' or $& in a bind's argument is read as a replacement pattern
- **Where:** `backend/internal/compositor/render/actions.go:129` (`jsReplace`), `backend/internal/compositor/render/hyprconfig.go:116` (`ipcCall`), `backend/internal/compositor/render/actions.go:101` (`DefaultLabel`), `components/methods/BindActions.qml:99` (`defaultLabel`)
- **What:** `jsReplace` reproduces JS `String.replace`'s `$$ $& $\` $'` handling, and the user's argument is passed through it as the replacement. A `launcherSearch` bind with the argument `US$'s rate` renders on sway as `exec "axiom ipc appLauncher search 'US\\''s rate'"` and on Hyprland as `exec_cmd("axiom ipc appLauncher search 'US\\''s rate'")` (scratch run): the shell gets `US\s rate`, and both descriptions read "Launcher: USs rate". niri substitutes word by word (niri.go:316-324) and passes it intact, so the same bind does different things per compositor. Fix: put user text in literally (`strings.Replace(s, "{0}", arg, 1)` in `ipcCall` and `DefaultLabel`, and for `"{}"` in sway.go's exec lines); `jsReplace` can become literal if no frozen case pins a `$` replacement. The shell's halves do the same (`BindActions.qml:69` `word.replace("{0}", text)`, :99 `.replace("{0}", argument)`, which the parity replay pins against the Go): pass a function (`() => argument`) there in the same change.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### A niri merge of two binds on one line loses one
- **Where:** `backend/internal/compositor/binds/marked.go:64` (`removeMarked`), `backend/internal/compositor/manager/manager.go:1305` (`merge`)
- **What:** `removeMarked` marks a niri file's sites right to left on the same `lines[i]`, but checks each site's `text` against `lines[i]` as already marked. With `binds {\n    Mod+T { spawn "foot"; }; Mod+Q { close-window; }\n}` both binds are extracted (same line, cols 4 and 29); `Mod+Q` is marked first, then `Mod+T`'s check fails as `changed`. Remove returns `removed:1, failed:[{line:2, reason:"changed"}]` and writes `Mod+T { spawn "foot"; }; /* (moved into axiom) */ /-Mod+Q { close-window; }` (reproduced with a `go test -overlay` probe). `merge`'s `left()` matches failures by file and line only, so it takes both line-2 binds back out of the commit: `Mod+Q` is commented out of the user's file and missing from `Keybinds.binds` (only `user/.backups/` has it), and the merge reports a file nobody changed. Sway can't reach it (one bind per line); Hyprland keeps a call not alone on its line. Fix: compare against the line as read (keep `orig := lines[i]` per line before any mark); a `TestNiriRemove` row with two binds on one line.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### A sway bind using a variable from an include moves as a literal $name
- **Where:** `backend/internal/compositor/binds/sway.go:256` (`extractSway`)
- **What:** `extractSway` knows only the `set` lines of user/'s own files and never follows an `include`, while the takeover keeps the adopted file's includes live. A config setting `$term`/`$menu` in an included file (`include /etc/sway/definitions` on Manjaro's sway) with `bindsym Mod4+Return exec $term` moves that bind as `{"action":"exec","argument":"$term"}` (reproduced); the line is commented out, axiom's module is read before user/ where `$term` isn't set, so sway leaves it literal and the user's terminal and launcher binds run nothing after a Merge. Extract with `--only` has the same gap for variables set in an earlier user/ file. Fix: collect the variables as sway reads them, following `include`s (`userconf.SwayText` already expands them), before reading each file's binds; failing that, keep a bind whose command still holds a `$name`, with a reason; a `TestSwayExtract` row.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

### A niri spawn of one word with a space moves as a broken shell command
- **Where:** `backend/internal/compositor/binds/niri.go:95` (`niriAction`)
- **What:** niri's `spawn` runs its arguments without a shell; the merge makes them axiom's `exec`, which every niri writer emits as `spawn-sh` (`render/niri.go:314`). Several words are shell-quoted (`shellJoin`), one word is passed as is (`if len(words) == 1 { return commandAction(o, words[0]) }`): `Mod+T { spawn "/opt/My App/app"; }` moves as `exec "/opt/My App/app"` (reproduced) and runs `/opt/My` with an argument; any shell character in the word (`;`, `$`, `&`, `*`, quotes) changes meaning too, and the original bind is already commented out. Fix: always `shellJoin(words)`, keeping a leading `~/` outside the quotes; a `TestNiriExtract` row with a spaced path.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### A sway line continuing a non-bind line is moved as a bind of its own
- **Where:** `backend/internal/compositor/binds/sway.go:283` (`extractSway`)
- **What:** Only the bind's own line is checked for a trailing `\`; a line that follows a continued line is read as a fresh statement. `exec_always foo \` then `bindsym Mod4+x kill` is to sway one `exec_always foo bindsym Mod4+x kill`; extract moves `SUPER + X → closeWindow` (reproduced) and remove prefixes the second line with `# (moved into axiom) `, so sway now runs `foo # (moved into axiom) bindsym Mod4+x kill` and the user gains a bind they never had. Rare. Fix: carry a `continued` flag from the previous raw line and skip a line it covers; one test row.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### Small shrinks in the compositor manager
- **Where:** `backend/internal/compositor/manager/manager.go:760` (`AllowTakeover`), `backend/internal/compositor/manager/manager.go:532` (`state`), `backend/internal/compositor/manager/manager.go:888` (`release`), `backend/internal/compositor/manager/manager.go:1251` (`merge`), `backend/internal/compositor/manager/writer.go:216` (`sprintf`), `backend/internal/compositor/manager/hypr.go:70` (`problems`)
- **What:** Deletion pass, about 15 lines. `AllowTakeover`'s `m.w == nil` check is dead (`enqueue` drops everything then) and its `if m.mode == "managed"` repeats line 760's early return; `state()`'s `if m.w != nil` (532) can't be false for its two callers, and its `kind` field (559) is read by no client; the approval removal with its warning is written twice (888-890, 1148-1150) beside an `approve()` for the add; `merge`'s `|| m.merging` (1251) can't be true at entry (set and cleared inside the one call on the manager goroutine); `sprintf` (writer.go:216) wraps `fmt.Sprintf` for its one caller `logf`; `problems().Blocked` is the same sentence in all three writers (hypr.go:70, sway.go:76, niri.go:88), read only at manager.go:854, where `m.files().ConfigDir` gives the one part that differs. Fix: drop the dead checks and `kind`, add `forgetApproval()`, call `fmt.Sprintf` in `logf`, build the blocked sentence in the manager and drop the field (and the fake writer's `Blocked`). Every path keeps its behaviour: each removed check is settled by the caller or the line before it. "Nothing reads userBindsRead or lastLoadFailed" drops another `state()` field, independently.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### niri's bind plan is a copy of runtimeLayer.plan
- **Where:** `backend/internal/compositor/manager/niri.go:110` (`plan`), `backend/internal/compositor/manager/runtime.go:42` (`plan`)
- **What:** `runtimeLayer` is "what every compositor's runtime layer shares", yet `niriWriter.plan` (niri.go:108-126, 19 lines) repeats `runtimeLayer.plan` (filter by `complete`, `render.RuntimeBinds` against the user's entries, keep `skipped`, log each taken key once through its own `reported` map, with its own `reported`/`skipped` fields). It has drifted: it drops `RuntimeBinds`' unreadable keys without the "Can't read the key %q" log the other two give, and words the skip log differently. Fix: give `niriWriter` a `runtime runtimeLayer{configName: "niri"}`; `parts`, `entries`, `ownKey` and `skippedKeys` use it; about 15 lines fewer and one log wording.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

### Go copies of bind helpers that only the parity replay calls
- **Where:** `backend/internal/compositor/render/actions.go:22` (`Supported`), `backend/internal/compositor/render/actions.go:36` (`AppliesUnder`), `backend/internal/compositor/render/actions.go:43` (`KeySupported`), `backend/internal/compositor/render/actions.go:63` (`HasCalls`), `backend/internal/compositor/render/actions.go:81` (`ArgumentKind`), `backend/internal/compositor/render/layer.go:29` (`Hex`), `backend/internal/compositor/render/shared_test.go:212`
- **What:** No daemon code calls these: `grep -rnw` over the non-test Go finds each only at its definition (or `Supported`/`KeySupported` inside `AppliesUnder`). Their only callers are `shared_test.go`'s op rows replaying the shell's `BindActions.*` / `CompositorLayer.hex`, which the shell keeps using itself (`KeybindManager.qml`, `KeybindEditor.qml`). Deletion pass, 36 lines (actions.go 20-45, 62-63, 80-83; layer.go 28-31) plus six op rows; the replay skips ops with no row (`if !ok { continue }`), so the cases still pass. (`UserKeyCounts`, the same kind, is in "The Hyprland Go code keeps dead and doubled helpers".) Fix: delete them and their rows.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### sway and niri each fit the shadow to axiom's themselves
- **Where:** `backend/internal/compositor/render/sway.go:510` (`SwayFxLines`), `backend/internal/compositor/render/niri.go:471` (`NiriLookNodes`), `backend/internal/compositor/render/layer.go:223` (`GaussianShadow`), `backend/internal/compositor/render/niri.go:422` (`NiriBindEntries`)
- **What:** Both writers carry the same 7 lines (`soft := truthy(get(s, "soft")) && truthy(get(s, "rgb"))`, the raw size and color, then `r, a := GaussianShadow(s); size = r; color = … + AlphaHex(a)`). Fix: `GaussianShadow(s)` returns the spec's `(size, color)`, falling back to the raw ones when not soft; each block becomes one line; output unchanged. Same pass: `NiriBindEntries`' `else if id != "" { mask = id[:len(id)-1] }` can't run (`KeyID` returns "" or an id holding `:`), 2 lines.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### The Hyprland and sway bind merges each skip half of compositor/actions
- **Where:** `backend/internal/compositor/binds/hypr.go:109` (`execAction`), `backend/internal/compositor/binds/sway.go:202` (`swayAction`), `backend/internal/compositor/binds/niri.go:56` (`commandAction`)
- **What:** sway's and niri's merges run every exec command through `actions.Default().IPCAction` first, so `axiom ipc appLauncher toggle`, `axiom lock` and `axiom restart` become the `launcher`, `lock` and `restartShell` actions. Hyprland's `execAction` only checks the exit command and `actions.MediaAction`, then returns `"exec", command` (`grep -n 'IPCAction' binds/hypr.go` finds nothing). bind-merge.md › Where it runs says the opposite: "What a command calling axiom (`axiom ipc …`, `axiom lock`, `axiom restart`) … maps onto comes from `compositor/actions`". The commonest real case is an included-mode user who wrote `hl.bind("SUPER + D", hl.dsp.exec_cmd("axiom ipc appLauncher toggle"))` and is then claimed. Probe: extracting that file gives `{"key":"SUPER + D","action":"exec","argument":"axiom ipc appLauncher toggle",…}`. The moved bind still works, but it shows on the Keybinds page as a raw exec instead of the launcher action. It also gets none of the action's call, label or section, and on a key axiom already binds, `mergeBinds` puts this exec in place of axiom's own launcher bind. The niri review found the mirror gap in sway's merge: its `exec` branch calls `IPCAction` but never `MediaAction`, so `bindsym XF86AudioRaiseVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+` moves as `exec` (no axiom OSD action, no `locked`/`repeating` defaults from `actionFlags`). Only niri's merge uses both, as niri-backend.md says all three do: the same user bind becomes an axiom action on one compositor and a shell command on another. Fix: one `actions.CommandAction(command)` (IPC, then media, else nil) called by all three merges, carrying `call`/`argument`, with a row per merge in the binds tests (`TestHyprMappingAndRawLua`: `axiom ipc appLauncher toggle` → `launcher`; sway: a `wpctl set-volume` exec → its media action).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system and the niri system

### Hyprland's remove deletes whatever hl.bind is on a site's line now
- **Where:** `backend/internal/compositor/binds/hypr.go:455` (`extractHypr`'s sites), `backend/internal/compositor/binds/hypr.go:507` (`removeHypr`), `backend/internal/compositor/binds/binds.go:174` (`readSites`)
- **What:** sway's and niri's sites carry the line's `text` (sway.go:327, niri.go:228), and `removeMarked` leaves a line whose text changed since extract (`changed`). Hyprland's sites carry only `file` and `line`, and `removeHypr` keeps only `s.line` (hypr.go:507). It reports `changed` only when no `hl.bind`/`hl.unbind` statement starts on that line any more (hypr.go:544). So if the file changes between extract and remove, and each site's line still holds some `hl.bind`, other binds are deleted. The window is the isolated child's run (up to 30 s) plus the commit; an editor save or a dotfiles sync can land in it. Probe: extract `binds.lua` = `SUPER + Y` (line 1), `SUPER + U` (line 2). Then the file gains `hl.bind("SUPER + Z", …exec_cmd("mine"))` at the top, and remove runs on the old sites. Result: `{"removed":2,"failed":[]}`, and the file is left with only `hl.bind("SUPER + U", …)`. Z, which was never moved, is deleted and is not in axiom. U is in axiom and still in the file, so it is bound twice, which bind-merge.md › Committing and removing says can't happen. The merge reports success, and only the dated backup has Z. This breaks C3 ("remove gives back exactly what was there"). Fix: put each statement's source text (`text[start:end]` from `statementSpan`) in the hypr site as `text`, and in `removeHypr` fail a site as `changed` when the statement found at its line differs. Add a test row: the probe above, expecting `2 changed` and Z kept.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### A claim comments out axiom's start inside a long string, breaking the script
- **Where:** `backend/internal/compositor/takeover/takeover.go:352` (`adopt`), `backend/internal/compositor/takeover/kinds.go:86` (hyprland `axiomLine`)
- **What:** `adopt` checks each line on its own with `mapLines`. A line matching the unanchored `axiomLine` (`(^|[[:space:]"'/])axiom["']?[[:space:]]+run…`) gets `-- (axiom starts and loads itself now) ` put in front of it, even when the line is inside a Lua long string. The result still parses, so `keepsParsing` keeps the edit (with luac it returns true at once). Probe: hyprland.lua = `hl.exec_cmd([[\n  axiom run &\n  waybar\n]])` claims as `adopted:00-previous.lua`, with line 2 of the copy now `-- (axiom starts and loads itself now)   axiom run &` inside the string. Hyprland runs that string through `sh -c`, where `-- (axiom …` is a syntax error, so the whole script fails and waybar (and anything else the script started) no longer starts in managed mode. The same thing happens for a matching line inside a `--[[ ]]` block comment (harmless there). Fix: skip lines that start inside a string or comment. luacheck already finds those spans (`tokens`), so export a `luacheck.InCode(text) []bool` (or reuse `WholeLines(text, []int{n})`) and only mark lines where it holds. Add a takeover test row with the file above, expecting the line inside the string to be left as it was.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### An unknown IPC function word merges as a toggle
- **Where:** `backend/internal/compositor/actions/actions.go:148` (`IPCAction`), `backend/internal/compositor/actions/actions.go:115` (`calls`)
- **What:** For an `ipcActions` row with `{call}`, the pattern captures any `\w+`, and a word not in `calls` becomes `"toggle"` (`if !ok { name = "toggle" }`). The targets have other functions: `edgeMenu` has `pin`/`unpin`/`edit`/`list` (EdgeMenuManager.qml), and `nightLight`/`idleInhibit`/`screenRecord` have `status`. Probe: `IPCAction("axiom ipc edgeMenu pin left")` gives `{"action":"edgeMenu","call":"toggle","argument":"left"}`, and `axiom ipc nightLight status` gives `{"action":"nightLight","call":"toggle"}`. On sway and niri, a user's bind that pins an edge menu is merged as one that toggles it, a silent change in behaviour. TestIPCAction has no row for a word outside `calls`. The niri review reproduced it with an overlay test for `edgeMenu pin`/`unpin`, `nightLight status` and `screenRecord status`, and found the same map also accepts `open`/`show`/`enable` for every action, whatever that action's IPC target names them (`idleInhibit` has no `open`). Fix: look the word up in the action's own row of the table's `calls` (`{open, close}`) or `toggle`; anything else returns nil, so the bind stays an `exec`. That drops the Go `calls` map (2 lines); test rows (`"axiom ipc edgeMenu pin left": "null"`).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system and the niri system

### The overview stays open with nothing shown after its monitor goes away
- **Where:** `shell/WorkspaceOverlay.qml:21` (`overlayVisible`), `shell/WorkspaceOverlay.qml:30` (`open`), `shell/WorkspaceOverlay.qml:42` (`toggle`), `shell/WorkspaceOverlay.qml:90` (`shown`)
- **What:** Open the overview on monitor B, unplug B (or B goes to sleep and is removed). The `Variants` over `General.outputs` destroys B's `PanelWindow`, its `FocusGrab` with it; nothing resets `overlayVisible` (grep: it's set only in this file, at lines 34, 43, 69, 126, 155, 162, 176; `openScreen` likewise). Axiom's `FocusGrab` emits `cleared` only from its `_lost` timer or a caught outside click, both gone with the object (services/compositor/FocusGrab.qml:51-53 only unregisters). So `overlayVisible` stays true with no window showing it: the next toggle bind only sets it false (nothing visible happens; the user has to press twice), `open()` and IPC `open` return early at line 30, and when a monitor with the same name comes back the overview reappears on it unasked. PLAUSIBLE on Hyprland only for the native grab: whether Quickshell's `HyprlandFocusGrab` emits `cleared` while being destroyed (settles with a nested Hyprland, `hyprctl output remove` while open); sway is certain from the code. Fix: in the `Scope`, `readonly property bool _screenGone: !General.outputs.some(s => s.name === root.openScreen)` with `on_ScreenGoneChanged: if (_screenGone) root.overlayVisible = false`, or make `shown` the only truth by clearing `overlayVisible` in the delegate's `Component.onDestruction` when it was `shown`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Wide active is hidden in the perMonitor layout but still applies there
- **Where:** `components/bar/widgets/Workspaces/schema.yaml:56` (`wideActive`), `components/bar/widgets/Workspaces/WorkspaceCellRow.qml:73` (`_length`)
- **What:** `wideActive` (default true) shows only with `{/Workspaces.layout: [standard, grid]}` or dynamic workspaces, yet `WorkspaceCellRow._length` reads `root.properties.wideActive` unconditionally, and the perMonitor layout (and `scrolling` under sway, which works as perMonitor, workspaces.md › Layouts) uses `WorkspaceStrip` → `WorkspaceCellRow` like standard. So on perMonitor the active cell is always twice as long and the toggle that would turn it off isn't on the settings page. Every layout draws through `WorkspaceCellRow`, so there is no layout where the option doesn't apply; the showIf came from when it read `{ "/Workspaces.layout": "standard" }` (f396b28 widened it to grid but not perMonitor). Fix: delete the `x-showIf` block (schema.yaml lines 60-63, 4 lines); the dynamic-workspaces sentence in workspaces.md ("`wideActive` and `relativeNumbers` show whatever the layout") then holds for `relativeNumbers` alone.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### A combo lookup says nothing holds a key the search or chips hide, and offers to bind it
- **Where:** `components/views/Keybinds/Keybinds.qml:38` (`sections`), `components/views/Keybinds/Keybinds.qml:304`, `components/views/Keybinds/Keybinds.qml:311` (Bind it), `components/methods/KeybindFilter.qml:55` (`filter`)
- **What:** The lookup's id is one more term in the same `KeybindFilter.filter` call as the search and the section, modifier and source chips (all ANDed, KeybindFilter.qml:55), and both the "Nothing is bound to {0}" text and the Bind it button test only that filtered result (`root.lookupId !== "" && root.sections.length === 0`). The search and chips live in `KeybindManager.page`, so they survive the page. Scenario: the search still holds "firefox" (or the "Your binds" chip is on), the user looks up SUPER + Q, which axiom binds to Close: the page says "Nothing is bound to SUPER + Q" and offers Bind it, which opens the editor with a second bind on a held key. keybinds.md says the list "offers Bind it when nothing holds it". Fix: decide "nothing holds it" from the unfiltered list, `KeybindFilter.filter(KeybindManager.keybindings, "", { "ids": [root.lookupId] }).length === 0`, for the text and the button (or clear the search and chips when a combo is looked up).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The bind inspector's typed label and argument miss Save
- **Where:** `components/views/Keybinds/BindInspector.qml:127` (`argumentText`), `components/views/Keybinds/BindInspector.qml:183` (`label`), `components/content/base/SaveResetActions.qml:41`
- **What:** The two text fields commit only on `editingFinished` (Enter or focus loss) and never call `EditsManager.holdTyping`. editors-pattern.md:15: "Typed text in a text or number box reaches the draft only on Enter, focus loss or Save, but shows Save at once: the box holds `EditsManager.typingField`, `SaveResetActions` … commit or drop it first." Save is a MouseArea (`ActionButton`), so clicking it takes no focus: select a bind, change its action (draft dirty), type "Open notes" in Label, click Save. `EditsManager.commitTyping()` finds no field, `save()` writes the bind without the label, and the field still shows "Open notes". The next focus change commits it and the page goes dirty again. With only a label typed on a clean draft, Save doesn't show at all, and Discard leaves the text in the field. PLAUSIBLE (an extra case, needs the shell): a click on another row rebuilds the inspector (Repeater over `[selectedIndex]`), and if the dying field doesn't emit `editingFinished` the text is lost. `SchemaTextField` guards that case with a commit in `Component.onDestruction`. Fix: on `textEdited`, call `EditsManager.holdTyping(field, field.Window.window)` and give each field `commitTyped()` (the existing setField) and `discardTyped()` (push the bind's value back), released after a commit, as `SchemaTextField` does. Also commit in `Component.onDestruction`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### Picking a key in the key map under an edit search selects a bind the list doesn't show
- **Where:** `components/views/Keybinds/KeyMapPanel.qml:31` (`pick`), `services/compositor/KeybindEditor.qml:28` (`selectBind`), `components/views/Keybinds/BindListRow.qml:74`
- **What:** The key map colours keys from every bind (`KeyMap.occupancy(KeybindManager.editor.binds, …)`), but `pick` selects an axiom key's bind with `selectBind(held.index)`, which neither clears the edit search and chips nor checks `visibleIndices`. `editBind` does both, and keybinds.md says the keyboard path clears them when they hide the bind. Scenario: the edit search holds "volume" and the user clicks SUPER + Q on the key map. The inspector opens on Close, but no row shows it, and `_revealIndex` stays set because no row ever calls `revealDone`. A row click selects with `reveal` false and doesn't reset it either. When the search is cleared later, the rebuilt row finds the stale `revealIndex` in `Component.onCompleted` (BindListRow.qml:74-77) and the list jumps to a bind picked minutes ago. After a removal or a move, that index may point to another bind. Fix: `KeybindManager.editor.editBind(held.index)` in `pick`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Renaming a saved preset after switching presets renames the wrong one
- **Where:** `components/views/Keybinds/PresetSheet.qml:39` (`choose`), `components/views/Keybinds/PresetSheet.qml:255` (`nameField`), `services/compositor/KeybindEditor.qml:746` (`renamePreset`)
- **What:** `choose(id)` refreshes the rename field only `if (!nameField.input.activeFocus)`. The preset rows are `ListEntryRow`s, whose `DragArea` is a MouseArea and takes no focus, so the field keeps its focus across a click on another preset. Scenario: click into saved preset "Work"'s name field, click saved preset "Gaming": the sheet selects Gaming but its name field still reads "Work", and Enter calls `renamePreset("saved:<gaming>", "Work")`. `renamePreset` doesn't check for a name already taken, so this leaves two presets named "Work", and a later `savePreset("Work")` overwrites whichever comes first. The guard exists for "Save current binds over it" (:264), which re-chooses the same preset and shouldn't wipe a half-typed name. Fix: keep typed text only when the preset stays the same: `if (id !== root.presetId || !nameField.input.activeFocus)`, evaluated before `presetId` is assigned.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The reference's sections and both chip rows are built while hidden
- **Where:** `components/views/Keybinds/Keybinds.qml:192`, `components/views/Keybinds/Keybinds.qml:237`, `components/views/Keybinds/Keybinds.qml:359` (the section `StreamedLoader`s), `components/content/parts/KeybindRow.qml:28` (`bindIndex`), `services/compositor/KeybindEditor.qml:336` (`bindIndexFor`)
- **What:** AGENTS.md: "nothing is built hidden". streamed-building.md:50: "A `visible: false` item is still built. Gate it with a Loader (`wanted`, `active`)", and :20 says to use `wanted` with the mode's own condition for content shown only in some mode. The section loaders and the list's filter-chip loader have no `wanted`; they sit under `visible: !root.editing && !root.keyboard`. The editor's chip loader is built on the list tab the same way. A page opened straight into the editor (Add a keybind from the layouts editor, a Cheatsheet's edit, Bind it) or into the keyboard tab therefore builds every reference section. While editing, each axiom `KeybindRow` keeps `bindIndex: KeybindManager.editor.bindIndexFor(root.bind.ids)`, a `findIndex` over every bind with a `BindKeys.keyId` parse each. Every draft edit (a key recorded, a pause, a flag) re-runs it for every hidden axiom row: about rows × binds `keyId` calls per edit. Fix: `wanted: !root.editing && !root.keyboard` on the section loaders and the list chips' loader, and `wanted: root.editing` on the editor chips' loader.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### In the standard layout, a switch past `count` slides through an unrelated workspace
- **Where:** `services/compositor/CompositorManager.qml:467` (`goToWorkspace`), `services/compositor/CompositorManager.qml:566` (`nthWorkspace`), `services/ui/LauncherCommands.qml:375` (`/ws`)
- **What:** The legs are planned whenever the *current* workspace is inside the block (`from >= 0 && from < size`), never checking the target. The standard layout has no block refusal (`perMonitorBlocks` false), so ids past `count` reach it: the default binds call `workspaces nth 1`..`10` (config.schema.json's `workspaceNth` defaults), which in the standard layout is `goToWorkspace(n)`, and `/ws 15` or `workspaces go 15` do the same. `cols` is `WorkspacesConfig.columns`, which is `count` outside the grid, so a target past the one row gets a sideways leg into the current row and a vertical leg on. The leg code run with real values: count 5, on workspace 3, Super+7 → `[{id:2,axis:"x"},{id:7,axis:"y"}]`; count 10, on 3, `/ws 15` → `[{id:5,axis:"x"},{id:15,axis:"y"}]`. Hyprland (the only backend with `workspaceSlide`) shows workspace 2 (or 5) — creating it if empty — then slides vertically in a layout the code's own comment says "only ever slide[s] sideways". Fix: plan legs only when both ends are in the block: `from >= 0 && from < size && to >= 0 && to < size`; otherwise one plain leg.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Where the compositor can't mirror, a profile's mirror can't be turned off or its monitor placed
- **Where:** `components/views/Monitors/MonitorInspector.qml:230` (Mirror row `shown`), `components/views/Monitors/MonitorInspector.qml:251`, `components/views/Monitors/MonitorInspector.qml:268` (X/Y `shown: !root.rule?.mirror`), `components/views/Monitors/MonitorCanvas.qml:19` (`others`), `services/compositor/MonitorManager.qml:275` (`issues`)
- **What:** monitors.md › Profiles: "a profile saved under one compositor is picked under another". A profile saved under Hyprland with a mirrored monitor (`mirror: "desc:…"`), opened on sway or niri (no `supports.monitorMirror`): the Mirror row is hidden (`shown: CompositorManager.supports.monitorMirror === true && (…)`), and the X/Y rows are hidden because `mirror` is set. The canvas lists the monitor as "mirrors X" under the board, not as a tile (`placedRules` drops mirrors), so it can't be dragged or moved, and the overlap and island checks skip it, though neither sway.go nor niri.go renders `mirror` (grep finds none), so that compositor lights it at its saved x/y. If X is off, the error "mirrors a monitor that isn't shown" (MonitorManager.qml:275) blocks Apply, and nothing on the page can clear it. Fix: let a set mirror always be turned off: `shown: !!root.rule?.mirror || (CompositorManager.supports.monitorMirror === true && mirrorField.targets.length > 0)`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The workspace strips' panel property is never read
- **Where:** `components/bar/widgets/Workspaces/WorkspaceStrip.qml:20` (`panel`), `components/bar/widgets/Workspaces/WorkspaceGridStrip.qml:21` (`panel`), `components/bar/widgets/Workspaces/Workspaces.qml:46`, `components/bar/widgets/Workspaces/Workspaces.qml:58`
- **What:** Both strips declare `property var panel` and `Workspaces.qml` sets it, but neither file reads it (`grep -c panel` is 1 in each strip: the declaration); popouts go through `PopoutAnchor { hitArea }`. Nothing else instantiates the strips (only Workspaces.qml:44 and :56). Fix: delete the two declarations and the two `panel: root.panel` lines (4 lines).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Three copies of the wheel-notch accumulator
- **Where:** `components/bar/widgets/Workspaces/WorkspaceStrip.qml:106` (`WheelHandler`), `components/bar/widgets/Workspaces/WorkspaceGridStrip.qml:102` (`WheelHandler`), `components/hosts/overlay/OverlayPageNavigator.qml:65` (`WheelHandler`)
- **What:** Each holds the same `WheelHandler { acceptedDevices: Mouse | TouchPad; property real _accumulated; onWheel: add angleDelta.y (else .x), return under 120, act on the sign, reset }` (15 + 16 + 14 = 45 lines); AGENTS.md › UI conventions: "a second copy of a pattern becomes a shared piece". Fix: a shared `NotchWheel` in components/reusable/ (a `WheelHandler` with `signal stepped(int direction)`, -1 for up/left), each user becoming `NotchWheel { enabled: …; onStepped: d => … }` (about 4 lines each): about 30 lines fewer, the same 120 threshold and reset in one place.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### The key map and the keyboard reference each carry the same modifier chips and legend
- **Where:** `components/views/Keybinds/KeyMapPanel.qml:57`, `components/views/Keybinds/KeyMapPanel.qml:82`, `components/content/parts/KeyboardReference.qml:46`, `components/content/parts/KeyboardReference.qml:75`
- **What:** KeyMapPanel.qml:57-71 (15 lines) and KeyboardReference.qml:46-61 (16) are the same `Flow` of `KeyNames.modifiers` `SegmentButton`s toggling `KeybindManager.page.keyMapMods`. The only differences are `visible: root.showMods` and `root.mods` for `keyMapMods`. KeyMapPanel.qml:82-111 and KeyboardReference.qml:75-104 (30 lines each) are the same colour legend (a swatch `Rectangle` from `root.fill(source)` plus a label). Only the entry list differs ("paused" is in one only) and Flow/Row. Both also define the same `inkOf` rule. That is about 45 repeated lines around one shared part (`KeyboardMap`, "through hooks"). Fix: give `KeyboardMap` a `legend: [[source, label]]` with a `fillFor: source => color` hook (fillOf/inkOf then read `fillFor(sourceOf(key))`), and the chips behind a `showMods`/`mods` pair. Each caller passes its entries and colours. That removes about 40 lines from one side and keeps both looks.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### A reference section's folded count re-derives BindRows.byModifiers' grouping
- **Where:** `components/content/parts/KeybindSection.qml:145`, `components/methods/BindRows.qml:133` (`byModifiers`)
- **What:** A folded group's count is `root.section.binds.filter(r => (r.combos[0]?.mods ?? []).join("+") === item.modelData.mods.join("+")).length`. That is `byModifiers`' own grouping rule (`row.combos?.[0]?.mods ?? []`, joined by "+") run again in the host, once per header per re-evaluation. AGENTS.md: "A methods helper's decision … is read from its output, never re-derived in a host". Fix: the header item in `items` carries `"count": group.rows.length` (KeybindSection.qml:21-24), and :145 reads `item.modelData.count`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### PresetSheet defers its re-choose a tick for a config that updates at once
- **Where:** `components/views/Keybinds/PresetSheet.qml:51`, `components/views/Keybinds/PresetSheet.qml:264`
- **What:** `saveAs` and "Save current binds over it" run `Qt.callLater(() => root.choose(…))` ("The list follows the config"). But `savePreset` → `SettingsManager.commitValues` → `ConfigManager.commit` sets `_config` synchronously (ConfigManager.qml:146) before the daemon call, so `KeybindsConfig.presets` and `savedPresets` are already current when it returns. A `Qt.callLater` standing in for an ordering the code already has is a timing hack (review lenses › design). Fix: call `root.choose(id)` / `root.choose(root.presetId)` directly and drop the comment.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The bind list's flag icons carry tooltip strings nothing shows
- **Where:** `components/views/Keybinds/BindListRow.qml:188`
- **What:** The flags Repeater's model is `[["repeating", "repeat", I18n.tr("Repeats while held")], ["locked", "lock", I18n.tr("Works while locked")], ["release", "keyboard_capslock", I18n.tr("Fires on release")]]`, but the delegate (a bare `StyledIcon`, :190-196) reads only `modelData[1]`. "Repeats while held" and "Fires on release" are used nowhere else (grep: one hit each), so they are two dead translation keys translated into every language. Fix: either drop the third element, or show it (a `StyledToolTip` on hover). Showing it is likely the intent, since the icons alone don't explain themselves.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### A reference section's title is worked out twice
- **Where:** `components/views/Keybinds/Keybinds.qml:203`, `components/content/parts/KeybindSection.qml:67`
- **What:** `section.undescribed ? I18n.tr("Undescribed") : (section.title ? I18n.tr(section.title) : I18n.tr("Other"))` is written out in the chip labels and again in the section card. A change to one (a new kind of section) leaves the chip and the card disagreeing. Fix: one `sectionTitle(section)` in KeybindManager (beside `sectionIcon`), used by both.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### niri's confirming quit moves in as an instant log out
- **Where:** `backend/internal/compositor/binds/niri.go:69` (`niriAction`)
- **What:** niri's plain `quit` asks first (`/usr/share/doc/niri/default-config.kdl:625`: "The quit action will show a confirmation dialog to avoid accidental exits"); only `quit skip-confirmation=true` doesn't. The merge maps both to `exitSession` (`node.Name == "quit" || plain`), which axiom writes as `quit skip-confirmation=true` (`render/niri.go`, `exitSession`) and `NiriManager.exitSession` sends as `Quit { skip_confirmation: true }`. A user config kept from niri's default, adopted on a managed takeover or merged from the Keybinds page, has `Mod+Shift+E { quit; }` and `Ctrl+Alt+Delete { quit; }`: after the merge either key ends the session at once, losing unsaved work, where it used to ask. The code's comment ("quit asks first unless skip-confirmation: axiom's log out doesn't") and `binds_test.go:554` take the change as intended, but nothing tells the user. Decided by the maintainer (asked 2026-10-30: "when axiom moves the user's niri binds in, niri's default Mod+Shift+E and Ctrl+Alt+Delete `quit` (which in niri shows a confirmation dialog) becomes axiom's `exitSession`, an instant log out with no confirmation. The code and a test treat this as intended. What should it do?"): "Keep a confirmation (Recommended)": "File as a bug: a moved `quit` should still confirm (axiom's power menu / a confirm step, or keep niri's own quit), not log out instantly." The audit's fix: map `quit` only with `skip-confirmation=true` (the condition becomes `quit` with that property true, or another action `plain`; dropping `node.Name == "quit" ||` alone would do the reverse, as a bare `quit` is `plain`), so a confirming quit moves as `raw` and keeps its dialog; reword the comment above it and flip the test row (`binds_test.go:554` expects `"raw"`).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the niri system

### After a sway reload, gapsOut and SwayFX's per-window blur and shadows stay off until the look changes
- **Where:** `services/compositor/SwayManager.qml:518` (`_onEvent`), `services/compositor/CompositorConfigManager.qml:243` (`_setState`), `docs/dev/compositor/sway-backend.md:90`
- **What:** On a sway config reload (Super+Shift+C, `swaymsg reload`, or in managed mode an edit to a `user/` file), SwayManager drops what the look set: `root._liveGaps = null; root._liveBlur = null;` (518-519), and it nulls `_windowEffects.blur`/`shadows` (522-526) "Until the look is sent again". But `setLiveLook` is only called from `CompositorConfigManager._setState`, and only when the look's JSON differs from the last one: `if (look !== root._lookSet && CompositorManager.backend.setLiveLook)` (243). The daemon's state `look` is `specLive`'s look (`manager.go:547`), and a reload doesn't change it, so `setLiveLook` is skipped. Nothing resets `_lookSet` (only lines 238, 243 and 244 touch it). The daemon re-sends the gaps and the SwayFX lines after the reload, so sway itself shows axiom's look. But until the user changes a look setting or reloads the shell:
  - `gapsOut` falls back to `_gaps`, which comes from `sway-text`. That text leaves axiom's own file out, so it is the user's gaps (sway's default 0 when they set none), while sway shows axiom's (default 3 + 6).
  - Every output's `reserved` (`SwayState.output` subtracts `gapsOut`) is off by the difference, and so are the bars and popouts that follow `CompositorManager.gapsOut`.
  - `blur` reverts to the config's.
  - On SwayFX, `windowCommands` with `blur`/`shadows` null leaves new windows alone. The global lines reach only the focused window, so windows opened after the reload get no blur and no shadows.

  The doc promises otherwise: "A config reload … resets blur and shadows, which the look sent after it sets again" (sway-backend.md:90).

  Fix: after each reload, CompositorConfigManager asks for the state again with `_lookSet` cleared, so the backend gets the look whether or not it changed: `Connections { target: CompositorManager; function onConfigReloaded() { root._lookSet = ""; root._fetchState(); } }`. About 5 lines.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the sway system

### A sway title-bar mouse bind moves in as a whole-window bind
- **Where:** `backend/internal/compositor/binds/sway.go:29` (`swayHarmless`), `backend/internal/compositor/binds/sway.go:288` (`extractSway`), `backend/internal/compositor/render/sway.go:245` (`swayConflictFlags`)
- **What:** sway(5) says mouse bindings "are only triggered when over the title bar" unless `--whole-window` is given. `swayHarmless` lists `--whole-window` as droppable, so a mouse bind *without* it moves in as well. axiom then writes every mouse key with `--whole-window` (`if k.Mouse { flags = append(flags, "--whole-window") }`). The i3 guide's own examples are `bindsym --release button2 kill` and `bindsym button3 floating toggle`. A probe of the worktree's extract on `bindsym --release button2 kill` gave `{"key":"mouse:274","action":"closeWindow","release":true}`, and the line was commented out. After a takeover, a middle click anywhere (a paste in a terminal) closes the window. The binds are shared, so Hyprland gets the same bind too.

  Fix: keep a mouse key whose flags lack `--whole-window` as `kept` `options` with the detail `title bar`, and add a `TestSwayExtract` row for it. About 4 lines.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### A sway exec chained with ; or , moves in as one shell command
- **Where:** `backend/internal/compositor/binds/sway.go:188` (`swayAction`)
- **What:** sway runs a bind's command as a list split at unquoted `;`/`,` (sway(5) › Command conventions). The `exec` branch (202) takes everything after `exec` as one argument (`execText(string([]rune(command)[4:]))`). A probe on `bindsym $mod+q exec notify-send bye; kill` moved it as `{"action":"exec","argument":"notify-send bye; kill"}`: the shell runs `kill` with no arguments, and the window no longer closes. `exec "foot", focus left` became an exec of `"foot", focus left`, so nothing starts. Both original lines were commented out. `TestSwayExecReadAsSwayRunsIt` covers only the quoted form, which sway keeps whole.

  Fix: before the `exec` branch, a stored command holding `;` or `,` outside quotes returns `raw` for sway, which keeps sway's behaviour. That is a small scan, plus a test row for each separator.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### A sway include path with a space breaks after a takeover
- **Where:** `backend/internal/compositor/takeover/kinds.go:196` (`swayInclude`), `backend/internal/compositor/render/sway.go:683` (`SwayManagedText`), `backend/internal/compositor/render/sway.go:694` (`SwayReleasedText`)
- **What:** sway expands an include through wordexp(3). A C probe showed a double-quoted `"<dir>/user/*"` stays literal (no glob), and an unquoted path with a space splits into two words. With a space in `$HOME` or `$XDG_CONFIG_HOME`, two things break:
  - `swayInclude` makes a relative include absolute as `quote + dir + "/" + inner + quote`, unquoted when the original was. `include conf.d/*` becomes two words and loads nothing.
  - The managed and released configs write `include ` + `SwayQuote(userDir+"/*")`. `SwayQuote` double-quotes the whole path, `*` included, so sway loads nothing from `user/`: the adopted config and every user file are dropped.

  `userconf.SwayText` still reads the quoted glob (`shellSplit`, then `glob`), so the daemon reads binds from files sway doesn't load. This is a rare path.

  Fix: quote only the folder, never the glob: one helper in render, `SwayQuote(dir+"/") + rest`, used by the three writers, plus a takeover test row and a golden row with a spaced dir.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the sway system

### A sway output rule by description misses a monitor with no serial
- **Where:** `backend/internal/compositor/render/sway.go:721` (`SwayOutputName`), `backend/internal/compositor/ipc/sway.go:122` (`Outputs`), `docs/dev/compositor/sway-backend.md:40`
- **What:** Profile rules name a monitor by `desc:<description>` by default. On sway the description is make, model and serial with every `Unknown` part left out (`describe`; `SwayState.output` does the same). `SwayOutputName` writes that text as the output's name in `output "Make Model" …`. sway matches an output by its name or its identifier, and the identifier keeps `Unknown` for a missing part (`output_get_identifier`). So for a monitor with no serial (common on laptop panels), the command names an output that never appears, and the saved profile does nothing on that monitor, both at runtime (`Outputs.Apply`) and in the files (`SwayOutputLines`). The doc's "sway's own identifier for an output" holds only when no part is `Unknown`. `outputs_test.go` covers `desc:` only with a full serial.

  PLAUSIBLE: settle it in a nested sway with a wayland-backend output (no serial). `swaymsg -t get_outputs` shows the `Unknown` part, and `swaymsg 'output "<make> <model>" scale 2'` should do nothing.

  Fix: resolve `desc:` to the connected output's name, as niri does (`connectorFor`, `render/niri.go`). Pass the details into `SwayOutputCommands` from `Outputs.Apply`, which already has them, and resolve the files' output rules the same way. Correct the doc line. [The Monitors page's Apply misses a niri-spelled monitor on Hyprland and sway](#the-monitors-pages-apply-misses-a-niri-spelled-monitor-on-hyprland-and-sway) changes the same sway branch: resolving through `sameDescription` there fixes its sway half too, so land the two together.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the sway system

### Managed mode's monitor-conflict check misses quoted and block output lines
- **Where:** `backend/internal/compositor/manager/sway.go:84` (`monitorPattern`), `backend/internal/compositor/manager/manager.go:966` (`findMonitorConflicts`)
- **What:** In managed mode, `user/` files that set monitors (they load after axiom's lines and win) should show as `monitorConflicts` on the Monitors page. sway's pattern takes the output name as `[^[:space:]]+`, so it misses the forms sway users write most for a particular monitor. Running the regex:
  - `output DP-1 mode 1920x1080` matches.
  - `output "Dell Inc. DELL U2720Q 123" mode 3840x2160` doesn't.
  - `output DP-1 {` doesn't.
  - `output 'LG 27' pos 0 0` doesn't.

  A takeover adopts the old config's output lines into `user/00-previous.conf`, so after a claim they override the Monitors page's profile with no warning. No test covers the sway pattern.

  Fix: `^\s*output\s+("[^"]*"|'[^']*'|\S+)\s+(\{|mode|res|resolution|pos|position|scale|transform|enable|disable|power)`, with a test row for each form.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### The detached layer's unbind list can drift from what sway holds
- **Where:** `backend/internal/compositor/manager/sway.go:225` (`runtimeApply`), `backend/internal/compositor/manager/sway.go:193` (`sendEach`)
- **What:** `runtimeApply` replaces and saves `SwayUnbind` (235-237) before anything is sent, and `sendEach` drops `run`'s transport failure. If the socket call fails (dial error, the 5 s timeout), neither the old unbinds nor the new binds reach sway. The old runtime binds stay bound but are no longer recorded, so a bind removed in axiom keeps firing until sway reloads.

  Second path: a reload is counted in `watchReloads`, but `SwayUnbind` is cleared only later, in `noteReload` on the manager goroutine. An apply in between still sends the old `unbindsym` lines, which can remove a key the user just bound in their reloaded config. The known entry "noteReload counts every compositor reload a second time" moves that reset into `configReloaded`; this path wants it where the reload is counted instead.

  Both are rare paths. Fix, about 10 lines: have `sendEach` report a transport error and keep the old list ahead of the new one when it does; skip a saved list whose reload count is older than `runtime.reloads`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the sway system

### Small shrinks in SwayManager
- **Where:** `services/compositor/SwayManager.qml:95` (`layersChanged`), `services/compositor/NiriManager.qml:120` (`layersChanged`), `services/compositor/SwayManager.qml:288` (`runCommands`), `services/compositor/SwayManager.qml:330` (`_lookSeen`), `services/compositor/SwayManager.qml:342` (`onActiveWindowIdChanged`), `services/compositor/SwayManager.qml:319` (`_configBlur`)
- **What:** Deletion pass, 21 lines, every behaviour kept (the compositor-parity review found `runCommands` too, noting Hyprland's `runLua` has the same shape and is filed under "HyprlandManager keeps members only it reads"):
  - `signal layersChanged` with its comment (94-95, 2 lines). It is never emitted, and the facade connects with `ignoreUnknownSignals: true` (`CompositorManager.qml:199`). niri's (`NiriManager.qml:119-120`, never emitted either) goes the same way, 2 more lines. contract.md › Signals then marks `layersChanged` optional (only Hyprland has it), and sway-backend.md drops its "`layersChanged`: never".
  - `runCommands` (287-290, 4 lines). Its only callers are SwayManager's own (339, 370); neither passes an empty line or a callback, so its filter and `callback?.(ok)` do nothing. Call `SwayIpcManager.command(lines.join("; "))` instead.
  - `_lookSeen` (328-330 and 313, 4 lines). It is always `root._windowEffects !== null`, so 334 becomes `if (!root._windowEffects)`.
  - `onActiveWindowIdChanged: _applyWindowLook()` (342, 1 line). `windows` is bound to `SwayState.ranked(…, activeWindowId)`, so `onWindowsChanged` already runs it on every focus change, and today it runs twice.
  - The blur default is written out twice (319-323 and 586-590), and `SwayState.configInfo("").blur` already holds it. That is 10 lines that become 2; keep the `fx` gate.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### Sway and niri each forward withMainBinds to the daemon
- **Where:** `services/compositor/SwayManager.qml:358` (`withMainBinds`), `services/compositor/NiriManager.qml:391` (`withMainBinds`), `services/compositor/CompositorManager.qml:399` (`withBinds`)
- **What:** Deletion pass, 10 lines. Since stage 7 both backends' `withMainBinds` are the same forward to `CompositorConfigManager.withEntries(callback)` (sway 356-360, niri 389-393), a layer whose job has shrunk to forwarding. Fix: the facade's `withBinds` calls `root.backend.withMainBinds ? root.backend.withMainBinds(callback) : CompositorConfigManager.withEntries(callback)` (only Hyprland reads its own), both forwards go, and contract.md marks `withMainBinds` optional.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### SwayConfigBinds keeps its own copy of sway's $variables
- **Where:** `backend/internal/compositor/render/sway.go:804` (`swaySet`), `backend/internal/compositor/render/sway.go:815` (`SwayConfigBinds`)
- **What:** Deletion pass, 12 lines. `userconf` already has `Vars` (`Set`, and `Expand` longest name first) and `SetLine`, and `extractSway` and `SwayText` use them. `SwayConfigBinds` re-implements all of it: `swaySet` is `SetLine` character for character, plus a names slice, a map, and a sort by length on every line. `render` can import `userconf` without a cycle. Fix: `vars := &userconf.Vars{}`, `SetLine` for `set` lines, `line = vars.Expand(line)`. That removes 18 lines (804: 1, 816-825: 10, 843-849: 7) and adds about 6, leaving one set of variable rules instead of two.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### Small shrinks in the sway writer and IPC
- **Where:** `backend/internal/compositor/manager/sway.go:203` (`setCursor`), `backend/internal/compositor/render/sway.go:478` (`numberOr0`), `backend/internal/compositor/ipc/sway.go:45` (`swayWrite`)
- **What:** Deletion pass, about 10 lines:
  - `setCursor` (203-205) sends `seat * xcursor_theme …`, but the live lines carry the same line every time (`SwayInputLines` appends `SwayCursorLine` whenever a cursor is set, `live` or not), so a cursor change sends it twice. Make it a no-op (3 lines to 1).
  - `numberOr0` (478-485) has one caller, `clampRound`. Inline it as a NaN check (8 lines out, about 2 in).
  - `swayWrite`'s tail (45-48) becomes `_, err := conn.Write(…); return err` (4 lines to 2).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### The sway extract's input-device case and isSwayFlag repeat the general rule
- **Where:** `backend/internal/compositor/binds/sway.go:37` (`isSwayFlag`), `backend/internal/compositor/binds/sway.go:288` (`extractSway`), `backend/internal/compositor/binds/sway.go:188` (`swayAction`)
- **What:** Deletion pass, about 17 lines. `--input-device=<id>` is in neither `swayFlags` nor `swayHarmless`, so the general `other` branch already keeps such a bind as `options`. The `device` boolean (288-302) exists only so the detail lists every flag instead of the unknown one, which nothing pins (`input-device` appears only in sway.go). `isSwayFlag` (37-45, 9 lines) has one caller. Fix: `slices.ContainsFunc(swayFlags, …)` inline, plus `if len(other) > 0 { push(… strings.Join(other, " ")) }`. The 17 lines at 287-303 become about 9, and `isSwayFlag` goes. `swayAction`'s `o Options` parameter is never read and goes too. These are the lines [A sway title-bar mouse bind moves in as a whole-window bind](#a-sway-title-bar-mouse-bind-moves-in-as-a-whole-window-bind) changes: land the two together.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### binds and takeover each keep their own isFile and git check
- **Where:** `backend/internal/compositor/binds/binds.go:185` (`isFile`), `backend/internal/compositor/takeover/kinds.go:215` (`isFile`), `backend/internal/compositor/userconf/niri.go:453` (`isFile`), `backend/internal/compositor/binds/binds.go:86` (`inGit`), `backend/internal/compositor/takeover/takeover.go:112` (`gitRepo`)
- **What:** Deletion pass, 11 lines. There are three identical 4-line `isFile` functions. `inGit` and `gitRepo` both run `git -C <dir> rev-parse --show-toplevel`; one keeps the answer, the other the repo. Fix: one exported `IsFile` (in `fsx`) and one `GitRepo` in a shared package, with binds' default tracker calling it. That removes two `isFile`s (8 lines) and `inGit` (3).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the sway system

### niri's overview drop moves a window's whole column and switches workspace
- **Where:** `services/compositor/NiriManager.qml:176` (`placeWindow`), `services/compositor/HyprlandManager.qml:228` (`_luaPrelude`'s `aim`)
- **What:** The same drop (`CompositorManager.placeWindow` from the overview, a tiled window dropped beside a target) does more on niri than on Hyprland and sway, in two ways. (1) The whole column moves. niri's `MoveColumnToIndex` moves the focused *column*, and nothing expels the dragged window from it first. Take workspace 1 with column 1 `[A, B]` (stacked or tabbed) and column 2 `[C]`, and drag A onto C's right side. `reinsert` is true, so no `MoveWindowToWorkspace` runs. Then `FocusWindow A` and `MoveColumnToIndex` (index `target.column - shift + 1`) move `[A, B]` past C: B goes along, and A isn't put on its own. A top/bottom drop then runs `ConsumeOrExpelWindowLeft` on A, which *expels* it, since it shares a column, rather than consuming it into C's column. Hyprland and sway move only the window (`hl.dsp.window.move({ window })`, `[con_id] move container to mark`). (2) The output switches workspace. Line 208 focuses the dragged window unconditionally, and niri's `FocusWindow` activates that window's workspace. So dropping onto a workspace that isn't showing leaves that workspace showing. Hyprland's `aim` focuses the target only `if t.workspace and t.workspace.active` (HyprlandManager.qml:228), so its drop doesn't switch, and sway's mark move changes no focus. The niri semantics are from niri's IPC docs; a live check in a nested niri would confirm. Fix: (1) when the dragged window shares its column on the same workspace, `ExpelWindowFromColumn` after the `FocusWindow` and count its new column in `shift`. (2) Read `root.activeWindowId` first, and when the target's workspace wasn't its output's active one, end with `FocusWindow` on it again.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### sway's named workspaces all share workspace id -1
- **Where:** `components/methods/SwayState.qml:129` (`window`), `components/methods/SwayState.qml:193` (`output`), `services/compositor/CompositorManager.qml:264` (`hasFullscreen`), `components/methods/DockLayout.qml:20` (`inScope`)
- **What:** On sway, a workspace without a number has `num` -1. That covers the user's own `workspace music` and axiom's `axiom-special-<name>` (with `Compositor.sway.specialWorkspaces: workspace`). Every window on any of them gets `workspaceId: -1` (`"workspaceId": ws?.num ?? -1`), and an output showing one gets `activeWorkspaceId: -1`, which is the contract's "unknown". sway's `specialWorkspaceId` is always 0. Hyprland gives a named or special workspace its own negative id, so the same consumers work there. Two scenarios on sway. (1) A fullscreen video on the special group's workspace or a named one: `hasFullscreen` filters -1 out (`.filter(id => id !== -1 && id !== 0)`) and answers false. The dock's trigger strip, toasts, edge popouts and the blur pause then behave as if nothing were fullscreen, against the rule "nothing draws over fullscreen". (2) A dock or the switcher scoped to `workspace` while a named workspace shows: `inScope` compares `win.workspaceId === workspaceId`, and -1 === -1, so it lists the windows of every named workspace on every output. Fix: give a named sway workspace an id of its own that no layout uses, as Hyprland does, e.g. minus its con id. Use it for both a window's `workspaceId` and the output's `activeWorkspaceId`. Update `tst_SwayState` `test_outputOnANamedWorkspace` and add a window row.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### sway lists disabled outputs as outputs
- **Where:** `services/compositor/SwayManager.qml:26` (`outputs`), `services/compositor/CompositorManager.qml:635` (`_bases`), `services/compositor/CompositorManager.qml:666` (`_orderedOutputs`)
- **What:** `SwayManager.outputs` maps every `I3.monitors` value without checking `active`. sway's `get_outputs` lists disabled outputs too (`active: false`, rect 0×0), and `SwayState.output` doesn't filter them. Hyprland's `Hyprland.monitors` and `NiriState.outputs` (`if (!logical) continue`) list only enabled ones. Scenario on sway: a laptop with its panel off (`output eDP-1 disable`, clamshell), one external monitor, the `perMonitor` layout and no profile. `blockBases` gives the disabled panel a block, and sorting by `MonitorLayout.outputId` can put it first. The external monitor's workspaces are then 11–20 on sway, where Hyprland and niri give it 1–10. A layout change's remap (`_orderedOutputs` → `SwayManager.applyRemap`) also focuses the disabled output. PLAUSIBLE: depends on Quickshell's I3 module making a monitor for an inactive output; settle it in a nested sway with `swaymsg output HEADLESS-2 disable`, then read `CompositorManager.outputs`. Fix: `I3.monitors.values.filter(m => m.lastIpcObject?.active !== false).map(…)`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### niri doesn't send windowFocused for a window that opens focused
- **Where:** `services/compositor/NiriManager.qml:625` (`_event`), `services/system/NotificationManager.qml:330` (`onWindowFocused`)
- **What:** The contract's `windowFocused(appId)` fires on Hyprland's `activewindow` and sway's `window` focus events, both sent when a new window maps focused. niri sends no `WindowFocusChanged` then. The window arrives as `WindowOpenedOrChanged` with `is_focused: true`: in the captured stream, `tests/fixtures/niri/events.jsonl` line 10, window 6 "foot" opens focused, and no `WindowFocusChanged` names it. `NiriState.reduce` moves the focus, so `activeWindowId` is right, but `_event` emits `windowFocused` only in its `WindowFocusChanged` case. Scenario: `clearOnFocus` is on, an app sends a notification, and the user starts that app. On Hyprland and sway its notifications go when its window opens. On niri they stay until focus leaves the window and comes back. Fix: emit when `NiriState.focusedWindowId` changes between `before` and the new state, for every event but the stream's initial `WindowsChanged`, replacing the `WindowFocusChanged` case.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### sway's merge moves workspace binds as raw sway commands
- **Where:** `backend/internal/compositor/binds/sway.go:188` (`swayAction`), `backend/internal/compositor/binds/niri.go:75` (`niriNumbered`), `backend/internal/compositor/binds/hypr.go:147` (`mapDispatcher`)
- **What:** Hyprland's merge maps `focus` and `window.move` `{ workspace = N }` to `workspaceNth` and `moveWindowNth`, and niri's maps `focus-workspace N` and `move-column-to-workspace N` the same way. `swayAction` knows only `kill`, `fullscreen`, `floating`, `sticky`, `layout toggle split`, `move position center`, `exit`, `focus` and `move` with a direction, and `exec`. Everything else is `raw` with `compositor: sway`. A probe extract gives `{"key":"SUPER + 1","action":"raw","argument":"workspace number 1","compositor":"sway"}`, where niri and Hyprland give `workspaceNth`. Every sway config derived from `/etc/sway/config` binds `$mod+1…0` and `$mod+Shift+1…0` this way. axiom's defaults hold those keys (`super-1` … `workspaceNth`), so `MergeBinds` puts the 20 raw binds in place of axiom's. Then: (1) on sway they bypass axiom's workspace layout (`CompositorManager.nthWorkspace`: per-monitor and grid blocks) and go to sway's global workspace N. (2) The binds are shared across compositors, and every other writer skips a raw sway bind, so the same config.json on Hyprland or niri leaves those 20 keys bound to nothing. (3) The Keybinds page lists them as raw commands, not "Workspace 1". Fix: in `swayAction`, `workspace [number] N` → `workspaceNth`, `move [container|window] [to] workspace [number] N` → `moveWindowNth`, and `workspace next|prev` (and `move … workspace next|prev`) → `workspaceStep` / `moveWindowStep`. Anything else stays raw as now. Add a `TestSwayExtract` row each.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### "Fire on release" is offered on niri and silently dropped
- **Where:** `backend/internal/compositor/render/niri.go:332` (`NiriBindNode`), `components/views/Keybinds/BindInspector.qml:209`, `backend/internal/compositor/render/hyprconfig.go:144` (`BindLua`)
- **What:** For a bind's `release` flag, Hyprland writes `release = true` and sway `--release`. `NiriBindNode` writes only `hotkey-overlay-title`, `repeat`, `allow-when-locked` and `cooldown-ms`, and reads no `release` (`grep -n release render/niri.go` hits only a comment): niri has no release binds. Nothing gates the flag: no `supports` key and no `isComplete` issue. The inspector's "Fire on release" switch is shown and saved on every compositor. Scenario on niri: a user turns it on for a bind, or a bind merged from sway or Hyprland arrives with `release: true`. axiom's own `restartShell` and `exitSession` defaults are release binds too. The action fires on press while the switch still reads on. Fix: a `releaseBinds` supports key (true on Hyprland and sway) that greys out the switch where it's false. axiom's release defaults then work on niri as press binds.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### The Monitors page's Apply misses a niri-spelled monitor on Hyprland and sway
- **Where:** `backend/internal/compositor/manager/outputs.go:49` (`Outputs.Apply`), `backend/internal/compositor/render/hyprlua.go:413` (`MonitorCalls`), `backend/internal/compositor/render/profiles.go:45` (`spelled`), `services/compositor/MonitorManager.qml:322`
- **What:** `hyprland/monitors.md` says a profile saved under one compositor is picked under another, and that "the daemon writes and applies such a rule in the running compositor's spelling (`render.SavedRules`)". That holds for the daemon's own profile switch (`SavedRules` → `spelled`). It doesn't hold for `outputs.apply`, which the Monitors page's Apply uses: it sends the profile's rules unchanged (`MonitorManager.qml:322`). The same `desc:PNP(AOC) …` rule (niri's spelling of a make it has no name for) gives three results. niri resolves it (`NiriOutputRequests` → `connectorFor`, through `sameDescription`). Hyprland gets `hl.monitor({ output = "desc:PNP(AOC) …" })`, because `MonitorCalls` resolves only a rule's `mirror` (416-420), never its `output`, and that misses Hyprland's "AOC …". sway gets `output "PNP(AOC) …" enable …`, which it stores for an output that doesn't exist and answers success. Scenario: a profile saved under niri for an AOC monitor, applied under sway or Hyprland. The page matches it as live (`MonitorLayout` strips `PNP(…)`), Apply reports nothing wrong, the monitor doesn't change, and the Keep/Revert countdown runs over nothing. Fix: in `Outputs.Apply`, put each rule through `render.spelled` against `details` before the Hyprland and sway branches (export it as `render.Spelled`). For sway, [A sway output rule by description misses a monitor with no serial](#a-sway-output-rule-by-description-misses-a-monitor-with-no-serial) resolves `desc:` to the connector, which covers this too: land the two together.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### Three settings stay editable on niri though its writer drops them
- **Where:** `config/schema/definitions/shared/Blur.yaml:73` (`contrast`), `config/schema/sections/WindowLook.yaml:259` (`opacity.fullscreen`), `config/schema/sections/WindowBehaviour.yaml:19` (`focusOnActivate`), `backend/internal/compositor/render/niri.go:462` (`NiriLookNodes`)
- **What:** compositor/README.md › Hiding what a compositor can't do: settings a compositor can't apply are gated by `x-showIf`/`x-enabledIf` on a capability. These three are gated only on keys niri sets, or not at all. So on niri each is shown, editable, and does nothing, while Hyprland and sway honour it. Blur contrast has `x-enabledIf: {/$supports.windowBlur: true}`: Hyprland writes `decoration.blur.contrast` and SwayFX `blur_contrast`, while `NiriLookNodes` writes only `passes`, `offset` and `noise`. Fullscreen opacity has `x-enabledIf: {/$supports.windowOpacity: true}`: Hyprland writes `decoration.fullscreen_opacity`, sway sets it per window, and niri's opacity rules read only `active`/`inactive`. niri-backend.md says "no fullscreen opacity", but the page doesn't. `focusOnActivate` has `hyprland` and `sway` `x-compositor` specs, no `niri` one and no gate. Scenario under niri: Fullscreen opacity 100 with active 90 leaves a fullscreen video at 90 %, while the setting reads as applied. Fix: a supports key each where niri lacks the option (`blurContrast` for Hyprland and SwayFX, `fullscreenOpacity` for Hyprland and sway), or a `niri` spec where niri has one (`focusOnActivate`; otherwise a key too).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### Mouse speed, acceleration and left-handed reach the touchpad only on Hyprland
- **Where:** `config/schema/sections/Input.yaml:115` (`mouse.accel`), `config/schema/sections/Input.yaml:128` (`mouse.sensitivity`), `config/schema/sections/Input.yaml:139` (`mouse.leftHanded`)
- **What:** The Mouse part's three fields are written as Hyprland's global `input.accel_profile` / `input.sensitivity` / `input.left_handed`, which apply to every pointer device, the touchpad included. sway's are `input type:pointer …`, which a touchpad (`type:touchpad`) doesn't match, and niri's are `input.mouse.*`. Scenario on a laptop: Mouse › Pointer speed −50 slows the touchpad on Hyprland and leaves it alone on sway and niri, and Left-handed swaps the touchpad's buttons only on Hyprland. No supports key or description says so. Decided by the maintainer (asked 2026-10-30: should the Mouse part reach the touchpad?): "Mouse and touchpad settings need to be seperate (i.e. one should be able to turn on mouse acceleration for touchpad only and adjust it seperatly)."
  Hyprland sets these only globally (`input.*`, every pointer) or per device by name (no device rules exist in render), so a touchpad apart from the mouse there needs a design first; sway's `type:touchpad` and niri's `input.touchpad` have the fields.
- **Size:** needs a plan
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### sway and niri build output details and descriptions twice
- **Where:** `components/methods/SwayState.qml:183` (`output`), `components/methods/SwayState.qml:298` (`outputDetails`), `components/methods/NiriState.qml:135` (`description`), `components/methods/NiriState.qml:351` (`outputDetails`)
- **What:** Deletion pass, about 12 lines. The make/model/serial description (`[make, model, serial].filter(part => part && part !== "Unknown").join(" ")`) is written three times: twice in SwayState and once as `NiriState.description`. Both `outputDetails` repeat the same mHz→Hz `rate` lambda, the `availableModes` template (`${m.width}x${m.height}@${rate(m).toFixed(2)}Hz`) and the 13-key object (24 and 30 lines). `MonitorLayout` matches modes as strings across compositors, so the two spellings must stay identical. Fix: one pure helper (`description`, `mode(width, height, mHz)`, `detail({…})`) with a test row, used by both. It removes about 12 lines and keeps the spellings identical by construction.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### The bind merge lists user/ files three times, once per compositor
- **Where:** `backend/internal/compositor/binds/hypr.go:336` (`hyprFiles`), `backend/internal/compositor/binds/sway.go:212` (`swayFiles`), `backend/internal/compositor/binds/niri.go:128` (`niriFiles`)
- **What:** Deletion pass, about 32 lines. `swayFiles` and `niriFiles` are the same 21 lines each; `diff` shows only the name, the comment and the filter line. `hyprFiles` (13 lines) does the same with a `.lua` filter but no hidden-file filter. That's 55 lines in all. Fix: one `userFiles(o Options, keep func(name string) bool) []string` (about 20 lines, `only` handled once, hidden files always skipped) plus a one-line filter per kind. It removes about 32 lines, and Hyprland's merge stops reading a hidden `.x.lua` the managed file never loads. Do it with [Three listings of niri's user files](#three-listings-of-niris-user-files), which moves the writer's copy.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### sway's and niri's merges build a moved bind the same way twice
- **Where:** `backend/internal/compositor/binds/sway.go:309` (`extractSway`), `backend/internal/compositor/binds/niri.go:203` (`extractNiri`)
- **What:** Deletion pass, about 11 lines. Both copy the mapped action's keys into `{key}` (sway 310-313, niri 204-207). Both then apply the same repeat rule under the same three-line comment (sway 319-325, niri 214-221: `if <native repeat on> && (actions.Default().Repeating[name] || name == "raw")`): 23 lines. Fix: one `movedBind(key, action, nativeRepeat)` of about 10 lines with the comment, called from both. It keeps every output, and the next change to the rule happens once.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### The merge keeps key and variable tables render already has
- **Where:** `backend/internal/compositor/binds/hypr.go:183` (`keyID`), `backend/internal/compositor/binds/sway.go:22` (`swayMouse`), `backend/internal/compositor/binds/hypr.go:41` (`hyprDirections`), `backend/internal/compositor/binds/sway.go:30` (`swayDirections`)
- **What:** Deletion pass, about 16 lines. (1) `keyID` (15 lines) is a third key normaliser beside `render.KeyID`/`BindKeys.keyId`. It lowercases and sorts but resolves no modifier alias, so `hl.unbind("WIN + Q")` doesn't match a moved `SUPER + Q`, which `render.KeyID` would. `binds` can import `render` with no cycle. (2) `swayMouse` (3 lines) holds the same 12 entries as `render`'s `swayMouseKeys`. (3) `hyprDirections` and `swayDirections` are the same four-entry map. Fix: use `render.KeyID` in the merge (re-keying `exampleKeys` and `TestKeyID`'s rows to its spelling), export one mouse table, and share one directions map. `SwayConfigBinds`' own `$variable` expander is [SwayConfigBinds keeps its own copy of sway's $variables](#swayconfigbinds-keeps-its-own-copy-of-sways-variables).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor-parity system

### A backed toast's blur fill is at the surface opacity twice
- **Where:** `components/surfaces/notifications/ToastStack.qml:346` (the card's `BlurShape`), `shell/BlurBackingWindow.qml:168` (`fills`)
- **What:** The blur window draws each copy opaque, then applies `Appearance.surfaceAlpha` once to all of them (`opacity: Appearance.surfaceAlpha`, line 168). Every other `kind: "rect"` shape hands it a raw colour: `BarContainer.qml:541`/`:643` use `BlurShape`'s default `Theme.background`, and `IntegratedEdgeMenu.qml:190` uses `Theme.background`. The toast card hands it `Qt.alpha(Appearance.fill(Theme.background), Appearance.fill(Theme.background).a * toastCard.opacity)`, and `Appearance.fill` has already multiplied in `surfaceAlpha` (`config/Appearance.qml:113`). With translucency at 80% and blur on, a toast's fill comes out at 0.64. It is lighter than the edge popout and bar it sits beside, and lighter than the same toast unbacked (`BlurManager.fillOn`, 0.8), so its tone jumps when the blur pauses or resumes. Fix: `color: Qt.alpha(Theme.background, toastCard.opacity)`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the blur system

### A keepFill opening leaves an unfilled row in an unbacked translucent pill
- **Where:** `components/bar/BarContainer.qml:750` (`strokeHoles`), `components/bar/BarContainer.qml:771` (the keepFill paint `Repeater`)
- **What:** `keepFill` openings come from `CornerMerge` (a pill bar's end pill merging into this bar's corner) and `PillBarJoin` (a popout's side joining a pill bar). The cut is `_farHole(start, end, o.keepFill && !Appearance.translucent ? "outer" : "both")`. When translucent, `"both"` also removes the stroke's inner fringe row, and that row lies inside the pill's own fill (`from = near ? foot - row + 1 : …`). The row is painted back only when opaque (`model: Appearance.translucent ? [] : …`). Backed, the blur window fills that row, so nothing is lost. But "translucent" is not "backed". A pill is unbacked yet translucent when the window look's blur part is off with opacity below 100, on the other screens during Hyprland's or SwayFX's compositor-wide pause, and before `CompositorManager.surfacesReady`. The pill then fills itself, nothing paints the cut row back, and the surface joining end-on covers only the stroke. The result is a 1px unfilled line along the whole opening. PLAUSIBLE: a nested-compositor screenshot of two pill bars meeting at a corner settles it, with translucency at 80% and the look's blur off. Fix: cut `"both"` always, and paint the row back whenever the pill fills itself: `model: root.backed ? [] : root._openingList.filter(o => o.keepFill ?? false)`, keeping `color: BlurManager.fillOn(…)`. `_farHole`'s `"outer"` mode then has no caller and goes. At opacity 100 it draws what it does today.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the blur system

### The editable dropdown's list fills translucent over the overlay
- **Where:** `components/reusable/StyledComboEntry.qml:289` (`dropdown`'s `background`), `components/forms/SchemaComboBox.qml:107`, `config/schema/sections/WindowLook.yaml:130` (`throughWindows`' description)
- **What:** `StyledComboEntry`'s list (a text entry that also drops down a list, `editable` or not) opens as a `Popup` inside its window, as on the overlay's pages, with `color: Appearance.fill(Theme.backgroundAlt)`: at the surface opacity, over the page under it, which no blur reaches inside the window. `SchemaComboBox`'s list, the same kind of dropdown, fills solid (`color: Theme.backgroundAlt`). Below 100 the combo entry's list shows the settings under it through its rows. The inline list (`expandsInline`, in a popout or edge menu) is backed like its popout and stays as it is. Decided by the maintainer (asked 2026-10-30 whether SwayFX's tooltips and the dock's menu should fill solid): "the only problem remaining that I find about lack of blur on tooltips and popups is for textentry/dropdown boxes (the ones that allow either), the dropdown doesn't have a solid background. No need for blur on the ones that open over the overlay (i.e. these)." Tooltips and the dock's menu stay as they are; only the setting's description, "Tooltips and menus always blur what's behind them", overstates it on SwayFX, whose `SwaySurfaceBlurLines` skips the `axiom-blur-popups` group. (An earlier answer, on notifications: "notifications on swayfx are blurred and work properly between all 3 compositors. If that is what you were talking about you can remove it".) Fix: `color: Theme.backgroundAlt` in the popup's `DropdownSurface`, as `SchemaComboBox`'s; reword the description's last sentence for SwayFX.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the blur system
### SlideAnimation's fade, easing and container aliases are dead
- **Where:** `components/hosts/popout/SlideAnimation.qml:21` (`enableFade`), `components/hosts/popout/SlideAnimation.qml:22` (`easingType`), `components/hosts/popout/SlideAnimation.qml:24` (`containerHeight`, `containerWidth`), `components/hosts/popout/SlideAnimation.qml:58` (`targetX`, `targetY`), `components/hosts/popout/AttachedSurface.qml:411`, `components/surfaces/edgemenu/IntegratedEdgeMenu.qml:169`
- **What:** None of these members changes anything. Both users (the only two `SlideAnimation {`) set `enableFade: false`, so the opacity is always 1 and the fade `Behavior` (lines 111-120) never runs; `easingType` is set by no one; `containerHeight`/`containerWidth` re-set `contentWrapper`'s size to the size it already binds, since both users fill their parent; `targetX`/`targetY` are the constant 0. Fix: remove 1 + 1 + 2 + 2 + 10 lines in the file and 3 + 3 at the users, 22 lines. The 2 easing reads become `Appearance.easing` and the 4 target reads become 0. Every behaviour is kept.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the blur system

### The blur window builds stand-ins and copies it never uses
- **Where:** `shell/BlurBackingWindow.qml:303` (`blankSurface`, `blankRect`), `shell/BlurBackingWindow.qml:189` (the `cutBy` `Copies`)
- **What:** Each window builds a whole hidden `AttachedSurface` (`blankSurface`) and a `Rectangle` (`blankRect`), used only as `?? blankSurface` / `?? blankRect` while a source is going. `AttachedSurfaceCopy` already handles a null source (`visible: root.source !== null`, and every read is `root.source?.… ?? …`), and the rect mirror's `visible: src !== null` (line 365) can never be false while the stand-in is there. Separately, a `part: "fills"` window still mirrors every shape of the other window (`Copies { shapes: backing.cutBy }`) and bursts `FrameNudge` for them, though `cutByUnion` (line 38) is `backing.part !== "fills" && …`, so they are never read. That happens on SwayFX with the overlay open. Fix: `?? null` at both sites, delete lines 301-311 (11 lines), and use `shapes: backing.part !== "fills" ? backing.cutBy : []`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the blur system

### BlurBacking spells out four near-identical blur windows
- **Where:** `shell/BlurBacking.qml:58`, `shell/BlurBacking.qml:68`, `shell/BlurBacking.qml:85`, `shell/BlurBacking.qml:99`
- **What:** The four `BlurBackingWindow`s (9 + 13 + 13 + 13 = 48 lines) differ only in their shapes and `cutBy` pair, `wanted`, `held` and `stackLayer` (all set by whether they're below or over the overlay), their `part`, and their namespace, which is `(part === "shadows" ? "axiom-shadows" : "axiom-blur-backing") + (over ? "-overlay" : "")`. Fix: one inline component taking `over`, with an `Instantiator` over `shadowsApart ? ["fills", "shadows"] : ["all"]`. It is used twice, the over-overlay one under its `aboveOverlay` gate: about 25 lines in place of 48. SwayFX's map order (fills, then shadows) is kept.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the blur system

### The border frame's path is built three times
- **Where:** `shell/BlurBackingWindow.qml:379` (`frameMirror`), `components/surfaces/border/RoundedBorders.qml:112` (`shadowWindow`), `components/surfaces/border/RoundedBorders.qml:212`, `components/surfaces/border/RoundedBorders.qml:252`
- **What:** The same rounded inner-rect path (the `A ${r} ${r} 0 0 1` template) is written out three times: `BlurBackingWindow.qml:407`, `RoundedBorders.qml:219` and `RoundedBorders.qml:261`. The copies have already drifted: line 259 has no `Math.max(0, …)`, while lines 217 and 405 do. `shadowWindow`'s `radius` (line 121) repeats `root.innerRadius`, and its `left`/`right`/`top`/`bottom` (lines 116-119) only forward `root.inner*`. Fix: `RoundedBorders` exposes `innerPath` (and the frame path built from it), and the three users read it. That is about 30 lines out, 8 in.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the blur system

### Small shrinks in the blur system
- **Where:** `components/methods/SurfaceContext.qml:140` (`shadow`), `services/ui/BlurManager.qml:33` (`_wanted`), `components/views/Settings/TranslucencyStatus.qml:36`, `backend/internal/compositor/render/layer.go:202` (`SurfaceBlur`), `backend/internal/compositor/render/niri.go:506` (`NiriSurfaceBlurNodes`)
- **What:** Deletion pass, about 17 lines. (1) `SurfaceContext.shadow`'s submenu branch has no caller: `if (s.parent) return s.parent;` is never reached, because its one caller, `layout` (line 363), never passes `parent`; submenus take their parent's look in `SubPopout`, and `SurfaceContext.shadow(` appears otherwise only in tests. `layout`'s `"onBar": !p.held && …` also repeats what `shadow` checks first, since a held surface is always `detached`. Drop the branch, its 2 comment mentions, `test_submenuTakesItsParentsShadow` (11 lines) and `!p.held && `, 14 lines in all. (2) `supports.blur` is tested again after `Appearance.blur`: `Appearance.blur` needs `translucent`, which needs `compositorBlurs`, and `CompositorManager` binds that to `supports.blur === true && !Paths.greeter`, so `&& CompositorManager.supports.blur === true` in `BlurManager._wanted` and in `TranslucencyStatus` (line 36) adds nothing. (3) Two Go expressions do nothing: `or(get(surfaces, "threshold"), nil)` (`layer.go:202`) returns its first argument, since `or` returns `b` only for a nil `a`; `|| rule.Value("xray") == nil` (`niri.go:506`) can't be true, because every `SurfaceBlur` row with `blur` or `popups` sets `xray`. Fix: remove each one; output unchanged.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the blur system

### Edge and floating popouts never close when their focus grab clears
- **Where:** `components/hosts/popout/EdgePopout.qml:460` (`focusGrab`), `components/hosts/popout/FloatingPopout.qml:162` (`focusGrab`), `services/compositor/FocusGrab.qml:57` (`_outside`)
- **What:** Both hosts handle the grab ending with `onCleared: { if (!active) root.hide(); }`. Inside `FocusGrab { … }`, `active` is the wrapper's own property, bound to `surfaceWindow.visible && root.grabEnabled && (…)` (EdgePopout.qml:452) or `root.isOpen && …` (FloatingPopout.qml:154), and the wrapper emits `cleared` only while that property is true:
  - **No native grab (sway, niri):** the backdrop `Connections` is `enabled: root._catching`, which is `!_native && active`. The `_lost` timer checks `root.active && …` (FocusGrab.qml:135).
  - **Hyprland:** the inner `HyprlandGrab` clears. Its own `active` goes false, but the wrapper's binding doesn't.

  So `!active` is always false when `cleared` arrives, and `hide()` never runs. The guard dates from when the handler sat on Quickshell's `HyprlandFocusGrab` directly, whose `active` does drop. The wrapper's other users close unconditionally (`PowerMenuWindow.qml:133` `onCleared: root.shown = false`, `DockMenu.qml:64` `onCleared: root.close()`).

  What users see:
  - A floating edge menu with `close.onOutsideClick` stays open on a click outside (FloatingEdgeMenu.qml:111 sets `closeOnClickOutside`).
  - The attached launcher (EdgePopout, `closeOnClickOutside: true`, Launcher.qml:191, commented "until Esc, a pick or a click elsewhere") stays open.
  - The detached launcher closes only on a click in its own window's free area (FloatingPopout.qml:169's MouseArea), not on a bar, the border or another monitor.

  Fix: `onCleared: root.hide()` in both hosts (`hide()` already checks `isOpen`).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### An open edge popout's layer and namespace still follow its edge's bar
- **Where:** `components/hosts/popout/EdgePopout.qml:94` (`slideDistance`), `components/hosts/popout/EdgePopout.qml:97` (`windowLayer`), `components/hosts/popout/EdgePopout.qml:113` (`layerNamespace`), `components/hosts/popout/EdgePopout.qml:216` (`_overlayLatch`), `components/hosts/popout/BarPopouts.qml:42` (`_under`)
- **What:** BarPopouts latches `placement.slidesUnder` in a `ClosedLatch`, so an open bar popout never changes layer. EdgePopout latches only two of that output's inputs (`_overlayLatch`, `_fullscreenLatch`) and reads `placement.slidesUnder` live. That value also depends on the edge's bar: `bar?.background === "transparent"`, from `SurfaceContext.layout`.
  - **Scenario:** a pinned floating edge menu or an OSD is open on a transparent bar's edge, and the bar's background changes or the bar goes away (`axiom config set`, an edit, a restored setup).
  - **What happens:** `slidesUnder` flips while the window shows, and with it `WlrLayershell.layer`, the namespace (`axiom-popout-under` ↔ `overNamespace`) and the margin (`slideDistance`).
  - **Rule broken:** ClosedLatch's own header ("what changes a popout's window layer or namespace … so an open popout never moves or restacks"), and AGENTS.md's "an open popout never moves".
  - PLAUSIBLE: what Hyprland does with a namespace changed on a mapped layer (ignored until a remap, or a remap) needs a nested session.

  Fix: `property ClosedLatch _under: ClosedLatch { source: placement.slidesUnder; closed: !root.occupied }`, read in `slideDistance`. Then `placement.overOverlay` can take `root.overlayOpen` directly, and `_overlayLatch`/`_overOverlay` (EdgePopout.qml:216-220, 5 lines) go.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### EdgePopout works out its attach edge and slide distance itself
- **Where:** `components/hosts/popout/EdgePopout.qml:204` (`attachBase`), `components/hosts/popout/EdgePopout.qml:94` (`slideDistance`), `components/methods/SurfaceContext.qml:340` (`layout`)
- **What:** `attachBase = ScreenEdgeManager.reservedWithMenusOn(screen, edge) - (bareEdge ? 0 : Appearance.borderWidth)` repeats `SurfaceContext.layout`'s no-bar `attachAt` branch, and it is read by `edgeOffset` and by FloatingEdgeMenu's `before` gap (`components/surfaces/edgemenu/FloatingEdgeMenu.qml:63`). `slideDistance` subtracts `barConfig?.insideBorder ? Appearance.borderWidth : 0`, a stroke rule `layout` doesn't return. That breaks components/hosts/popout/AGENTS.md: "Never add a rule in a host: a new case is a `SurfaceContext` rule plus a `tst_SurfaceContext` row". A change to either rule in SurfaceContext would leave the edge popout's window apart from its box. Fix: `layout` returns the attach base and the slide distance, with `tst_SurfaceContext` rows; EdgePopout reads both from `placement`, and keeps `attachBase` as that output for FloatingEdgeMenu. Both this and [An open edge popout's layer and namespace still follow its edge's bar](#an-open-edge-popouts-layer-and-namespace-still-follow-its-edges-bar) change `slideDistance`: take them in one batch.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### A tray submenu longer than the screen runs off it
- **Where:** `components/content/parts/TraySubmenu.qml:14` (`implicitHeight`), `components/content/parts/TrayMenuList.qml:29` (`implicitHeight`), `components/hosts/popout/SubPopout.qml:133` (`maxContentHeight`)
- **What:** SubPopout gives submenu content the room it has (`maxContentHeight`, from `screenFrom`/`screenTo`), and submenus.md says "content that may be taller … scrolls past `maxContentHeight`". Only `Submenu/MenuSubmenu.qml:46` reads it. `TraySubmenu`'s height is `menuList.implicitHeight`, and `TrayMenuList` is a bare ColumnLayout with no Flickable. So a tray submenu with more entries than fit (about 25 or more on a 1080 px screen) is as tall as all its entries. `SurfaceContext.submenuPlace` clamps only its start, so the box runs past the screen's bottom and the last entries can't be reached. Fix: `TrayMenuList` takes a `maxHeight` (unbounded by default) and wraps `menuLayout` in a Flickable as MenuSubmenu does; TraySubmenu passes `root.wrapper.maxContentHeight`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### The Updates popout's package list is frozen at opening
- **Where:** `components/bar/widgets/Updates/Updates.qml:54` (`extraData`), `components/content/Updates/Updates.qml:20` (`repoPackages`), `components/content/Updates/Updates.qml:21` (`aurPackages`), `components/hosts/popout/BarPopouts.qml:547`
- **What:** The widget sends `repoPackages`/`aurPackages` as `extraData`. BarPopouts copies each key once in `onLoaded` (`item[key] = root.currentData[key];`), which replaces the panel's live bindings (`property var repoPackages: UpdatesManager.repoPackages`) with the arrays as they were at opening. `PopoutAnchor.open()` returns early while the popout is open.
  - **Scenario:** with the popout open, right-click the widget (`UpdatesManager.refresh()`), or let an upgrade finish in a terminal. The bar's count changes, but the popout still lists the old packages, or still says it's up to date, until it is reopened.
  - **Why the keys exist:** only to apply the widget's AUR filter.

  Fix: delete the widget's `extraData` (4 lines). The panel's `aurPackages` binds the same filter itself (`UpdatesConfig.includeAur && UpdatesManager.hasAur ? UpdatesManager.aurPackages : []`), which cards then share; both properties become `readonly`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### NowPlaying builds its strip layout and a second transport hidden in every mode
- **Where:** `components/content/NowPlaying/NowPlaying.qml:330` (the strip), `components/content/NowPlaying/NowPlaying.qml:440` (the grid's `Transport`), `components/content/NowPlaying/NowPlaying.qml:453` (the popout's `Transport`)
- **What:** components/content/AGENTS.md says "a part shown in one mode only is a Loader gated on it, not `visible: false`". All three parts here are gated by `visible` only:
  - The strip `RowLayout` (lines 329-402, 74 lines, `visible: root.hasPlayer && root.mini`) shows only in a short card. It is built in the Media popout and in every other card too, including its `Art`, whose CrossFade decodes the cover once more while hidden.
  - The grid's `Transport { visible: root.embedded }` is built in the popout.
  - The popout's `Transport { visible: root.hasPlayer && !root.embedded }` is built in every card.

  So each opening of the Media popout builds a seek slider, two time labels and three buttons it never shows, and a hidden cover decode, a third beside the two [Images decoded at full size or more than once](#images-decoded-at-full-size-or-more-than-once) counts. Fix: Loaders gated on `root.mini` for the strip and grid, and on `root.embedded` / `!root.embedded` for the two transports (Layout attached properties on the Loaders). Fix it together with NowPlaying's thresholds in [the sizing entry](#eight-modules-full-layouts-need-more-room-than-their-fullmin-sizes-even-inside-the-padding): the Loaders gate on the `mini`/`short` switches that entry recomputes. The compact play `MediaButton` also lacks the `enabled: MediaManager.canTogglePlaying` its two siblings have (modules review, 2026-10-31).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### PopoutWrapperBase's aboutToDismiss signal has no listener
- **Where:** `components/hosts/popout/PopoutWrapperBase.qml:161` (`aboutToDismiss`)
- **What:** A repo-wide grep for `boutToDismiss` finds only the declaration, its example comment (line 160) and the emit in `requestDismiss` (line 165); no wrapper handles it. Fix: delete the comment and signal (159-161) and the emit (165): 4 lines.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### Three EdgePopout members nothing reads
- **Where:** `components/hosts/popout/EdgePopout.qml:80` (`detached`), `components/hosts/popout/EdgePopout.qml:149` (`yielded`), `components/hosts/popout/EdgePopout.qml:191` (`gaps`)
- **What:** Each forwards `placement.*` or `claim.*`, and nothing reads them on an EdgePopout. Internal users read `placement`/`claim` directly. `SubmenuHost`'s `geometry.detached` is EdgePlacement's, and the only outside mention is FloatingEdgeMenu.qml:25's comment `(EdgePopout.gaps)`. Fix: delete lines 77-80 (`detached` and its comment), 149 and 191 (6 lines), and point that comment at `EdgePlacement.gaps`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### PopoutGeometry handles a phase and a submenu pair the registry never produces
- **Where:** `components/methods/PopoutGeometry.qml:81` (`resolve`), `components/methods/PopoutGeometry.qml:120` (`resumable`), `tests/tst_PopoutGeometry.qml:115`
- **What:** Two branches handle cases nothing produces:
  - **The "closing" phase:** PopoutManager writes only the phases "open" and "yielded", plus "opening" through `resumable`. A grep for `"closing"` over services/, components/ and tests/ finds only PopoutGeometry's comment (line 17), lines 81 and 120, and the test.
  - **The sibling-submenu skip** (lines 89-91, `e.kind === "submenu" && claim.parentId && e.parentId === claim.parentId`): it needs two submenu claims with one parent. A submenu's key is its parent's plus `/submenu`, with one SubPopout per host, so the only such entry is the claim itself, which line 79 already skips.

  Fix: drop both `"closing"` clauses, lines 89-91, the comment's "closing" part and the test's "gone" row (about 6 lines).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### PillBarJoin's available repeats what joined already says
- **Where:** `components/hosts/popout/PillBarJoin.qml:45` (`available`), `components/methods/SurfaceContext.qml:114` (`end`), `docs/dev/popouts/pill-and-floating-bars.md:34`
- **What:** `available` asks `ScreenEdgeManager.surfaceEnd(screen, side).kind === "pillBar"` again. EdgePlacement sets `joined` from `place.joinStart && startEnd.sink === "pillBar"`, and `SurfaceContext.end` gives sink `"pillBar"` only when `joins && e.kind === "pillBar"`. So `joined` implies `available` wherever both are read. The doc's "Its `available` is what makes the end joinable" is wrong too. Fix: drop lines 43-45 and the two `available` terms, and point the doc at `sink: "pillBar"`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### Geometry members nothing reads
- **Where:** `components/hosts/popout/AttachedSurface.qml:330` (`sideU`), `components/hosts/popout/AttachedSurface.qml:331` (`farSideU`), `components/hosts/popout/EdgePlacement.qml:225` (`merged`), `components/methods/SurfaceOutline.qml:97` (`size`)
- **What:** No `.sideU`/`.farSideU` read of AttachedSurface and no `.merged` read of an EdgePlacement exist. `SurfaceOutline.size` is called only by `tests/tst_SurfaceOutline.qml` (lines 146, 329), while AttachedSurface works the size out again itself. Fix: delete the three properties (3 lines). Then either AttachedSurface takes its implicit size from `SurfaceOutline.size(root._spec, root._m)`, or `size` goes (lines 95-103, 9 lines) and the tests inline it.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### SurfaceContext.layout's pill and merged results have no test row
- **Where:** `tests/tst_SurfaceContext.qml:553` (`test_layout_between_pills`), `components/methods/SurfaceContext.qml:337` (`layout`)
- **What:** No row pins `layout`'s result for:
  - a box on a pill: `backfill` 1, `attachFromBar` = pill foot, `ownSink` null, shadow look `"bar"`. The one pill-mode row checks only `mode` and `pill.index`.
  - a pill bar showing no pills (`merged`): `attachClearance`, `straight`, `ownSink`.
  - `ownSink`'s null branches: a bare edge and a non-solid bar.

  A slip in any of these passes today (63 rows pass). A lost backfill shows the pill stroke's fringe as a line; a wrong `attachClearance` puts a merged box's content where the pills would be. Fix: add `test_layout_on_pill`, `test_layout_merged` and a bare-edge `ownSink` row.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### The tray menu's isVertical and barConfig are never read
- **Where:** `components/content/SystemTray/SystemTray.qml:14` (`isVertical`), `components/content/SystemTray/SystemTray.qml:15` (`barConfig`), `components/bar/widgets/SystemTray/SystemTray.qml:99`
- **What:** The tray content declares both from its payload and nothing reads either: no host reads them off `currentItem`/`currentData`, and inside the content only the declarations match. The widget's `extraData` sends them only to feed these. Fix: drop the two properties and the two `extraData` keys (4 lines).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### Both tray menu lists override the same width cap
- **Where:** `components/content/parts/TrayMenuList.qml:22` (`maxWidth`), `components/content/SystemTray/SystemTray.qml:38`, `components/content/parts/TraySubmenu.qml:21` (`_window`), `components/content/parts/TraySubmenu.qml:34`
- **What:** TrayMenuList's only two users both replace its default `Widget.px(600)` with the same stand-in, 30% of the screen's width: `(root.wrapper.screen?.width ?? 2000) * 0.3` and `(root._window?.screen?.width ?? 2000) * 0.3`, each marked `// fixed px`. TraySubmenu keeps `_window` only for this, and the default is never used. Fix: make the stand-in TrayMenuList's default, read through its own `QsWindow.window`, and drop SystemTray.qml:38 and TraySubmenu.qml:20-21 and 34 (4 lines).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### The tray menu draws its own separator
- **Where:** `components/content/parts/TrayMenuItem.qml:99` (the separator `Rectangle`)
- **What:** A separator entry draws a hand-made line (lines 98-106, 9 lines: `height: 1`, `color: Theme.foreground`, `opacity: 0.2`). docs/dev/core/shared-ui-pieces.md lists `StyledSeparator` ("border-coloured divider"), and AGENTS.md says "Reuse before building". It is the only popout divider that ignores the theme's border colour and width. Fix: `StyledSeparator { anchors.centerIn: parent; width: parent.width - root.itemPadding * 2; visible: root.menuItem.isSeparator }`, 4 lines fewer.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### The two workspace popouts share 28 lines of payload and colour properties
- **Where:** `components/content/WorkspaceStrips/WorkspaceStrips.qml:18`, `components/content/WorkspaceGrid/WorkspaceGrid.qml:18`
- **What:** `diff` shows the same payload comment and members in both files: `output`, `monitor`, `vertical`, `cellSize`, `cellLength`, `barConfig`, `cellSpacing`, `radius`, the four colours, `base` and `activeId` (23 lines), plus the `_settled` latch and its comment (5 lines). AGENTS.md: "a second copy of a pattern becomes a shared piece". Fix: a `WorkspacePopoutPanel.qml` (a `Panel`) in components/bar/widgets/Workspaces/, which both already import, holds those 28 lines. Each panel keeps only its own members (`stripVertical`/`ids`; `emptyColor`, `gridColumns`, `gridRows`, `activeIndex`). About 23 lines fewer. BarPopouts' `hasOwnProperty` copy covers inherited properties, so the payload still lands.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### Small improvements to WorkspaceGrid
- **Where:** `components/content/WorkspaceGrid/WorkspaceGrid.qml:36` (`fontSize`), `components/bar/widgets/Workspaces/WorkspaceGridStrip.qml:218`, `components/content/WorkspaceGrid/WorkspaceGrid.qml:87` (`look`), `components/bar/widgets/Workspaces/WorkspaceCellRow.qml:69` (`_look`)
- **What:** Two small fixes:
  1. **`fontSize` is dead.** `grep -cw fontSize` in WorkspaceGrid.qml is 1 (the declaration), yet the widget still sends `fontSize: root.barConfig.fontSize,`. WorkspaceCell reads `barConfig.fontSize` itself. Fix: delete both lines (2 lines).
  2. **The cell's `look` is a copy.** It repeats `WorkspaceCellRow._look`'s `BarsConfig.cellColors(…)` expression with only the variable names changed, so a change to how the bar colours cells would leave the popout behind. Fix: one `BarsConfig` function both call.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the popouts system

### The dock's footprint assumes fillets at both ends
- **Where:** `components/surfaces/dock/DockWindow.qml:298` (`_footprint`)
- **What:** The dock's collision footprint is its rest rect grown by `EdgeAttach.filletMargin` at both ends whenever it's attached. `SurfaceOutline.footprint` adds fillet squares only at filleted ends (none at joined, flush or straight ends, none on a bare edge), and it covers the backfill row. So on a bare edge the dock claims `R - half` px past each end, and PopoutGeometry reports a collision with a popout beside it that early. Fix: use the dock's EdgeSurface `footprint` mapped to the screen, and drop the hand-built one (about 6 lines).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the popouts system

### Nothing listens to the bar's layoutUpdated any more
- **Where:** `components/bar/BarContainer.qml:31` (`layoutUpdated`), `components/bar/BarContainer.qml:313` (`layoutMoved`, `_slotsKey`, `_settle`), `components/bar/BarContainer.qml:401` (`onAllocationUpdated`), `components/bar/WidgetGroup.qml:109` (`allocationUpdated`, `_allocationKey`), `docs/dev/bar/composition.md`
- **What:** The signal has no handler. `grep -rn 'layoutUpdated'` over QML and docs finds only its declaration, its two emits (BarContainer.qml:314, 320) and composition.md's "`BarContainer.layoutMoved()` emits `layoutUpdated` … so an open popout re-anchors on the settled widget". Its listener was BarPopouts' `onLayoutUpdated`, removed in "Rework and harden popouts (#53)". The chain still runs on the hot path:
  - Every `slots` change `JSON.stringify`s the slots.
  - Every section allocation change (a ticking clock's width, a tray icon) `JSON.stringify`s the allocation, emits `allocationUpdated` and calls `layoutMoved()`.
  - `layoutMoved()` emits to nobody and restarts a Timer that emits to nobody again `animNormal` later.

  Fix: delete the chain and its doc line, 35 lines: the signal and its comment (BarContainer.qml:29-31), `_slotsKey`/`onSlotsChanged`/`layoutMoved`/`_settle` (301-321), Section's `onAllocationUpdated` (401), WidgetGroup's `allocationUpdated`/`_allocationKey`/`onAllocationChanged` (108-117).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### A bar made while the bar editor is open may never report to it
- **Where:** `components/bar/BarContainer.qml:346` (`on_ReportKeyChanged`), `components/bar/BarContainer.qml:349` (`_report`)
- **What:** A bar's report reaches `BarManager.setLive` only from `on_ReportKeyChanged`, and a change handler doesn't run for a property's first value.
  - Bars that exist when the editor opens are fine: their key goes from `"null"` to the report.
  - A BarContainer created while `BarManager.editing` is already true starts with its report. On a bar with room, `hidden` stays `{zone: []}` and `selected` stays null, so the key may never change and nothing is sent.
  - The editor remakes bars often: changing a bar's Background, or moving it to the other axis, changes `BarsConfig.layerNamespace`, which `shell/Bar.qml:25` keys the window on. Adding a bar makes a new one.
  - The old container's `Component.onDestruction` clears the id, so `BarManager.liveReports` drops that bar. The board's "Fits …" line goes blank, and the lanes and inspector lose their crowded marks and sizing text.

  PLAUSIBLE: whether the first value already has `root.screen` depends on binding order. To settle it, open the bar editor, switch a bar's Background, and check that the fit line stays. Fix: `Component.onCompleted: root._report()`. `setLive` ignores an unchanged report and an empty id.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### A second bar on an edge is invisible to the screen-edge answers, and New bar makes one
- **Where:** `components/methods/BarEnds.qml:161` (`edgesOn`), `services/ui/ScreenEdgeManager.qml:91` (`barReservedOn`), `services/ui/ScreenEdgeManager.qml:206` (`barOn`), `services/ui/BarManager.qml:155` (`addBar`)
- **What:** `edgesOn` keeps only the first enabled bar on each edge (`if (!edges[edge]) edges[edge] = bar;`). Every screen-edge answer goes through it: `barReservedOn`, `frameLine`, `detachedGaps`, `surfaceEnd`, `barStartOn` and each bar's `ends`.
  - The compositors stack both bars' exclusive zones, so with two reserving bars on one edge `reservedWithMenusOn` is short by the second bar's zone.
  - Docks (`components/surfaces/dock/DockWindow.qml:60`), floating edge menus (`components/surfaces/edgemenu/FloatingEdgeMenu.qml`) and bar popouts (`EdgePlacement`) then sit under the second bar.
  - Bars on the perpendicular edges never yield to the second bar.
  - The first bar wins even when it reserves nothing. `barOn` picks by panel registration order and `edgesOn` by config order, so the two can disagree.

  The editor creates this case. `addBar` fills every field from the Bar defaults (location top, screen primary), so on the default config **New bar** stacks a second bar on the default top bar. `duplicateBar` moves its copy to a free screen "so it doesn't sit on the original", which suggests stacking isn't meant.

  **Decided** (maintainer, 2026-10-30): "Stacked bars will be planned as supported. Mark it as needs a plan and move to deferred". Fix: `edgesOn` returns every bar on an edge, and the reserved, frame-line and corner answers add them up, designed first through a plan; deferred until then.
- **Size:** needs a plan
- **Found:** 2026-10-30, while reviewing the bar system

### Plugging in or unplugging a monitor remakes the bar that stays
- **Where:** `config/BarsConfig.qml:409` (`expandBars`), `shell/Bar.qml:25`
- **What:** The id depends on how many of the bar's screens are connected.
  - A bar on every monitor (or on several named ones) keeps the plain `bar.id` while one of its screens is connected (`if (screens.length <= 1 || bar.screen.mode === "primary")`). It gets `<id>@<screen>` once two are.
  - `shell/Bar.qml` keys each `BarPanel` on `b.id + "|" + namespace`. Docking a laptop with an "Every monitor" bar changes the laptop bar's key from `bar` to `bar@eDP-1`, so its window is destroyed and rebuilt. Undocking does the same to the bar that stays.
  - That bar flickers and loses its open popout and its owner-keyed requests (`"corner:" + id`, `"barPopout:" + id`). On sway and niri, the remade bar maps after the border, which then maps the border again (layering-and-corners.md › Build order).

  Running bars already carry `sourceId` for the config entry. Fix: suffix `@<screen>` whenever `bar.screen.mode !== "primary"`, so an entry's id depends only on its screen. Check every reader that compares a running id with a config id first; `liveReports` and `isSelectedWidget` match on `sourceId`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the bar system

### Removing or copying another bar moves the editor's selection to a different bar
- **Where:** `services/ui/BarManager.qml:247` (`removeBar`), `services/ui/BarManager.qml:189` (`duplicateBar`)
- **What:** The selected bar is held only as `selectedBarIndex`, and BarsPanel offers Remove and Duplicate on every row.
  - Remove: in `[A, B, C]` with B selected, removing A leaves `selectedBarIndex` at 1 (`Math.max(0, Math.min(root.selectedBarIndex, …))`). The inspector and style groups now edit C, and the widget selection is cleared. `_moveCopied` on the line before remaps the copied style's index, but nothing remaps the selection.
  - Duplicate: with B selected, duplicating A sets `selectedBarIndex = index + 1`, still 1, so its change handler doesn't fire. B's selected widget `{zone, index}` then applies to the new copy.

  Fix: in `removeBar`, `if (index < root.selectedBarIndex) root.selectedBarIndex--;`, and clear the widget selection only when the selected bar was the one removed; `duplicateBar` calls `clearSelection()`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### A corner piece's pull-out re-derives a bar's reserve and misses its clamp
- **Where:** `components/surfaces/border/RoundedBorders.qml:39` (`cornerMargin`), `config/BarsConfig.qml:351` (`reservedZone`)
- **What:** `cornerMargin` pulls a corner piece back out over a bar inside the border "As far as the bar reserves (see BarPanel)". It works that distance out again as `-(bar.extent - reserveTrim(bar, gapsOut))`, but what `BarPanel` reserves is `BarsConfig.reservedZone`, which clamps: `return Math.max(0, barConfig.extent - trim);` (BarsConfig.qml:356). Scenario: a transparent bar inside the border on Hyprland, with `gaps_out` larger than the bar's extent (40 against 34). The bar reserves 0, but `cornerMargin` returns +6, so both corners on that edge sit 6 px in from the frame's corner. PLAUSIBLE: the code difference is certain; what gets drawn needs that setup in a nested Hyprland. Fix: read the reserve the bar sets, as `innerInset` does a few lines down: `const zone = bar?.insideBorder ? BarsConfig.reservedZone(bar, CompositorManager.gapsOut[edge] ?? 0) : 0; return (zone > 0 ? -zone : -root.strokeWidth) - docks;` (9 lines to 5).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### The pill merge in BarContainer repeats BarLayout's, untested
- **Where:** `components/bar/BarContainer.qml:96` (`sectionPills`), `components/methods/BarLayout.qml:523` (`_mergeSpans`)
- **What:** `sectionPills` hand-rolls the loop that joins spans at most `pillMerge` apart (99-107), which `BarLayout._mergeSpans` already does for islands, then decides each pill's joins in the host (`root.ends.start.joinable && m.start - gap <= reach`). That breaks composition.md (main-axis layout math lives in `methods/BarLayout`) and AGENTS.md ("A methods helper's decision … is read from its output, never re-derived in a host"). No row tests when an end pill joins. The copy also writes into `_spans`' own objects (`spans.slice()` is shallow, and `last.end = …` mutates the pushed span). Fix: a BarLayout `pillRects(spans, merge, gap, reach, length, joinStart, joinEnd)` on `_mergeSpans` (which copies), with rows for a free end, a joined end at each side, and a held end. `sectionPills` (96-126, 31 lines) becomes one call of about 3 lines.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the bar system

### StandaloneBar only wraps BarPanel's BarContainer
- **Where:** `components/bar/StandaloneBar.qml:7`, `components/bar/BarPanel.qml:127` (`bar`), `components/bar/BarContainer.qml:215` (`borderOpening`), `components/bar/BarContainer.qml:515` (`blurOrigin`)
- **What:** Its header calls it "A bar's BarContainer outside a window of its own", but nothing draws a bar outside a window any more. BarPanel is its only user, and it overrides StandaloneBar's own logic (the implicit 300 px size) with explicit x/y/width/height; what's left forwards `barConfig`/`panel`/`screen` into a BarContainer filling it. The comments about "the bar editor's preview" (215, 515) describe a preview that is gone. Fix: put the `BarContainer` straight into BarPanel with the same x/y/width/height (`container: bar`), read the container's own `x`/`y` in `blurOrigin`, drop the preview clauses, and drop its `Extra:` line in `.claude/skills/review-system/systems.md`. This removes StandaloneBar.qml (27 lines).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the bar system

### BarContainer._withEntry rebuilds Utils.withEntry
- **Where:** `components/bar/BarContainer.qml:174` (`_withEntry`), `components/methods/Utils.qml:65` (`withEntry`)
- **What:** `_withEntry` copies the map and sets or deletes `owner` (177-182), which is `Utils.withEntry`; the same file already uses `Utils.withEntry` at line 341. Fix: `return Utils.deepEqual(map[owner] ?? null, value ?? null) ? null : Utils.withEntry(map, owner, value || undefined);`, 12 lines (172-183) down to 4.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### enrichBarConfig hands out two fields nothing reads and keeps three dead fallbacks
- **Where:** `config/BarsConfig.qml:106` (`enrichBarConfig`), `config/BarsConfig.qml:145`, `config/BarsConfig.qml:25`, `config/BarsConfig.qml:47`, `config/BarsConfig.qml:113`
- **What:** Nothing reads an enriched bar's `joinable` or `separatorGap` (every `.joinable` read is an end's or SurfaceContext's own edge; `separatorGap` is read only as `look.separatorGap`, line 118). The bar comes from `ConfigManager.live` with every default filled, so `barConfig.background ?? "solid"`, `barConfig.pillPadding ?? 0` and `barConfig.pillMerge ?? 0` never fall back (AGENTS.md: "readers use no `??` fallbacks"; check_structure only catches `_c.key ?? x`). Fix: delete lines 105-106 and 145 (3 lines) and the three `??` tails.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### A bar's reserve trim is worked out again by callers holding the enriched bar
- **Where:** `config/BarsConfig.qml:354` (`reservedZone`), `config/BarsConfig.qml:345` (`detachedPush`), `config/BarsConfig.qml:176` (`enrichBarConfig`)
- **What:** `enrichBarConfig` already sets `bar.trim = BarsConfig.reserveTrim(bar, gapsOut[edge] ?? 0)`. Every caller of `reservedZone` and `detachedPush` passes an enriched bar and its own edge's `gapsOut`, then gets the same number again from `reserveTrim`: `components/bar/BarPanel.qml:38`, `services/ui/ScreenEdgeManager.qml:91` (without `?? 0`, so the two sources can differ), `components/hosts/popout/EdgePlacement.qml:201`. Fix: read `barConfig.trim`; `reservedZone(barConfig)` loses its `gapsOut` parameter, and `detachedPush` becomes `gapsOut - barConfig.trim - connectorGap / 2`. Take it with [A corner piece's pull-out re-derives a bar's reserve and misses its clamp](#a-corner-pieces-pull-out-re-derives-a-bars-reserve-and-misses-its-clamp), whose fix calls `reservedZone`. (`cornerMargin`'s copy is the Major above.)
- **Size:** small
- **Found:** 2026-10-30, while reviewing the bar system

### Missing test rows for two helper decisions
- **Where:** `components/methods/BarEnds.qml:111` (`endOf`), `components/methods/BarLayout.qml:181` (`overflowHidden`)
- **What:** `tst_BarEnds` has no row for a solid bar meeting a solid bar: the `|| bar.solid` arm (a solid bar with the border off gets `_frame`, i.e. `bare`) is untested, and changing it to `_barStroke("solidBar", opts)` passes every row. `tst_BarLayout`'s two `lockCenter` rows never let the centre alone overflow, so line 181's `return [2]` is untested: returning `[0, 1]` would hide side widgets while the centre still doesn't fit. Fix: add those two rows.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the bar system

### An overlay misses a transparent bar's inner accent line
- **Where:** `components/hosts/overlay/ReservedAreaWindow.qml:46` (`_margin`)
- **What:** `_margin` returns `gapsOut` for every transparent bar. A transparent bar with `accentLine: inner` reserves its full extent instead (`BarsConfig.reserveTrim` is 0 for it), so the overlay sits `gapsOut` past that bar's inner edge rather than on it. The last line's `reserveTrim` call can then only return 0, since the transparent case already returned. Fix: `if (bar?.background === "transparent") return bar.trim;` and make the last line `return -Appearance.borderWidth;`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### WindowLookConfig rebuilds BarStyle.look
- **Where:** `config/WindowLookConfig.qml:31` (`_barLook`), `config/BarStyle.qml:15` (`look`)
- **What:** `BarsConfig.lookOf({})` returns what `BarStyle.look` holds: every `Bars.style` key with the shadow flattened. Every other user of the shared look reads `BarStyle.look` (RoundedBorders, SurfaceShadow, AttachedSurface, EdgePlacement). Fix: `readonly property var _barLook: BarStyle.look`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar system

### Media squeezed to its minimum in the fill style shows the meter, not its icon
- **Where:** `components/bar/widgets/Media/Media.qml:20` (`minimumSize`), `components/bar/widgets/base/IconTextWidget.qml:46` (`_leadRoom`), `components/bar/widgets/base/IconTextWidget.qml:54` (`_iconStart`)
- **What:** Media is elastic, with `minimumSize: root.iconLength + root.padding * 2`. Its header says it shrinks "down to just the icon when the bar is crowded", and a crowded section or a `layout.size` cap squeezes it to that minimum. Its schema offers `fill`. In that style the meter is a lead graphic *before* the icon (`ValueGraphic.afterIcon` is only ticker/stacked). `leadSlot` sits at x 0 with its full `leadLength` (`fontSize * 4`, 56 px at the defaults), and the icon is drawn at `_iconStart = _leadRoom`, past the room the minimum leaves. The widget clips to its box (BaseWidget `clip: true`), so a squeezed Media in fill style shows about 20 px of the progress meter and no icon. Ticker and stacked draw after the icon and are fine. Fix: count the lead in the minimum, `minimumSize: root.iconLength + (root.leadAfterIcon ? 0 : root.leadLength + root.spacing) + root.padding * 2` (or expose `_leadRoom` as `leadRoom`).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### The Workspaces widget's measured length glides when the active cell widens
- **Where:** `components/bar/widgets/Workspaces/WorkspaceCell.qml:151` (`Glide on width`), `components/bar/widgets/Workspaces/WorkspaceCellRow.qml:48` (`implicitWidth: cells.implicitWidth`)
- **What:** With `wideActive` (the default), each cell's `width`/`height` glides over animNormal. The row's implicit size is the `cells` Grid's, the sum of those drawn widths, and so is `BarWidgetHost.naturalSize`.
  - When a switch changes the total, the measured size moves on every frame of the glide. Each frame re-runs the bar layout and re-targets the host's own animFast glide.
  - The total changes when the new active workspace wasn't shown before (showEmpty off, and always on niri through `_hideEmpty`): its cell appears at 2× length while the old active one shrinks. It also changes when the active workspace leaves the row.
  - This breaks composition.md › Bar motion: "**Measured, never animated:** the layout is measured from the modules' implicit sizes. That covers `naturalSize`/`preferredSize`…".
  - `Glide on width|height` under `components/bar` is otherwise only on WidgetBackground and BarWidgetHost, both drawn sizes.

  PLAUSIBLE that it shows (a neighbour jittering or lagging over the glide): a TRACE of `naturalSize` while switching to a new niri workspace settles it. Fix: measure the row from its targets, `ids.length * cellLength + (wide active shown ? cellLength : 0) + (ids.length - 1) * spacing` across the main axis, and clip the row while a cell still glides.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### A custom clock format without spaces spills past a vertical bar
- **Where:** `components/bar/widgets/Time/Time.qml:108` (`_split`)
- **What:** On a vertical bar the clock is `widgetSize` wide, and a custom format is stacked one part per line, split only on whitespace and `:` (`text.split(/[\s:]+/)`). With `dateFormat: "yyyy-MM-dd"` (or `dd.MM.yyyy`, `HH.mm`) the whole value is one line ("2026-10-30" is about 70 px at font 14), centred in a ~26 px column. BarWidget doesn't clip, and the host clips only while resizing, so the text draws across the bar's edge onto the windows beside it. The file's header promises "On a vertical bar each is stacked into short lines". Fix: split on `/[\s:.\-\/,]+/`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### SystemStats' used memory clips on a vertical bar
- **Where:** `components/bar/widgets/SystemStats/SystemStats.qml:108` (`segmentData`, `mem`), `components/bar/widgets/base/IconTextWidget.qml:140` (`elide`)
- **What:** On a vertical bar each value is upright under its icon, at `textScale` 0.7 with `Text.ElideNone`, centred in the `widgetSize` column of a box that clips (BaseWidget `clip: true`). With `memoryFormat: used` the value is `toFixed(1) + "G"`, five characters from 10 GiB up ("15.6G"). That is about 5 × 0.6 em × 9.8 px ≈ 29.5 px in monospace, in a 26 px column, so both outer glyphs lose about 2 px; "125.3G" loses most of a glyph each side. Percent values ("100%", about 23.5 px) fit. PLAUSIBLE: a screenshot of a vertical bar with `memoryFormat: used` on a machine using 10 GiB or more settles it. Fix: whole GiB on a vertical bar (`toFixed(root.isVertical ? 0 : 1)`), or let an upright label shrink to fit (`fontSizeMode: Text.HorizontalFit` with a `minimumPixelSize`).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### The stacked style clips on a thin bar
- **Where:** `components/bar/widgets/base/ValueGraphic.qml:217` (value `font.pixelSize`), `components/bar/widgets/base/ValueGraphic.qml:229` (caption `font.pixelSize`)
- **What:** Stacked's two lines are `fontSize * 0.8` and `fontSize * 0.6`, sized from the font alone: about 1.17 × 1.4 × fontSize ≈ 23 px at font 14. They are centred in the widget's `widgetSize`, and the widget clips. At the default 26 px they fit. At `widgetSize` 20 with font 14, where a one-line label (about 16 px) still fits, about 1.5 px comes off the top of the value and the bottom of the caption. PLAUSIBLE: a screenshot of a stacked widget on a 20 px bar settles it. Fix: scale both lines by `Math.min(1, root.crossSize / (1.2 * 1.4 * root.fontSize))`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### BaseWidget's background box and panel-size defaults are dead
- **Where:** `components/bar/widgets/base/BaseWidget.qml:13` (`backgroundColor`), `components/bar/widgets/base/BaseWidget.qml:15` (`showBackground`), `components/bar/widgets/base/BaseWidget.qml:17` (`contentItem`), `components/bar/widgets/base/BaseWidget.qml:19` (`radius`), `components/bar/widgets/base/BaseWidget.qml:29` (the `Rectangle`), `components/bar/widgets/base/IconTextWidget.qml:22` (`spacing`), `components/bar/widgets/base/IconTextWidget.qml:25` (`fontSize`), `components/bar/widgets/base/ValueGraphic.qml:31` (`fontSize`), `docs/dev/core/shared-ui-pieces.md:103`
- **What:** Widgets don't draw their own backgrounds; WidgetGroup does (widget-style.md › Widget style). BaseWidget still has its own box, and it is never drawn. Its three instances all set `showBackground: false`: BarIconWidget:60, SystemStats:179 (`box`) and SystemStats:204 (the segments).
  - `backgroundColor` and `radius` feed only that Rectangle. The two `radius:` setters (BarIconWidget:43, SystemStats:178) therefore do nothing.
  - `contentItem` has no reader (its declaration is its only hit in `components/bar`).
  - Deletion pass: BaseWidget lines 13–15, 17, 19 and 29–35 (12 lines) plus the five setters, 17 lines in all.
  - shared-ui-pieces.md:103 still calls BaseWidget "the rounded box a bar widget sits in": it becomes "the sizing wrapper".

  The bases' remaining defaults are the panels' sizes, and every instance replaces them from `barConfig`:
  - BaseWidget: `padding: Widget.padding`, `crossSize: Widget.height`
  - IconTextWidget: `spacing: Widget.spacing * 1.5`, `fontSize: Appearance.fontSize`
  - ValueGraphic: `fontSize: Appearance.fontSize`

  These five are the only `Widget.*`/`Appearance.fontSize` reads under `components/bar/widgets`, and they read as though the bar's pieces size from the Interface section. Default them to 0.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### SystemStats works out ValueStyleWidget's style fallbacks again
- **Where:** `components/bar/widgets/SystemStats/SystemStats.qml:199` (segment `style`), `components/bar/widgets/SystemStats/SystemStats.qml:139` (`backgroundLevelColor`), `components/bar/widgets/SystemStats/SystemStats.qml:141` (`_textByState`), `components/bar/widgets/base/ValueStyleWidget.qml:34` (`style`)
- **What:** Two rules live in both `ValueStyleWidget.style` and SystemStats' per-segment `style`: "stacked on a vertical bar is a label" and "a sparkline with no history is a fill". `Qt.alpha(colors.icon, 0.35)` and `colorText && colors.fill.a < 1` are copied word for word too. A new style rule added to one copy will be missed in the other. Fix: put the fallbacks in one function on ValueGraphic (`resolvedStyle(style, vertical, hasHistory, ratio)`) and read it from both places, about 4 lines out of SystemStats. The pill colour can be a ValueGraphic constant.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### The workspace switchers find a workspace by id with hand-written loops
- **Where:** `components/bar/widgets/Workspaces/WorkspaceStrip.qml:74` (`wsById`), `components/bar/widgets/Workspaces/WorkspaceStrip.qml:83` (`hasWindows`), `components/bar/widgets/Workspaces/WorkspaceCellRow.qml:56` (`_occupied`)
- **What:** `WorkspaceStrip.wsById` and `hasWindows` (lines 74–85, 12 lines; `hasWindows` has one call, line 63), and `WorkspaceCellRow._occupied` (8 lines), each walk `CompositorManager.workspaces` with an index loop to find one id. WorkspaceGrid already does it in one line: `CompositorManager.workspaces.find(ws => ws.id === id) ?? null` (WorkspaceGrid.qml:61). Fix: `wsById` becomes that `find`, `hasWindows` is inlined at its call, and `_occupied` becomes `return (CompositorManager.workspaces.find(ws => ws.id === id)?.windowCount ?? 0) > 0;`. That is 20 lines down to about 6, with the same results.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the bar-widgets system

### Reopening the overlay while it closes leaves it open but hidden
- **Where:** `components/hosts/overlay/OverlayPanel.qml:44` (`open`), `components/hosts/overlay/OverlayPanel.qml:69` (`hideTimer`)
- **What:** `close()` sets `isOpen = false` and starts `hideTimer` (`Appearance.animSlow`, 300 ms at the default motion), which sets `visible = false` when it fires. `open()` sets `visible = true; isOpen = true` but never stops the timer. So toggling the overlay twice within the slide-out (a double tap of its keybind or of `axiom ipc overlay toggle`, or a `SurfaceGroup` sync from another monitor) leaves it open but hidden: `isOpen` is true while the window isn't visible. `OverlayPages.open` (bound to `visible`) unloads its pages, the backdrop stays dimmed (`shell/Overlay.qml` shows it on `panel.isOpen`) and its focus grab stays active. The next toggle closes the hidden overlay, so the user has to press twice to get it back. It has been this way since the restructure commit (`git log -S"hideTimer.start"`). Fix: `hideTimer.stop();` first thing in `open()`.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the overlay system

### A clean layout's problem blocks saving the others in the Layouts editor
- **Where:** `components/views/Layouts/Layouts.qml:78` (`canvas.canSave`), `components/views/Layouts/LayoutsPanel.qml:34` (`problems`)
- **What:** The canvas's Save is enabled only while none of the five drafts has `problems`, yet `onSave` saves only the dirty ones, and each `saveChanges()` already refuses its own problems. So a saved layout that `GridEditor.problemsFor` objects to, even one nobody touched, disables saving every page and menu. Example: a config imported or edited by hand whose lock screen layout lacks its required module ("the lock screen: needs its … module") while `Lockscreen.mode` isn't `quickshell`. The lock screen's row is then hidden (`OverlayManager.lockscreenEditable`), so it can't be fixed from the editor, and "Can't save yet" lists it under every edit. The same happens with a hidden login screen (`greeterEditable`) and with a saved overlay page whose modules overlap, a case `ModuleGrid._check` expects (it warns about them). The navigator's Save all (`EditsManager.saveAll`) already saves around it, so the two Save buttons disagree. Fix: gate `canSave`, and the problems listed, on the dirty drafts only: `drafts.every(d => !d.isDirty || d.problems.length === 0)`.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the overlay system

### The five layouts drafts are listed by hand in eight places
- **Where:** `components/views/Layouts/Layouts.qml:38` (`Component.onCompleted`), `components/views/Layouts/Layouts.qml:77` (`canvas.dirty`, `canvas.canSave`, `onSave`, `onReset`), `components/views/Layouts/LayoutsPanel.qml:34` (`problems`), `services/ui/EditsManager.qml:49` (the Layouts `dirty`), `services/ui/EditsManager.qml:172` (`saveAll`), `services/ui/EditsManager.qml:194` (`discardAll`)
- **What:** `OverlayManager`, `OverlayManager.menus`, `DesktopManager.editor`, `LockManager.editor` and `GreeterManager.editor` share one interface (`isDirty`, `problems`, `ensureLoaded`, `saveChanges`, `resetChanges`), but every caller spells all five out. Layouts.qml loads them (7 lines), reads dirty and canSave (2) and saves and resets them (19). LayoutsPanel concatenates their problems (1). EditsManager reads dirty (1), and saves (10) and discards (10) them. That makes 50 lines, and the orders already differ: EditsManager saves the menus before the pages, Layouts.qml after. A sixth draft would need all eight edits. Fix: `OverlayManager.drafts: [root, root.menus, DesktopManager.editor, LockManager.editor, GreeterManager.editor]`, with `layoutsDirty`, `layoutsProblems`, `loadLayouts()`, `saveLayouts()` and `resetLayouts()` over it (about 15 lines). Each place becomes one call (about 8 lines), about 27 lines fewer, and the Save gate above becomes one line.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the overlay system

### GridEditor's canAdd and canMove have no caller
- **Where:** `services/ui/GridEditor.qml:370` (`canAdd`), `services/ui/GridEditor.qml:375` (`canMove`)
- **What:** `grep -rnw 'canAdd\|canMove' --include=*.qml .` finds only their definitions, plus the Checks line in grid-canvas.md (`CompositorStatusCard`'s `canAdd` is its own property). The canvas and the drag layer use the plans (`hoverPlan.valid`) instead; only `canResize` has a caller (`EditorInspector.qml:195`). Fix: delete both (lines 369–378, 10 lines) and drop them from grid-canvas.md's "Checks" line.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the overlay system

### Small shrinks in the overlay
- **Where:** `config/OverlayConfig.qml:34` (`pinnedPages`), `config/OverlayConfig.qml:253` (`slotShape`), `components/hosts/overlay/OverlayPages.qml:52` (`pageCount`, `pages`, `_onPinned`), `components/views/Custom/Custom.qml:17` (`fineGrid`), `components/hosts/overlay/OverlayPageNavigator.qml:228` (the pill's `Behavior`s)
- **What:** Four things can go or shrink, about 15 lines in all:
  - `pinnedPages` is a list of one (Layouts). `OverlayPages` counts `pinnedPages.length` into `pageCount` and `pages`, but draws a single hard-wired `editorPage`, so a second entry would get a tab and an index with nothing behind them. A single `layoutsPage` object on OverlayConfig, with `_onPinned` a bool, says what the code does (about 4 lines fewer).
  - `OverlayConfig.slotShape` only forwards to `GridPlacement.slotShape`, and has one caller, `SlotContext.qml:28`. That caller can call `GridPlacement.slotShape` itself, importing `qs.components.methods` (3 lines fewer).
  - In `Custom.qml`, the fine grid sets `availableWidth` / `availableHeight` (lines 17–18). An `OverlayGrid` with a `fixedUnit` uses them only for `roomWidth`, which nothing reads on this grid (`ModuleGrid` reads `unit`, `gap` and `sizes`), so both lines can go.
  - The navigator pill's two `Behavior { NumberAnimation { duration: Appearance.animNormal; easing.type: Easing.OutCubic } }` (lines 228–239, 12 lines) are `Glide on x { duration: Appearance.animNormal }` and the same on `width` (6 lines): the shared piece, with `Appearance.easing` in place of a literal.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the overlay system

### fullMinWidth and fullMinHeight are compared with the slot's size, padding included
- **Where:** `components/content/base/SlotContext.qml:32` (`compact`), `components/content/base/Card.qml:38` (`growHeight`), `components/content/base/Panel.qml:48` (`growHeight`), `docs/dev/overlay/writing-modules.md:24`
- **What:** `compact` tests `(width > 0 && width < fullMinWidth) || (height > 0 && height < fullMinHeight)`, where `width`/`height` are the whole slot. Every module writes `fullMin*` as the px its content needs, with no padding: none of the 30 `fullMinHeight:` settings in `components/content` adds a pad, and Weather sets `fullMinHeight: Appearance.fontSize * 6`, the same figure as its `currentHeight`, which it compares with `innerHeight` everywhere else. So from `fullMin*` up to `fullMin* + 2 × pad` (36 px in a bordered card at the defaults) the full layout is laid into room up to 36 px short of what it asked for. Cases at font 14, normal density: Weather in a 4x1 strip 360×90 px has 54 px inside for a 72 px block, and `Card`'s clip cuts it where the compact figure would have fit. Stopwatch with the timer set at a 140 px slot has 104 px for 130 px (segment row 30, ring 56, buttons 36, spacing 8), so the ring overlaps the buttons. The strips of Calculator, ClipboardHistory, EmojiPicker, ScreenRecord, AudioMixer, Brightness and NowPlaying (`fullMinHeight` 3.5 × font = 49) have 13 px inside at 49 px for a 28–34 px row. NightLightControls and WorldClocks (2.4 × font) reach the border. `growHeight` grows a card to `fullMinHeight`, short by the same pad. Fix, in one place: in `SlotContext`, compare the room inside the full layout's padding, with `fullPad: OverlayConfig.cardPad(false, <the bare test pad uses>)` (the non-compact pad, so `compact` doesn't depend on itself): `(width > 0 && width - 2 * fullPad < fullMinWidth) || (height > 0 && height - 2 * fullPad < fullMinHeight)`. Add `2 * fullPad` in `growHeight`, and say in writing-modules.md that `fullMin*` are inner px. It is likely the cause of [High module padding clips edge menu modules](#high-module-padding-clips-edge-menu-modules) too (a higher padding shrinks the room inside while `compact` still sees the whole slot): fix them together.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### Eight modules' full layouts need more room than their fullMin sizes, even inside the padding
- **Where:** `components/content/Palette/Palette.qml:17` (`columns`), `components/content/Pomodoro/Pomodoro.qml:20` (`fullMinHeight`), `components/content/Focus/Focus.qml:30` (`fullMinHeight`), `components/content/Disks/Disks.qml:25` (`columns`), `components/content/Tailscale/Tailscale.qml:54` (`fullMinHeight`), `components/content/WifiNetworks/WifiNetworks.qml:75` (`fullMinHeight`), `components/content/Updates/Updates.qml:44` (`fullMinHeight`), `components/content/NowPlaying/NowPlaying.qml:32` (`short`, `mini`)
- **What:** Contract (writing-modules.md): a module sets `fullMinWidth` / `fullMinHeight`, "the px its full layout needs". These don't cover it even once the entry above is fixed. All figures are inner px at font 14, normal density.
  - **Palette** picks 2, 4 or 8 columns from width alone. `fullMinHeight` 12f (132 px inside today) covers only 8 columns. 4 columns need about 266 px and 2 about 502 px (16 chips of about 57 px each with one role line). The default `[8, 4]` on a card under about 300 px tall cuts the bottom rows. Fix: choose the columns from both axes, and set the minimum from the chip count.
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

### SystemGraphs has no px minimum, so its full panels are cut on strips and tall columns
- **Where:** `components/content/SystemGraphs/SystemGraphs.qml:105` (`columns`)
- **What:** SystemGraphs sets no `fullMinWidth`/`fullMinHeight` (`grep -c fullMin` = 0), so it is compact only at 2×2 grid units or less. A panel (a `StatFigure` of about 53 px + spacing + a `Sparkline` of at least `Appearance.fontSize`) needs about 69 px. Scenarios: one metric in a 3x1 strip at a 60 px unit has 24 px inside, and the panel is cut to the top of its value. All five metrics in a 2x6 column at a 60 px unit get rows of 50 px, so each sparkline sits over its label. `columns` picks by aspect ratio only, never by px. Fix: `fullMinHeight` about `Appearance.fontSize * 5` (one panel) and `fullMinWidth` about 6f, and skip a column count whose rows would be shorter than one panel.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### The Clock's date and label keep their room while the time shrinks to nothing
- **Where:** `components/content/Clock/Clock.qml:48` (`captionSize`), `components/content/Clock/Clock.qml:50` (`captionsHeight`), `components/content/Clock/Clock.qml:54` (`faceHeight`)
- **What:** The captions always take `captionCount * (captionSize * lineRatio + spacing)`, with `captionSize` at least `Appearance.fontSizeBy(-2)`. The face gets what's left (`faceHeight: Math.max(0, root.innerHeight - root.captionsHeight)`), and the digits are fitted to it. Clock has no `fullMin*` and no compact form. Example: the default stacked style with the date on, in a 4x1 strip at a 60 px unit, has 24 px inside. The date takes about 14 px, which leaves about 10 px for two lines of digits, so the time is about 3 px tall under a 10 px date. With a `label` as well, the face gets 0. The same happens on the lock screen and the greeter, which both host Clock. Fix: the time is the key figure, so count a caption only while the face keeps at least that caption's own height. Drop the label first, then the date.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### The Cheatsheet's keyboard view is cut off below about 530 px, with no scroll and no small layout
- **Where:** `components/content/Cheatsheet/Cheatsheet.qml:46` (`fullMinHeight`), `components/content/Cheatsheet/Cheatsheet.qml:36` (`strip`), `components/content/parts/KeyboardMap.qml`, `components/content/parts/KeyboardReference.qml:75` (the legend `Row`)
- **What:** With `view: "keyboard"`, the module shows only `KeyboardReference`. Its height is fixed and it sits in no `Flickable`: 8 rows of `Math.round(Widget.height * 1.9)` = 57 px keys (6 `KeyMap.rows` plus the 20 `KeyMap.extras`), the gaps and the legend come to about 493 px inside, a card about 529 px tall. `fullMinHeight` is `Appearance.fontSize * 3` (42 px), the list view's figure, used for both views, and `strip` excludes the keyboard. So any card from 42 to about 529 px tall loses the legend, then the extra keys, then the lower rows, with no way to scroll to them. That includes the schema's `defaultSize: [8, 6]` at any unit under about 88 px. Across, at `fullMinWidth` (inner 160 px) a key unit is 8 px. Below about 24 px a unit, a key's corner name (never elided) spills into its neighbour. The legend is a non-wrapping `Row` of about 340 px. Fix: give the keyboard view its own minimums (about 28f × 38f), so a smaller slot shows the count figure, or a short key form, or put it in the list view's `Flickable`. Make the legend a `Flow`.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### A DeviceList squeezed to nothing wants no growth
- **Where:** `components/content/parts/DeviceList.qml:29` (`overflow`)
- **What:** `overflow: scroll.height <= 0 ? 0 : …` returns 0 whenever the list has no height. So `wantedHeight` is the card's own height, and `growHeight` doesn't grow it. A list gets 0 px exactly when the controls above it take the whole card (Tailscale's 4×2 card and WifiNetworks with VPNs, in the entry above). So a WifiNetworks, Tailscale, BluetoothDevices or VpnConnections card with `properties.grow` stays at a size that shows no rows, which is the one case growing is for. Notifications handles the unmeasured case the other way (`components/content/Notifications/Notifications.qml:64`: `scroll.height > 0 ? … : 1`). Fix: `root.on ? list.implicitHeight - Math.max(0, scroll.height) : -Math.max(0, scroll.height)`.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### Parts shown in one mode are built hidden in every mode, in ten modules and parts
- **Where:** `components/content/Network/Network.qml:84` (strip `Graphs`), `components/content/AudioMixer/AudioMixer.qml:170` (tabs and list), `components/content/Calculator/Calculator.qml:472` (`Keypad`), `components/content/WorldClocks/WorldClocks.qml:178`, `components/content/parts/CountdownTimer.qml:50` (`TimeRing`), `components/content/Stopwatch/Stopwatch.qml:78` (`CountdownTimer`), `components/content/parts/TodoList.qml:120` (rename field), `components/content/ClockCalendar/ClockCalendar.qml:149` (`InlineAgenda`), `components/content/Agenda/Agenda.qml:156` (`EventEditor`), `components/content/parts/calendar/DayPane.qml:69` (`EventEditor`)
- **What:** components/content/AGENTS.md: "a part shown in one mode only is a Loader gated on it, not `visible: false`", and "a row's expansion is built only while expanded". These parts are gated by `visible` only:
  - Network builds both its strip (lines 84–122) and its full column (124–191), each with two Sparklines, in every card.
  - AudioMixer builds its tabs and list (170–308, one `AudioRow` per playing app) in every slider-only card, and its card header in every popout.
  - Calculator builds its 20–24 key `Keypad` with `showKeypad` off and in every strip.
  - WorldClocks builds both a tile and a row layout for each clock (lines 178 and 225).
  - CountdownTimer builds its ring and buttons while idle, and its duration field and presets while set.
  - Stopwatch builds the whole `CountdownTimer` in stopwatch mode, and its time, buttons and laps in timer mode (in the Stopwatch popout too).
  - TodoList gives every item its own rename `StyledTextEntry`, though at most one row renames at a time.
  - ClockCalendar builds two `InlineAgenda`s, of which at most one shows, and a `DayPane` (a third agenda and the 360-line `EventEditor`). Where `showEvents` is false (always on the greeter, on the lock screen unless `Calendar.showOnLockscreen`), none of them can ever show, yet every lock and greeter surface builds them.
  - Agenda and DayPane each build an `EventEditor` that shows only after a click.

  This is the same rule as the NowPlaying entry, in other files. It is separate from "Compact cards still build their full layout": these parts are built at full size too. Fix: Loaders gated on each mode (`root.strip`, `!root.sliderOnly`, `showKeypad`, `tiles`, `idle`, `timerMode`, the row being renamed, `inlineAgenda && sideBySide`, `showEvents`, editing), with the Layout attached properties moved onto the Loaders. Done module by module, since ids read from the root need the loader's `item`.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### Card and Panel each spell out the grow and expand members
- **Where:** `components/content/base/Card.qml:28` (`wantedHeight`, `growHeight`), `components/content/base/Panel.qml:38` (`wantedHeight`, `growHeight`)
- **What:** Both roots declare `wantedHeight` and the same `growHeight` formula, each with its comment (11 lines each, word for word), beside an otherwise shared `SlotContext`, which already has every value `growHeight` reads (`width`, `fullMinWidth`, `fullMinHeight`). Fix: move `wantedHeight` and `growHeight` into `SlotContext`, bind `wantedHeight` in each root's `SlotContext {}` and alias `growHeight`. That is about 7 lines fewer, with one formula to change, which the padding entry above also touches. `canExpand`/`expand` stay, since their default `from ?? root` needs the root.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### Tailscale's PeerRow redraws DeviceRow without its buttons
- **Where:** `components/content/Tailscale/Tailscale.qml:103` (`PeerRow`), `components/content/parts/DeviceRow.qml`
- **What:** PeerRow (lines 103–167, 65 lines) is DeviceRow's row drawn again: the same `Rectangle` with `Widget.radius`, the hover colour with `ColorGlide`, the `RowLayout` margins, a `StyledIcon` at `Appearance.fontSize * 1.4` coloured by state, and a name (`fontSizeBy(-1)`) over a status (`fontSizeBy(-3)`), both elided. The only differences are that it has no connect or forget buttons, and that it shows "Copied" for 2 s. Fix: give DeviceRow `property bool connectable: true` to gate its connect button, and write PeerRow as a DeviceRow with `connectable: false` and its copy handler and timer. That is about 20 lines, so 45 fewer.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### WifiNetworks' WPA password form repeats WifiJoinForm's
- **Where:** `components/content/WifiNetworks/WifiNetworks.qml:179` (`pskForm`), `components/content/parts/WifiJoinForm.qml`
- **What:** For `row.kind === "psk"`, the row loads `pskForm` (lines 179–209, 31 lines): a password field (echo Password, Enter submits, Escape calls `NetworkingManager.cancelPassword()`, focused on load) and a connect button enabled while the field isn't empty. `WifiJoinForm { security: "psk" }` draws the same: only its password row and connect button, focused first, and complete when the password isn't empty. The only difference is where the password goes, Quickshell's `connectWithPsk` rather than `join`. Fix: drop `pskForm` and the `sourceComponent` switch, and make the join form's `onSubmitted` choose `NetworkingManager.connectWithPsk(row.network, fields.password)` for psk rows. That is 32 lines fewer. Check that WifiJoinForm's Escape also reaches `cancelPassword`.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### Three row options nothing sets
- **Where:** `components/content/parts/DeviceRow.qml:32` (`disconnectTip`), `components/content/parts/ItemRow.qml:23` (`titleFamily`), `components/content/parts/TodoList.qml:20` (`showFocus`)
- **What:** `grep -rnw` over qml, yaml, json and py finds each name twice: its declaration and its one read. No DeviceRow user sets `disconnectTip` (BluetoothDevices sets only `connectTip`). No ItemRow user sets `titleFamily`, which defaults to `Appearance.fontFamily`, StyledText's own. No TodoList user (Todo, Focus) sets `showFocus`, so it is always true despite its comment "off where no timer is near". Fix: inline `I18n.tr("Disconnect")`, drop the `titleFamily` binding, and drop `showFocus` and its test (about 4 lines).
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### Login and Password each carry the same required-field report
- **Where:** `components/content/Login/Login.qml:43` (`_report`), `components/content/Password/Password.qml:41` (`_report`)
- **What:** Both modules hold the same 12 lines: `_reportedKey`, a `_report()` that unreports the old key and reports the new one through `SurfaceManager.reportRequiredField`, and `Component.onCompleted`, `onHostChanged` and `Component.onDestruction`. They differ only in the host test (`onGreeter` / `onLockscreen`). Fix: one small QtObject part in `content/parts/` holding the 12 lines, given the host and whether it applies. Each module keeps 1–3 lines, so about 20 lines fewer.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### Three keycap parts draw the same cap, and KeyCap's icon slot has no user
- **Where:** `components/content/parts/KeyCap.qml:12` (`icon`), `components/content/parts/KeyCluster.qml`, `components/content/parts/KeybindRow.qml:109`, `components/content/parts/ModifierCap.qml`
- **What:** KeyCap, KeyCluster and ModifierCap repeat the same `Rectangle` shell: the height `Math.round(Widget.height * (compact ? 0.62 : 0.75))`, the width, radius and colour, and the text size. KeyCluster is a KeyCap whose text is its keys with a gap between them, and KeybindRow builds both a KeyCap and a KeyCluster for every alternative and hides one (lines 109–121). No `KeyCap {` user sets `icon`. Fix: delete KeyCluster.qml (35 lines), and replace KeybindRow's pair (13 lines) with one `KeyCap { text: alternative.modelData.join(" ") }` (about 5): about 43 lines fewer, and one cap built per alternative. Delete `icon` and its `StyledIcon` (7 lines) unless ModifierCap folds into KeyCap too, which needs SUPER ordered first; check `KeybindManager`'s modifier order before doing that. About 50 lines in all.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the modules system

### WeatherForecast repeats the Weather card's current conditions
- **Where:** `components/content/WeatherForecast/WeatherForecast.qml:23`, `components/content/Weather/Weather.qml:70` (`Current`)
- **What:** The popout's place name, condition icon, temperature, condition and details (lines 23–57, 35 lines) are the card's `Current` component drawn again with its own sizes. `Current`'s own comment says "as in the bar's forecast popout". A change to how the current weather reads (units, details) has to be made twice. Fix: move `Current` into a part in `content/parts/` and use it in both, so the popout is about 30 lines shorter. Or make the Weather card a Panel that is also the popout (content-roots.md's one-file shape) and drop WeatherForecast (96 lines).
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### Any custom widget reaches the lock screen past its Offer switch
- **Where:** `components/content/CustomWidget/CustomWidget.qml:23` (`widgetId`), `config/OverlayConfig.qml:108` (`customModuleTypes`), `services/ui/SettingsManager.qml:370` (the `customWidgets` options), `components/views/Layouts/EditorInspector.qml:244`
- **What:** `module.lockscreen` ("Offer on the lock screen": "what it prints shows to anyone at the screen: offer only what's fine to show") is checked only by the lock screen's library (`OverlayConfig.customModuleTypes` drops the `lockscreen` host when it's off). A placed module draws whatever its `properties.definition` names: (1) turning the switch off after placing one leaves it on the lock screen, its script running; (2) the lock screen's inspector shows the module's settings form (`EditorInspector.qml:244`), whose definition picker lists every definition (`x-options: customWidgets` → `CustomWidgetsConfig.items.map(item => item.id)`), so any definition can be switched in. Nothing in `CustomWidget.qml` reads `module.lockscreen` (grep: only `actionsEnabled` checks `host.kind`). Fix: on the lock screen, a definition without `module.lockscreen` is treated as none: `widgetId` empty when `root.host?.kind === "lockscreen" && !CustomWidgetsConfig.definition(id)?.module.lockscreen` (so nothing is acquired), with its EmptyState saying it isn't offered there.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A custom widget's module past 8 grid units can't be saved
- **Where:** `services/apps/CustomWidgetsEditor.qml:209` (`_fitSize`), `config/schema/definitions/custom/CustomWidget.yaml:89` (`module.size` items, `maximum: 8`), `config/schema/definitions/kinds/CustomElementBase.yaml:44` (`place.w`, `maximum: 64`)
- **What:** The element canvas is unbounded (`GridEditor` with no `area`), an element's place may be 64 sub-cells (16 units) wide or tall and `x`/`y` have no maximum, and every edit sets `module.size` to the elements' bounds rounded up (`CustomWidgetData.pageSize`). Resizing or dragging an element past the 32nd sub-cell (two cards) makes `module.size` 9 or more; the preview draws it, but Save sends a config the daemon's `Pipeline.Check` refuses (`module.size.0: value 9 is greater than maximum 8`): `ConfigManager.commit` logs `axiom refused the config` and the draft turns dirty again, with no word on the page about why. Fix: make the limits agree: `module.size`'s `maximum` 16 (the place's 64 sub-cells), or bound the canvas (`GridEditor.area` of 32 × 32 sub-cells, a module's largest).
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A custom widget's Tooltip switch does nothing
- **Where:** `config/schema/definitions/custom/CustomWidget.yaml:66` (`tooltip`), `components/views/CustomWidgets/BarTab.qml:95`, `components/methods/CustomWidgetData.qml:472` (`fromWaybar`)
- **What:** The Bar tab offers a Tooltip switch (default on) and Waybar's `"tooltip": false` imports into it, but nothing reads a definition's `tooltip` (repo-wide grep: the schema, BarTab's `order` and `fromWaybar` only). The bar widget shows no tooltip at all (no bar widget base has one: hovering opens the module popout), while the plan says every bar style shows `tooltip` (`docs/dev/plans/custom-json-widgets.md`, Bar styles). The output's `tooltip` field reaches only the Text block element. Fix: either draw it (a `StyledToolTip` of `fields.tooltip` on the bar widget while its popout doesn't open, gated on the switch) or delete the switch: the schema line, BarTab's `"tooltip"` and `fromWaybar`'s two lines (3 lines; the key prunes on load). Open question for the maintainer: should a custom widget on the bar show the script's tooltip on hover when its popout is off, as Waybar does, or is the popout the only hover?
- **Size:** small
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A stale exec-if check can block a widget after its exec-if changed
- **Where:** `services/apps/CustomWidgetsManager.qml:163` (`_checkIf`)
- **What:** The check's callback only asks whether the id is still watched (`if (!(id in root._watching))`), not whether its `execIf` is still the one checked. Editing Run only if on the page re-checks on every keystroke (`_wanted` changes, `_sync` calls `_checkIf`), and clearing it watches at once (`_watch`). A check that ends after a newer one, e.g. typing `ping -c1 -W1 myhost` (the partial `ping -c1 -W1 myh` waits its second to fail while the full one answers in milliseconds), sets `_blocked`, releases the watch the newer check started and shows `"ping -c1 -W1 myh" failed` until the next refresh. PLAUSIBLE: the order the checks end in; a slow failing prefix settles it. Fix: `if (root._watching[id]?.execIf !== def.execIf) return;` in place of the `in` check (`_watching` holds each id's `execIf`).
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A command naming a program shows the program as its script
- **Where:** `components/views/CustomWidgets/DefinitionsPanel.qml:26` (`scriptText`), `services/apps/CustomWidgetsEditor.qml:184` (`scriptPath`)
- **What:** `scriptPath` is the command's first word whenever it starts with `/` or `~/`, so a command like `/usr/bin/sensors -j` or `/opt/cuda/bin/nvidia-smi …` names a binary: `FileManager.read` (a blocking FileView, on the UI thread, of the whole file) reads the ELF into a string, The script group shows its first 40 "lines" of binary as the script, and `signalsWaybar` regex-scans it. A large binary stalls the page while it reads. Fix: show only a script, text starting with `#!` (`scriptText.startsWith("#!")` for `scriptHead` and `signalsWaybar`); reading only the head needs a size cap `FileManager.read` doesn't have.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### CustomElement's six Binding blocks are Qt.binding in its setSource
- **Where:** `components/content/parts/custom/CustomElement.qml:33` (the `Binding` blocks), `components/content/parts/custom/CustomElement.qml:21` (`_load`)
- **What:** `_load` hands the element its six properties as plain values, then six `Binding { when: root.item !== null … }` blocks (lines 33-68, 36 lines) keep them current. Passing each as `Qt.binding(() => root.element)` (and so on) in `setSource`'s properties, as `BarTab`'s `BarPreview` loads the bar widget, keeps them bound from creation, across a kind change (each `_load` binds the new item) and drops the 36 lines. Fix: wrap the six values in `Qt.binding`, delete the Binding blocks; the file goes from 69 to 33 lines.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### A custom layout without elements rebuilds its default elements every sample
- **Where:** `components/content/parts/custom/CustomLayout.qml:24` (`elements`)
- **What:** For a definition with no elements, `elements` reads `root.fields?.ratio`, so every push (4 a second for a stream, per surface showing it, plus the Module tab's five previews) runs `CustomWidgetsConfig.defaultElements` (two `ConfigManager.withDefaults` schema walks) and hands every element a new `element` object, re-evaluating its `place`, `bind`, `options` and `rect`. Only whether there is a value matters. Fix: `readonly property bool _hasValue: (root.fields?.ratio ?? -1) >= 0` read by `elements` (a bool that doesn't change doesn't notify), keeping the Icon/Ring switch.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

### An integrated menu's zone stays behind when it changes edge or screen
- **Where:** `components/surfaces/edgemenu/IntegratedEdgeMenu.qml:93` (`onReservedChanged`), `components/surfaces/edgemenu/IntegratedEdgeMenu.qml:88` (`Component.onDestruction`), `services/ui/ScreenEdgeManager.qml:155` (`setZone`)
- **What:** The menu reports its zone with `ScreenEdgeManager.setZone(root.screen?.name ?? "", root._edgeName, root.reserved)` only when `reserved` changes, and clears it on destruction under the screen and edge it has then. `EdgeMenu` keeps the host across edits (keyed by id, loaded by mode), so changing an open menu's edge or monitor in the layouts editor (open while previewing, or pinned) moves `_edgeName` or `screen` without clearing the old key: `zones["DP-1:top"]` keeps the old depth until qs restarts. Everything reading `zoneOn`/`reservedWithMenusOn` for that edge (floating menus, edge popouts, `BarPopouts.borderInset`, the hover strips' `edgeInset`) then sits past a strip that isn't there. Zones are also keyed per screen and edge only, so two integrated menus open on one edge overwrite each other's, and closing one zeroes the other's. DockWindow already solves both (`_zoneSet`, the key set last, and `DockManager.setZone`'s per-dock key). Fix: as DockWindow, remember the key last set and clear it when the key changes or on destruction, and key the zone by menu id too, summed per edge.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

### An integrated top or bottom menu's zone follows its growing modules
- **Where:** `components/surfaces/edgemenu/IntegratedEdgeMenu.qml:49` (`depth`), `components/surfaces/edgemenu/IntegratedEdgeMenu.qml:135` (`exclusiveZone`), `components/surfaces/edgemenu/EdgeMenuBody.qml` (`maxGrownHeight`)
- **What:** hosts.md says of an integrated menu: "The zone is set once while it's open (windows retile in one step)". But `depth` is `Math.ceil(root.bodyDepth + root.pad * 2 + root.innerStroke)`, with `bodyDepth` the body's live `implicitHeight` on a top or bottom edge: `ModuleGrid.sizes.height`, from the grown places (`ModuleGrid.places`). `exclusiveZone` and the window's `implicitHeight` follow it. So a top menu holding a module with `grow` (Notifications, AudioMixer, WifiNetworks, …: nine modules have it) changes its exclusive zone each time that module grows or shrinks, e.g. when a notification arrives: the windows retile again, and the shown layer window grows (the squeezed flash growing popout windows show). FloatingEdgeMenu avoids this by reserving the most up front (`maxContentDepth: root._body.maxGrownHeight`). Fix: reserve `maxGrownHeight` on a top or bottom integrated menu, so the zone is set once. Question for the maintainer: is a strip that keeps room for its modules' growth right, or should the zone follow the modules (then hosts.md changes, and the window still mustn't grow while shown)?
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

### A whole-edge menu's hover strip covers only its modules' length while closed
- **Where:** `components/surfaces/edgemenu/EdgeMenuSync.qml:45` (`triggerLength`), `components/surfaces/edgemenu/FloatingEdgeMenu.qml:105`, `components/surfaces/edgemenu/IntegratedEdgeMenu.qml:108`, `config/EdgeMenusConfig.qml:114` (`lengthOf`)
- **What:** With `trigger.length` 0 (the default) the strip is "the menu's length" (overview.md). `triggerLength(body, …)` takes the body's length while it's loaded, else `EdgeMenusConfig.lengthOf`: the modules' natural grid plus `paddingOf` twice. Both hosts load the body only while open (EdgePopout's loader is `active: root.occupied || root.keepLoaded`, IntegratedEdgeMenu's `active: root.occupied`). So a `length: "edge"` menu with `open.onHover`, closed, opens only from a strip as long as its unstretched modules, centred on the edge (`triggerCentre`/`centre` are the edge's middle); open, the strip spans the edge. Hovering near either end of the edge, where the menu draws, does nothing. For every menu the closed strip is also shorter than the open one: `lengthOf` leaves out the box's border (floating: `contentPadding` is `borderWidth + padding`) and an integrated menu's frame (`pad`). Fix: work the strip out from config alone, open or closed, with the host's own padding: `menu.trigger.length > 0 ? menu.trigger.length : menu.length === "edge" ? <the host's room along the edge> : gridLengthOf(menu, …) + pad * 2`, dropping the `body` argument; `lengthOf` (EdgeMenusConfig.qml:110–116, 7 lines) then has no caller once the editor's fit check uses the placement ([its entry](#the-layouts-editor-says-a-menu-fits-its-edge-when-it-scrolls)).
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

### The layouts editor says a menu fits its edge when it scrolls
- **Where:** `components/views/Layouts/MenuTarget.qml:22` (`tooLong`), `components/views/Layouts/MenuTarget.qml:18` (`length`)
- **What:** `tooLong` is `root.length > root.edgeLength`: `lengthOf` (the grid plus `paddingOf` twice) against the screen's whole edge. On screen the menu's room is the edge less what the perpendicular edges reserve and the box's insets (`frame.startPad`/`endPad`), and `GridPlacement.menuCell` decides it doesn't fit (`cell` null: it starts at `startPad` and scrolls). Scenario: a right-edge menu on a 1080 px screen with a 40 px top bar, its grid 1000 px and padding 8: the editor says "1016 px along its edge" with no warning, the nudge arrows vanish (`onLattice` false) with no reason given, and on screen it scrolls. AGENTS.md: "A methods helper's decision … is read from its output, never re-derived in a host". Fix: `tooLong: root.menu?.length !== "edge" && root.place !== null && root.place.cell === null`, and the px text from `root.place.length` (the grid along the edge, as `menuPlacement` returns it), dropping `length`.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

### Previewing a submenu menu doesn't open it once a module above its row has grown
- **Where:** `components/content/Submenu/Submenu.qml:35` (`_firstOpener`)
- **What:** "Show on screen" on a submenu menu holds the parent open, and the parent's first Submenu row opening it opens it (`previewed` needs `_firstOpener`). `_firstOpener` finds that row by comparing the config's `place.x`/`place.y` with `root.slotRect[0]`/`[1]`, but `slotRect` is `GridPlacement.rectOf(slot.place)` from `ModuleGrid.places`, the grown places: a growing module above the row in its columns (Notifications with a notification, say) pushes it down (`GridPlacement.grown`), the coordinates differ, no row is the first opener, and the submenu never opens while the editor says it's shown. Fix: match the row by something growth doesn't move: hand modules their config place beside `slotRect` (OverlaySlot) and compare that, or compare the row's `properties` with the first opener's (two identical rows open the same menu alike).
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

### IntegratedEdgeMenu's empty engage exists only for EdgeMenuSync's call
- **Where:** `components/surfaces/edgemenu/EdgeMenuSync.qml:64` (`_edgeHost`, `_engage`), `components/surfaces/edgemenu/IntegratedEdgeMenu.qml:70` (`engage`)
- **What:** EdgeMenuSync connects `EdgeMenuManager.engageRequested` for both hosts and calls `engage()` through a `var` (`_edgeHost`, since PopoutWrapperBase has no `engage`), so IntegratedEdgeMenu defines an empty `engage()` ("it holds no popout claim, so there's no rank to raise"). Only the floating host has anything to do. Fix: move the `Connections` into FloatingEdgeMenu (`if (id === root.menuId) root.engage()`), deleting EdgeMenuSync.qml:64–74 (11 lines) and IntegratedEdgeMenu.qml:70–73 (4 lines), about 6 added.
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the edge-menus system

### MenuSubmenu repeats EdgeMenuBody's module grid
- **Where:** `components/content/Submenu/MenuSubmenu.qml:24` (`_modulesKey`, `host`, `overlayGrid`), `components/surfaces/edgemenu/EdgeMenuBody.qml:25` (`_modulesKey`)
- **What:** MenuSubmenu copies EdgeMenuBody's parts one for one: the `_modulesKey` re-parse ("as EdgeMenuBody", lines 24–27), the `host` map (29–34, adding `submenu`), the `OverlayGrid` at `cardUnitOf`/`gapOf` (36–40, on the parent's screen) and the clipped Flickable around a `ModuleGrid` at the menu's `zoomOf` (54–71): 33 lines that must change together (a fix to how a menu's modules are keyed, zoomed or hosted lands twice). Fix: EdgeMenuBody takes a `screen` (for `cardUnitOf`) and `submenu` (no pin, no Escape, no stretch, `host.submenu`), and MenuSubmenu becomes an `EdgeMenuBody` (`vertical: true`, `maxLength` from `root.wrapper?.maxContentHeight`) plus its empty text: 33 lines out, about 12 in.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system
