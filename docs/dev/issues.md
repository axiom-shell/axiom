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
- **What:** A module's children go into `Card.full` / `Panel.column` (a default property alias), which is only hidden while `compactContent` shows, so a compact card builds its whole layout as well as its figure. On the Tiny page (34 modules in quarter-card slots) this is most of what's left of its build: WifiNetworks about 65 ms, each ClockCalendar about 45 ms (`Built overlay module <Type> in X ms` with `--debug`). It also slows the bar popouts using those panels. A fix is an optional `fullContent: Component` on both roots, loaded only while not compact, then moving the heavy modules to it one by one (their ids are referenced from the module root, so each needs its own pass): see [streamed-building](core/streamed-building.md).
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
- **What:** The wallpaper window keeps two screen-size decodes (the previous one past its crossfade, `cache: false`), about 20 MB each at 3440×1440; the desktop's `ScreenLayoutView` decodes it a third time (`cache: false`) and keeps screen-size frost captures. NowPlaying decodes album art with no `sourceSize`, twice (once under a blur layer).
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
- **What:** Nothing keeps a bar popout's content within the screen: content taller than the room past the bar (the Calendar popout with its event editor open on a short screen, 1080 px or less with a top bar) draws its box past the screen's far side, and what's there is cut off. `popoutRoom` measures the room left, and only `StyledComboEntry`'s inline list keeps to it. A general guard would hand the content a most height (as `SubPopout.maxContentHeight` does for submenus) for it to scroll within.
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

### The community setups' check doesn't take monitor places yet
- **Where:** `services/core/SavedConfigsManager.qml` (`exportConfig`'s `places`), `components/views/Settings/CommunitySetupsCard.qml` (Export and submit), `backend/internal/share/share.go` (`Pick`'s `monitors`)
- **What:** An export names each per-monitor part's monitor (`x-monitorRef`: a bar's, dock's, OSD's, edge menu's, strip's, a monitor's own desktop) by its place (`#2`, `@primary`, `*`), so a multi-monitor setup lands on the importer's monitors. Those fields are `machine` scope, and the community-setups repo's CI admits only `look` keys (a walk mirroring `share.Pick`), so it would refuse such a file: Export and submit leaves the places out (`exportConfig(false, false, false)`), and a shared setup's second-monitor bar still lands on the importer's bar by position. Its CI needs to admit an `x-monitorRef` field holding a place, and then the card can export with them.
- **Size:** small
- **Found:** 2026-10-20, while aligning the schema's scopes

### Saving a profile that names a new monitor can move other monitors' blocks
- **Where:** `components/methods/WorkspaceGeometry.qml` (`blockBases`), `services/compositor/CompositorManager.qml` (`_bases`, `_remapWorkspaces`)
- **What:** Blocks are numbered over the monitors the saved profiles name, sorted by output identity, so saving a profile that names a monitor no profile named before puts it among them: every monitor sorting after it gets a new base, its workspaces sit outside its block, and in the `perMonitor` and `grid` layouts its list and steps miss them (the scrolling layout lists them as borrowed, which compaction leaves) until `axiom ipc workspaces reconcile`. The same happens once on updating to row 13 where the profiles name a monitor that isn't connected. Nothing remaps when `_bases` changes; a remap from the old block order to the new one would (`remapWorkspaces` takes each monitor's `block`, one per layout today). Rare: a per-monitor layout, a newly saved monitor, and its identity sorting before a connected one.
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
- **Where:** `backend/internal/compositor/manager/manager.go` (`New`), `backend/internal/compositor/manager/outputs.go` (`OutputsFromEnv`, `Outputs.Read`), `backend/internal/daemon/compositorsocket.go` (`greeterHandlers`), `components/methods/CompositorKind.qml`
- **What:** The shell picks its compositor with `CompositorKind`: with more than one of `HYPRLAND_INSTANCE_SIGNATURE` / `SWAYSOCK` / `NIRI_SOCKET` set (one left in the systemd user environment by an earlier session), the one whose process still runs wins. The daemon doesn't: `manager.New` takes the first set in a fixed order (Hyprland, niri, sway; the shell's is Hyprland, sway, niri) and `Outputs.Read`/`Apply` switch on the same order, with no process check. Under niri with a stale `HYPRLAND_INSTANCE_SIGNATURE` (or under sway with a stale `NIRI_SOCKET`) the manager is Hyprland's: `live()` needs the shell's facts to name its kind, so the layer is never applied (no binds, look or input in any mode), the status card stays on Checking, monitor profiles and `outputs.apply` go to a dead socket, and idle's `ScreenPower` fails. Fix: one Go `Detect(getenv)` (CompositorKind's rule, `/proc/<pid>/comm`) used by all three; then the daemon can start qs with only the running compositor's variable set, and `CompositorKind.qml` (68 lines), `tests/tst_CompositorKind.qml` (73) and `CompositorManager._running` go.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the compositor system

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
- **Where:** `services/compositor/SwayManager.qml` (`withCursorPos`, `warpCursorToLayer`, `withLayerRects`), `services/compositor/NiriManager.qml` (`withCursorPos`, `warpCursorToLayer`, `withLayerRects`), `services/compositor/CompositorManager.qml` (`withLayerRects`), `docs/dev/compositor/contract.md`
- **What:** Deletion pass. `CompositorManager.withCursorPos` and `warpCursorToLayer` call the backend only with `supports.cursorPos` / `cursorWarp`, which only Hyprland sets, so sway's and niri's `withCursorPos` (calls back null) and empty `warpCursorToLayer` are never reached. `withLayerRects` is called ungated, but both only call back null, which the facade's no-backend branch already does. About 22 lines over the two backends. Fix: delete the four gated stubs; make `withLayerRects` optional in the facade (`root.backend?.withLayerRects ? … : callback(null)`) and delete its two stubs; mark the three optional in contract.md › Session and input and the compositor-backend recipe.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### Small shrinks in the compositor layer
- **Where:** `services/compositor/CompositorManager.qml` (`stepWorkspace`), `services/compositor/CompositorConfigManager.qml` (`copyIncludeLines`, `copyAutostartLines`), `config/WindowLookConfig.qml` (`shadowSoft`), `components/views/Settings/CompositorStatusCard.qml`
- **What:** Deletion pass, about 12 lines. `stepWorkspace` re-derives `WorkspacesConfig.columns` and `rows` (`grid ? columns : size`, `grid ? rows : 1` equal them in every layout: `columns` is `count` and `rows` 1 outside the grid), a re-derivation of a reader's decision. `copyIncludeLines` / `copyAutostartLines` each wrap one `ClipboardManager.copyText` for one caller (the status card, which can call it itself). `WindowLookConfig.shadowSoft` is `_shadowMatched` under a second name, read once by `CompositorConfigManager._look`. Fix: use the readers' `columns`/`rows`; have the card call `ClipboardManager.copyText(CompositorConfigManager.includeLines)` and drop the wrappers; send `_shadowMatched` as a public `shadowMatched` (or keep one name).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the compositor system

### A trial monitor Apply that turns a monitor off drops its Keep/Revert
- **Where:** `services/compositor/MonitorManager.qml` (`onOutputsHotplugged`, `apply`, `revert`), `services/compositor/HyprlandManager.qml` (`_announce`)
- **What:** `apply()` evaluates the trial rules and sets `pending`; the hotplug handler (MonitorManager.qml:451-456) ends any pending trial (`pending = false; _countdown.stop()`), assuming the hotplug means the daemon already switched profiles. A trial whose rules disable or mirror a monitor makes Hyprland remove that output (`monitorremoved` → `outputsHotplugged`), so the trial ends itself: the prompt goes, the 15 s auto-revert is cancelled, `axiom ipc monitors revert` does nothing (`revert()` returns while `!pending`), and the trial layout stays live, unsaved. Turning the wrong monitor off is the case the revert exists for. Code path confirmed; that Hyprland sends `monitorremoved` for a rule-disabled monitor wants one nested Hyprland run (`scripts/dev/nested.sh hyprland`). Fix: end the trial only on a hotplug the trial's own rules don't explain (record the outputs `apply()` expects to stay enabled), or keep the countdown running.
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
- **What:** In detached mode the daemon re-applies binds by eval only (`runtimeApply`, no reload, so no `configreloaded`). The page re-reads Hyprland's binds only on `configReloaded`, on open, and through `refreshSoon`, whose one caller is the merge (KeybindEditor.qml:500); the Go port (dd773ed) dropped the three `refreshSoon()` calls the QML runtime layer made after each apply. `_appliedBinds` follows the daemon's state at once, so the two disagree until the page reopens: move a bind from SUPER + Q to SUPER + W and Save, and SUPER + Q shows as the user's own bind (reference, key map colour, "Your compositor config uses this key" on a new bind there) while SUPER + W is missing. Fix: `on_AppliedBindsChanged: refreshSoon()` in KeybindManager (its debounce and `_readAgain` guard already absorb bursts).
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
- **What:** Two chunks are sent as one eval with no `pcall`, unlike `addLayerRules`, which wraps each rule for exactly this. `runtimeApply` (hypr.go:221-228) puts the binds, required settings, look/input/blur and strips lines first and `AXIOM_RUNTIME_KEYS = {…}` last: a look or strips line Hyprland raises on (an option this version doesn't know) leaves the binds live but unrecorded, so the next apply unbinds nothing, reads axiom's own binds as the user's, reports them in `skippedKeys` and stops managing them until Hyprland reloads (and `AXIOM_STRIPS` stays unset). `outputs.apply` joins every `hl.monitor` call into one eval (outputs.go:55), so the first refused rule leaves the monitors after it unlaid; niri's branch below sends them one at a time for that reason. PLAUSIBLE: whether `hl.config`/`hl.monitor` raise on a bad value wants one nested Hyprland run. Fix: emit `AXIOM_RUNTIME_KEYS` right after the binds and wrap the look/input/blur and strips groups each in `pcall`; wrap each `hl.monitor` in `pcall`, collect the errors and `error(table.concat(e, "; "))` at the end so the refusal is still reported.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### A user/ file with a dot in its name never loads
- **Where:** `backend/internal/compositor/render/hyprconfig.go` (`UserFilesLua`), `backend/internal/compositor/binds/hypr.go` (the extract's module name)
- **What:** The managed and released files load each `user/*.lua` as `require("user." .. name)`, and the bind extract uses the same module name. Lua's `require` turns every `.` into `/`, so `user/my.binds.lua` is looked for as `user/my/binds.lua`: it never loads (Hyprland's config errors say module not found) and the merge reports an error for it. Reproduced against the extract. Nothing warns about dotted names (docs/installation.md only says `require("user.<name>")`). Fix: load such files with `dofile` (or skip them with a reported error), and say so in config-modes.md › managed.
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
- **What:** Each `captureKeys(true)` arms a 30 s `hl.timer` that leaves `axiom_record` if it's the current submap, and nothing cancels it when the recording stops. Record a key at t=0, finish at t=3, Add bind at t=10: the first timer leaves the second recording's submap at t=30, while QML still shows "Press a combo…" until t=35. Each start also redefines the submap, adding another copy of its unreachable bind (redefining a submap adds to it, as window-switcher.md notes). PLAUSIBLE and likely softened: the recorder's `ShortcutInhibitor` (KeyRecorder.qml) should keep Hyprland's binds from firing while it has focus. Sway already avoids the race by naming each mode anew. Fix: a generation in Lua (`AXIOM_CAPTURE_GEN`) checked by the timer and bumped on leave, and define the submap once.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Two keybind reference paths drop a key's binds
- **Where:** `services/compositor/KeybindsPageState.qml` (`_bindMods`), `components/methods/BindRows.qml` (`collapseDirections`)
- **What:** `_bindMods` decodes a bind's modifiers from its `BindKeys.keyId`, which leaves a tap's own modifier out, so a hand-written or merged `SUPER + Super_L` bind has no modifiers and the SUPER chip filters it out (the recorder's plain `Super_L` is unaffected). `collapseDirections` keeps only the first row per direction and merges only those (`_merged(ordered, …)`, BindRows.qml:107-119), while `_buildKeybindings` keeps rows whose labels differ in case apart ("Focus Left" next to "Focus left"), so the second row's `ids`, `user` and `overrides` are lost and the key map and combo lookup miss its key. Both rare. Fix: take the modifiers from `KeyNames.split(bind.key).mods`; pass all `members` to `_merged` and keep `ordered` for the cluster, with a test row of two "left" rows.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The monitor prompt's padding is a bare 18 px, and check_sizes misses it
- **Where:** `components/surfaces/monitors/MonitorPromptWindow.qml` (`pad`), `scripts/check_sizes.py` (`SIZE_WORD`)
- **What:** `readonly property int pad: 18` (MonitorPromptWindow.qml:19, used at :50-51) stays 18 px at every Interface scale while the card's text scales; AGENTS.md has sizes outside the bars from `Widget.px(n)`. `check_sizes.py` doesn't flag it because its size words have no `pad`. Fix: `Widget.px(18)`, and add `pad` to `SIZE_WORD` (the check that would have caught it).
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### HyprlandManager keeps members only it reads
- **Where:** `services/compositor/HyprlandManager.qml` (`withAnimations`, `_optionsWaiting`, `runLua`, `withBinds`, `layerApplied`, `refreshOptions`, `animations`, `animationsEnabled`, `_compaction`, `applyRemap`, `_bases`), `docs/dev/hyprland/ipc.md`, `docs/recipes/service.md`
- **What:** Deletion pass, about 40 lines. `withAnimations` has no caller, and `_optionsWaiting` serves only it (about 11 lines). `runLua` is a public wrapper whose only callers are its own `captureKeys` and `leaveSwitcher` (7 lines; `_eval` there). `withBinds` is used only by `withMainBinds` (inline, about 4). `layerApplied` only forwards to `refreshOptions` under two stacked comments (one function, about 4). `animations`/`animationsEnabled` are public but feed only `_workspaceAnim` (compute it in `_readOptions`, about 6). `_compaction` and `applyRemap` wrap their lines in the same animation-off/on prelude and epilogue (one `_runPlan(lines)`, about 4). `_bases` is recomputed on every output change though only the scrolling layout reads it (gate on `dynamicByLayout`, 2; the copy itself is by design, workspaces.md › Layouts). ipc.md's list of what `CompositorManager` uses ("`runLua`, `withOutputs`, `withBinds`, `refreshOptions`, `animations`, `switcherKey`") names a `withOutputs` that doesn't exist and four members no other file calls, leaves out `WindowSwitcherManager` (`leaveSwitcher`, `switcherKey`) and `CompositorConfigManager` (`layerApplied`) reaching the backend, and says the runtime layer's unbind goes through `runLua` (it's the daemon's now); service.md:109 also names `runLua`.
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### WindowSwitcherConfig.compositorSwitcher is a reader member nothing reads
- **Where:** `config/WindowSwitcherConfig.qml` (`compositorSwitcher`)
- **What:** No QML reads `WindowSwitcherConfig.compositorSwitcher`: the daemon reads the setting itself (`manager/niri_test.go` pins it). It isn't in "Three reader members nothing reads" or `scripts/config-usage-baseline.json`, because the unused-member check misses it ([its own entry](#the-unused-reader-member-check-counts-a-member-named-after-its-key-as-used)). Deletion pass: 3 lines.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### A bind description's section is parsed three ways
- **Where:** `services/compositor/KeybindsPageState.qml` (`_bindSection`), `services/compositor/KeybindManager.qml` (`bindLabel`, `_buildKeybindings`), `components/methods/BindActions.qml` (`hasOwnSection`)
- **What:** "Section: Label" is split three ways: `indexOf(": ")`, `indexOf(":")` and `split(":")[0]`. Only the editor's (`_bindSection`) doesn't trim, so `" Media: Play"` or `"Media : Play"` passes `hasOwnSection` (which trims) and gets its own " Media"/"Media " section and chip in the editor, while the reference shows it under Media. Fix: one `BindActions.splitDescription(text) → { section, label }` (trimmed), with test rows for a leading space and `a:b: c`, used by all three.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### KeybindManager keeps tables the methods helpers already hold
- **Where:** `services/compositor/KeybindManager.qml` (`_modifiers`, `decodeMods`, `_keyNames`, `_appliedBinds`, `userKeyCounts`), `components/methods/BindKeys.qml` (`_modBits`), `components/methods/KeyMap.qml` (`labelOf`), `services/compositor/KeybindsPageState.qml` (`_bindMods`)
- **What:** Deletion pass, about 36 lines. `_modifiers` (33 lines) is a second name↔mask table, the inverse of `BindKeys._modBits`, and `_bindMods` parses keyId's string (`parseInt`) to get a mask back: one `decodeMods(mask)` in BindKeys, built from `_modBits`, replaces it (net about -25), and the two can't disagree. Nine `_keyNames` entries (`mouse:272/273/274`, `mouse_up/down`, `left/right/up/down`) return what `KeyMap.labelOf` already does, which `_formatKey` asks next (about 9 lines). The skipped-key list is computed twice (KeybindManager.qml:230 and :245; one property, -2).
- **Size:** small
- **Found:** 2026-10-30, while reviewing the hyprland system

### The workspace strips repeat ActiveStrip's loader
- **Where:** `components/bar/widgets/Workspaces/WorkspaceStrip.qml`, `components/bar/widgets/Workspaces/WorkspaceGridStrip.qml`, `components/bar/widgets/Workspaces/ActiveStrip.qml` (`hasWindows`)
- **What:** Both strips hold the same `Loader { active: stripDirection !== ""; visible: hasWindows; ActiveStrip { 12 bindings } }` (only the text colour differs) and the same `stripOnly` expression but for the id count; `ActiveStrip.hasWindows` also calls `CompositorManager.stripWindows` again beside its `StripWindows`. Deletion pass: move the loader into ActiveStrip (it sets its own `active`/`visible` and exposes `stripOnly(count)`), about 20 lines.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The managed file's catch-all monitor line is copied into M.monitors
- **Where:** `backend/internal/compositor/render/hyprlua.go` (`HyprFileMonitorCalls`), `backend/internal/compositor/manager/hypr.go`
- **What:** Until the outputs are read, `M.monitors()` is refilled from the file: every line starting `hl.monitor({ output = "`. In managed mode that matches the managed file's fixed catch-all `hl.monitor({ output = "", mode = "preferred", … })` (hyprconfig.go:528) too, so each write made before the first read adds one more copy inside `M.monitors()`. Harmless (each replaces the default rule; the next write after a read cleans up) but the file churns and the layer key changes. Fix: read only the lines inside `function M.monitors()`, or skip `output = ""`.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### Hyprland's exit command is kept in two packages
- **Where:** `backend/internal/compositor/binds/hypr.go` (`exitCommand`), `backend/internal/compositor/render/hyprconfig.go` (`exitLua`)
- **What:** The merge maps `exec_cmd(<exitCommand>)` to `exitSession` and the writer emits `exitLua` for `exitSession`: the same string, kept by hand in two places (hypr.go:44, hyprconfig.go:30), with no test tying them. Changed alone, a written exit bind merges back as a plain `exec`. Fix: one constant (e.g. in `actions`) used by both; deletion pass 1 line.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### noteReload counts every compositor reload a second time
- **Where:** `backend/internal/compositor/manager/manager.go` (`seenReload`, `noteReload`), `backend/internal/compositor/manager/runtime.go`, `backend/internal/compositor/manager/hypr.go`, `backend/internal/compositor/manager/sway.go`, `backend/internal/compositor/manager/niri.go`, `docs/dev/hyprland/config-modes.md`
- **What:** `watchReloads` calls `seenReload()` from its forwarder as the event arrives (the count `runtimeLayer.read`'s retry relies on); the manager's reload handler then calls `noteReload()` (manager.go:1184), adding 1 to the same counter on the goroutine that also runs the read, where it can't land mid-read. Deletion pass, about 9 lines: drop `noteReload` from the writer interface, its three implementations, `runtimeLayer.noteReload` and the call; config-modes.md › detached names `noteReload()` and should name `seenReload`.
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
- **Where:** `scripts/gen_docs.py` (the reader-member usage count), `scripts/config-usage-baseline.json`
- **What:** gen_docs.py (around line 334) counts a reader member as used inside its reader when its name appears more than once there. `(?<![\w])name\b` also matches the `.name` in the member's own `_c.name` binding, so every member named after its config key passes, read or not: `WindowSwitcherConfig.compositorSwitcher` has no reader anywhere and isn't listed (see "WindowSwitcherConfig.compositorSwitcher is a reader member nothing reads"). Fix: don't count a match preceded by `.`, or count `<Reader>.<member>` uses outside the reader; then shrink the baseline by whatever it newly finds.
- **Size:** trivial
- **Found:** 2026-10-30, while reviewing the hyprland system

### The window switcher's blur and release on sway and niri
- **Where:** `services/compositor/WindowSwitcherManager.qml` (`commit`, `pick`), `components/surfaces/switcher/SwitcherKeys.qml`, `components/surfaces/switcher/SwitcherStrip.qml`
- **What:** From the maintainer's notes: the switcher's blur background is broken, and releasing the modifier doesn't always switch to the picked window on compositors other than Hyprland (sway's binds report steps only, and `SwitcherKeys` has to see the release). It "should work the same on niri since it just shows windows". On niri this is only while `WindowSwitcher.compositorSwitcher` is off or in detached mode: by default the included and managed files bind the keys to niri's own switcher (row 16). The plan settles one release path that works on every compositor and the switcher's backing.
- **Size:** needs a plan
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

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

### The system stats widget changes width with its digits
- **Where:** `components/bar/widgets/SystemStats/SystemStats.qml`
- **What:** From the maintainer's notes: going between one and two digits changes the widget's width, moving everything beside it; it should keep a constant size.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Modules inside borders aren't sized evenly
- **Where:** `components/hosts/overlay/ModuleGrid.qml`, `components/hosts/overlay/OverlaySlot.qml`
- **What:** From the maintainer's notes: module sizing within borders isn't even (the space around modules framed by a border differs from side to side or between modules).
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
- **Where:** `components/bar/BarWidgetHost.qml` (`Component.onCompleted`'s `Qt.callLater`), `components/bar/widgets/Workspaces/ActiveCellIndicator.qml` (`_placed`)
- **What:** Restoring a saved config that rebuilds the bars logs `TypeError: Value is null and could not be converted to an object` (8–12 per rebuild) and `Cannot read property 'index' of null` from `ActiveCellIndicator`: the `Qt.callLater` closures run after their item was destroyed. Also on the same swaps, `Button.qml` logs `Unable to assign [undefined] to QString` for `icon`/`text` while its properties are being replaced.
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
