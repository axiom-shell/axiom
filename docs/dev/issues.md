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

### CI checks dependencies only when a PR touches Go
- **Where:** `.github/workflows/checks.yml` (the `go` job's change filter)
- **What:** Since checks run on pull requests only and the `go` job is skipped unless the binary's inputs changed (#107), govulncheck runs only on PRs that touch Go, with no scheduled run, so a newly published advisory for a dependency goes unseen until the next Go PR. (The amd64/arm64 cross-builds run at every merge now, in `.github/workflows/edge.yml`, so an arm64 break surfaces right after merge, not at release.) A weekly `schedule:` run of the `go` job would cover it.
- **Size:** small
- **Found:** 2026-10-26, while auditing the autopilot's Phase 1 PRs

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

### Running it unattended's gate can't get `verify ok` on a committed branch
- **Where:** `docs/dev/roadmap.md` (Running it unattended, step 5), `scripts/dev/verify.sh`
- **What:** Step 5 tells the leader to run `scripts/dev/verify.sh` on the pushed branch and expect `verify ok`, but verify.sh checks changes since HEAD, so on a clean committed branch it prints only `nothing changed since HEAD`. The leader used `scripts/dev/verify.sh --all` (`all checks passed`) instead; the step should say so.
- **Size:** trivial
- **Found:** 2026-10-26, while taking the binds-child segfault from the roadmap

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

### A compositor manager test misses its takeover prompt under load
- **Where:** `backend/internal/compositor/manager/manager_test.go` (`TestAConfigGivenBackMeanwhileIsntWrittenOver`, `harness.eventually`)
- **What:** CI on PR #184 (which touched no Go) failed with `manager_test.go:555: never: asked again` (state `"status":"pending"`, `"takeoverPending":false`). The wait covers a live change whose file sync comes 2 s later, inside `eventually`'s 3 s bound, so a loaded runner has 1 s of slack; the test runs `t.Parallel()` with the package. A flaky CI failure blocks an unrelated PR. A possible fix: a longer bound for this wait, or a sync delay the test sets shorter.
- **Size:** trivial
- **Found:** 2026-10-28, while merging the niri screenshot fix (CI on PR #184)

### A self-update test once took the build path for a release
- **Where:** `backend/internal/daemon/selfupdate_test.go` (`TestReplaceInstalled`)
- **What:** Locally, `go test -count=1 ./internal/compositor/... ./internal/daemon/` failed once with `selfupdate_test.go:68: rebuilt true from "built", reason ""` in the case `a release's` (the fake release server's binary should have been taken), then passed on a rerun. Likely the release fetch failing or timing out under parallel load, so `replaceInstalled` fell back to building; not reproduced.
- **Size:** small
- **Found:** 2026-10-29, while running the Go tests for roadmap row 13

### A binds test fails with pthread_create failed in CI
- **Where:** `backend/internal/compositor/binds/isolate_test.go` (`TestIsolatedExtractSurvivesAFileTakingAllMemory`)
- **What:** CI on PR #124 (which touched no Go) failed with `isolate_test.go:115: got reading the binds: runtime/cgo: pthread_create failed: Resource temporarily unavailable: exit status 2`, then passed on a rerun. The test expects the child to be ended by its memory limit (an error naming `MiB`); this time the child couldn't start a thread (`EAGAIN`, likely the limit or a loaded runner's thread cap reached while the Go runtime was still starting threads) and failed with the cgo error instead. A flaky CI failure blocks an unrelated PR.
- **Size:** trivial
- **Found:** 2026-10-27, while finishing the singletons plan (#123)

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

### A hot reload while locked leaves niri's red screen
- **Where:** `services/session/LockManager.qml` (its `PersistentProperties` locked state), `components/surfaces/lockscreen/LockSurface.qml`
- **What:** A QML reload while the session is locked destroys the lock object: `Session lock object was destroyed without unlocking. The session will stay locked in case this was accidental.` The locked state is kept, so the new generation should lock again, but on niri (2026-10-18) the screen stayed niri's red locked background with no way out, and only restarting niri got the session back. Saving any loaded file while the idle locker has locked the screen does it. Check whether the new generation's `WlSessionLock` takes over the old lock on niri (and on sway/Hyprland), or have the lock object survive a reload.
- **Size:** small
- **Found:** 2026-10-18, while adding niri's blur (an edit hot-reloaded while the screen was idle-locked)


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

### The check order is kept in three places
- **Where:** `scripts/check_all.sh`, `scripts/dev/verify.sh`, `.github/workflows/checks.yml`
- **What:** The same checks, in the same order, are listed by hand three times; a check added to one can be missed in the others. One list (a file the three read, or `check_all.sh` as the one CI runs) keeps them equal. They have drifted already: CI's `JSON is valid` step (`python3 -m json.tool` over every tracked `.json`) is in neither `check_all.sh` nor verify.sh, so `verify.sh --all` passes a broken JSON file that CI fails.
- **Size:** small
- **Found:** 2026-10-26, while reviewing the repository's organization

### verify.sh skips the checks a deletion or a check's own change needs
- **Where:** `scripts/dev/verify.sh` (`changed`, the step triggers)
- **What:** `changed` keeps only files that exist (`[[ -f "$f" ]]`), so a deleted file triggers nothing: deleting a Go file runs no Go checks (the package may no longer build), deleting a QML or script file a doc cites runs no `check_docs.py`, and a change that only deletes prints `nothing changed since HEAD`. CI then fails what verify passed; the roadmap's "Delete before adding" makes this the common case. The triggers also miss a check's own change: `check_docs.py` runs only when a `.md` or `.qml` changed (not for `config/schema/` YAML, though it checks the `x-*` annotations, nor for a change to `check_docs.py` itself), `check_qmllint.py` and `check_sizes.py` only when QML changed, `check_docs.py` has a `CheckDocs` class in `tests/scripts/test_scripts.py` the script map doesn't run, and `.githooks/pre-commit` (not `*.sh`) is never shellchecked. Fix: keep deleted paths in `changed` for the triggers (filter only where a step reads the file, as qmlformat does), and map each `scripts/check_*` file to its own check.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### The guard misses compound commands, wrapper options and writes onto config.json
- **Where:** `.claude/hooks/guard.py` (`split_commands`, `simple`, `check_argv`), `tests/scripts/test_guard.py`
- **What:** Probing `guard.check` with ordinary shell forms (not adversarial ones) lets these through: `(qs kill)`, `{ qs kill; }`, `$(qs kill)`, `if true; then qs kill; fi` (`(`, `{`, `$(` and `then` are taken as the command's name); `sudo -u me axiom lock`, `nice axiom lock`, `flock /tmp/l axiom lock`, `systemd-run --user axiom quit` (a wrapper's option value becomes the command; `nice`, `flock`, `systemd-run` aren't wrappers); `gh -R a/b issue create` (only `args[:2] == ["issue", "create"]`); and every Bash write onto the live config.json: `cp x ~/.config/axiom/config.json`, `mv x <it>`, `> <it>`, `tee <it>`, `sed -i … <it>`, which skip the `x-takeover` check `check_config_edit` gives Edit and Write. The last is how a raw copy over config.json once dropped `Compositor.mode` managed. Also `rm -r ~/.config` and `find ~/.config/axiom -name config.json -delete` delete it unchecked. Fix: split on `(`, `)`, `{`, `}`, `$(`, backticks and the shell keywords; skip a wrapper's option values; match `issue create` anywhere in gh's argv; refuse a Bash write whose target is `LIVE_CONFIG` (cp/mv/install destination, `>`/`>>`, tee, `sed -i`), each with a `test_guard.py` case.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### CI's Go tests run as root, so the unwritable-file tests never run there
- **Where:** `.github/workflows/checks.yml` (the `go` job), `backend/internal/compositor/binds/binds_test.go` (`TestAnUnwritableFileFailsAlone`), `backend/internal/compositor/manager/manager_test.go` (`TestAFailedReleaseIsRetried`), `backend/internal/compositor/manager/sway_test.go`, `backend/internal/compositor/userconf/userconf_test.go`, `backend/internal/compositor/edit/hookup_test.go`, `backend/internal/daemon/selfupdate_test.go`
- **What:** The `go` job runs in `archlinux:latest` as root, and six tests skip when `os.Geteuid() == 0` ("root writes anywhere"): the refusal paths for a file the user can't read or write (a failed release retried, an unwritable bind file failing alone, a read-only install). They run only on a developer's machine, so a PR from someone who didn't run them merges with those paths untested. Fix: run `scripts/check_go.sh --ci` as an unprivileged user in the container (`useradd -m ci`, a chown of the workspace and Go caches, `su ci -c …` or `setpriv`).
- **Size:** small
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### check_go.sh passes stale generated code except under --ci
- **Where:** `scripts/check_go.sh` (`generated`), `scripts/check_all.sh`
- **What:** `generated` rewrites the committed `zz_generated_*` files with `go generate`, then fails on a stale one only with `--ci`; check_all.sh (documented as "every check CI runs") calls `check_go.sh` without it, so `verify.sh --all` prints `all checks passed` on a branch CI fails, leaving the regenerated file as an unnoticed working-tree change. The usage says the plain run checks "generated code fresh". Fix: fail on stale generated code whenever `--fix` isn't given (keep `--ci` for govulncheck).
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### CI can't fail on stale translation files
- **Where:** `scripts/check_i18n.py` (`main`), `.github/workflows/checks.yml` (Translations, `continue-on-error`)
- **What:** `check_i18n.py` exits 1 for any key without a translation (empty counts as missing), which is the normal state, so CI runs it as a warning only. The same exit carries the real errors: a stale `config/i18n/template/language.json` (generated, AGENTS.md › Checks), a file not in the canonical format, keys absent from a file or unused. A commit made without the pre-commit hook (a fresh clone or worktree before `git config core.hooksPath .githooks`, or `--no-verify`) lands them with CI green. Fix: exit 1 only for the template, the format, and keys absent or unused; report empty ones without failing; drop `continue-on-error`.
- **Size:** small
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### The qmllint baseline doesn't shrink when warnings are fixed
- **Where:** `scripts/check_qmllint.py` (`main`), `scripts/qmllint-baseline.json`
- **What:** A baselined warning that's gone only prints `note: N baselined warnings are gone`, and the baseline keeps its count, so the warning can come back later without failing. AGENTS.md calls the baselines ratchets, and the allowlist already fails on an unused entry (`check_structure.py`). Fix: fail (or have verify.sh rewrite the baseline) when the counts drop, as the allowlist does.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### check_structure's Quickshell.Io check doesn't see IpcHandler
- **Where:** `scripts/check_structure.py` (`IO_KINDS`)
- **What:** The comment above the check says IPC handlers are moving to the daemon too, and AGENTS.md says IPC comes through `IpcTarget`, but `IO_KINDS` lists only `Process`, `FileView`, `Socket` and `Quickshell.execDetached`; no QML uses `IpcHandler` now, so a new one (agents add temporary ones to open a popout for a screenshot) would pass. Fix: add `IpcHandler` to `IO_KINDS`.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### The permission deny list names a config path that's gone
- **Where:** `.claude/settings.json` (`permissions.deny`), `.claude/hooks/guard.py` (docstring)
- **What:** `permissions.deny` still refuses `rm config/user/config.json` (the folder no longer exists) and refuses `git clean -x`/`-X`/`-fdx`, which neither AGENTS.md › Never nor the guard mentions, though the guard's docstring says the deny list "repeats the plain ones". Fix: drop those two lines, and either name `git clean -x` in AGENTS.md (it deletes the generated files and local state) or drop it.
- **Size:** trivial
- **Found:** 2026-10-29, while reviewing the guardrails system (roadmap row 18)

### Small tooling leftovers
- **Where:** `components/methods/IconResolver.qml`, `packaging/aur/`, `docs/dev/core/i18n.md`
- **What:** `IconResolver` is the one methods helper without a test (`tst_IconResolver`) (and the one importing `Quickshell`, for `iconPath`). The `axiom-shell` and `axiom-shell-git` PKGBUILDs are near copies. `check_doc_drift.py` flags `i18n.md` (12 commits behind its files, after the services moved to folders).
- **Size:** trivial
- **Found:** 2026-10-26, while reviewing the repository's organization

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

### Notifications have no blur backing on sway and Hyprland
- **Where:** `components/surfaces/notifications/NotificationToast.qml` (a `PopupWindow`), `shell/Notifications.qml` (`anchorPanel`), `backend/internal/compositor/render/sway.go` (`SwaySurfaceBlurLines`)
- **What:** From the maintainer's notes: a notification gets no blur backing (always, or likely only the first after launch; on sway too). Not reproduced in nested niri (2026-10-29, at 70% opacity): every toast blurred, the first after launch too (`BoxBlurRegion`). Nested Hyprland doesn't start under niri, and nested sway isn't used. Likely cause on sway: a toast is an xdg_popup of the 1×1 `axiom-notifications` layer window, and SwayFX's `layer_effects` doesn't blur a layer's popups ([sway backend](compositor/sway-backend.md)), so the rule written for that namespace blurs only the invisible anchor. On Hyprland the `axiom-blur` rule's `blur_popups` should cover them; why the first wouldn't is unexplained. A possible fix (a guess for Hyprland, whose cause is unknown): each toast its own layer window in that namespace (corner anchors, the gap plus its stack offset as margins, Normal exclusion), blurred by the rules like the other `blurSurfaces`; it then wants `no_anim` on Hyprland, as it slides itself.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap; narrowed 2026-10-29 (the border half fixed)

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

### Notifications can only sit in a corner
- **Where:** `config/NotificationsConfig.qml`, `config/schema/sections/Notifications.yaml` (`position`)
- **What:** `Notifications.position` is `topLeft` | `topRight` | `bottomLeft` | `bottomRight`. A centred bar (an island pill with `lockCenter`, a frame setup's empty top middle) can't have its toasts come out of the middle of an edge, the way the OSD (`position` 0–100 along an edge) and the launcher already can.
- **Size:** needs a plan
- **Found:** 2026-10-29, while building the revamped example setups (the Island example)

### Bar widget hosts settle after they're gone
- **Where:** `components/bar/BarWidgetHost.qml` (`Component.onCompleted`'s `Qt.callLater`), `components/bar/widgets/Workspaces/ActiveCellIndicator.qml` (`_placed`)
- **What:** Restoring a saved config that rebuilds the bars logs `TypeError: Value is null and could not be converted to an object` (8–12 per rebuild) and `Cannot read property 'index' of null` from `ActiveCellIndicator`: the `Qt.callLater` closures run after their item was destroyed. Also on the same swaps, `Button.qml` logs `Unable to assign [undefined] to QString` for `icon`/`text` while its properties are being replaced.
- **Size:** small
- **Found:** 2026-10-29, while building the revamped example setups
