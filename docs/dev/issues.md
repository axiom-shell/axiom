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

### A file write or change can be missed across a daemon re-exec
- **Where:** `services/core/FileManager.qml` (`write`, `watch`), `services/core/BackendManager.qml` (`_failQueued`)
- **What:** Calls in flight when the connection drops fail with `unavailable` (protocol.md), so a `file.write` out at the moment of a re-exec is dropped (logged `[FileManager] Could not write`; notes show "Couldn't save"), and the file keeps its older content until the next save of it. Likewise a change made on disk between the drop and the next hello pushes nothing (the watch is gone until `onGreeted` sends it again), so a todo list or open note edited elsewhere in that moment isn't reloaded. FileView wrote and watched in-process, with no such gap. Rare (a ~200 ms window per re-exec, which dev mode does on every Go save); a fix would resend a write that failed `unavailable` and call each watcher once after a re-hello.
- **Size:** small
- **Found:** 2026-10-28, while reviewing the file.write / file.watch move (backend stage 6)

### Calls in flight are lost across a daemon re-exec, one service at a time
- **Where:** `services/core/BackendManager.qml` (`_failQueued`, `call`), `services/core/FileManager.qml` (`write`), `services/core/ThemeManager.qml` (`themeIntegrations`), `services/system/MediaManager.qml` (the album art fetch)
- **What:** Three entries share one cause: a re-exec fails every call in flight with `unavailable` (`the connection to axiom closed`), and each caller then warns or drops its work ("A file write or change can be missed across a daemon re-exec", "ThemeManager warns when the daemon's re-exec fails its integrations", "MediaManager warns when the daemon's re-exec fails its album art fetch"). Each new funnel adds callers, so fixing them one service at a time keeps adding entries. One fix in `BackendManager` would close all three: a call marked safe to repeat (an option on `call`) is held and sent again after the next hello rather than failed, and watchers are called once after a re-hello; the caller decides what's safe (a whole-file `file.write`, `theme.integrate`, `media.art` are; a `share.import` isn't). Not the daemon's own commands ("The daemon's own commands are left zombies across a re-exec") or the updates check's warning, which are Go-side.
- **Size:** small
- **Found:** 2026-10-28, while reviewing row 11's PRs (#155 to #158)

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

### An unreadable sway config file still binds axiom's keys silently
- **Where:** `backend/internal/compositor/manager/sway.go` (`userBinds`), `backend/internal/compositor/userconf/sway.go` (`SwayText`)
- **What:** #109 shows `UnreadBinds` as the manager's problem only when `userconf.SwayMain` finds no config (`w.unread = main == ""`). A main config that exists but can't be read, or an include that can't be read, is skipped silently by `SwayText` (`os.ReadFile` failing returns `""`), so axiom binds over the keys those files hold with no problem shown. The decision behind #109 ("an unreadable config is realistically axiom's own reader failing on one sway accepts") is about exactly this case, not a missing file. `SwayText` could report the paths it failed to read, and `userBinds` could set `unread` when any did.
- **Size:** small
- **Found:** 2026-10-26, while auditing the autopilot's Phase 1 PRs

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

### The updates check warns when a daemon re-exec kills checkupdates
- **Where:** `backend/internal/updates/updates.go` (`Source`'s `Fetch`, `runCheck`)
- **What:** `axiom daemon logs` shows `checking for updates` with `checkupdates failed (-1): ` 7 times since 2026-10-26, each within a few seconds of a `dev build done: re-executing` line (12:33:56.102 after a re-exec at 12:33:55.828 on 2026-10-27). Exit code -1 is a kill by a signal: most likely the old image's context ends at the re-exec, the check's `checkupdates` is killed with it, and `Fetch` logs the failure before the hub drops the fetch as cancelled. A `ctx.Err()` check before the warning would quiet it; the next image checks again anyway.
- **Size:** small
- **Found:** 2026-10-27, while merging #133

### ThemeManager warns when the daemon's re-exec fails its integrations
- **Where:** `services/core/ThemeManager.qml` (`themeIntegrations`)
- **What:** As with `MediaManager`'s album art: a daemon re-exec (dev mode rebuilding after a Go edit) fails a `theme.integrate` call in flight, and ThemeManager logs `Theme integrations failed: the connection to axiom closed`, though the call could simply be sent again after the next hello.
- **Size:** trivial
- **Found:** 2026-10-27, while porting the greeter installer (a dev-mode re-exec during the batch)

### MediaManager warns when the daemon's re-exec fails its album art fetch
- **Where:** `services/system/MediaManager.qml` (the album art fetch)
- **What:** A daemon re-exec fails every request in flight with `the connection to axiom closed`, and `MediaManager` warns about it, though it's an expected failure it could retry on the next hello. #112 had folded it into "The shell's socket warns when the daemon re-execs", but the socket's warning is Quickshell's and this one is ours to quiet.
- **Size:** trivial
- **Found:** 2026-10-26, while auditing the autopilot's Phase 1 PRs

### The polkit agent fails to register on reloads
- **Where:** `services/session/PolkitManager.qml` (`_registerCheck`)
- **What:** In the live session the log shows `[PolkitManager] Could not register as the polkit agent` with no other agent named, on most reloads (6 in one session's `scripts/log.sh --all`) and at the start, where Quickshell logs `quickshell.service.polkit.listener` `failed to register listener: GDBus.Error:org.freedesktop.PolicyKit1.Error.Failed: An authentication agent already exists for the given subject`. `_probe` finds no other agent, so possibly the previous generation's listener (or one left by the daemon's restart) still holds the subject. Not looked into: next step, check `busctl` for the agent's owner across a reload.
- **Size:** needs a plan
- **Found:** 2026-10-26, while reading the log for the unloaded config's compositor mode

### Running it unattended's gate can't get `verify ok` on a committed branch
- **Where:** `docs/dev/roadmap.md` (Running it unattended, step 5), `scripts/dev/verify.sh`
- **What:** Step 5 tells the leader to run `scripts/dev/verify.sh` on the pushed branch and expect `verify ok`, but verify.sh checks changes since HEAD, so on a clean committed branch it prints only `nothing changed since HEAD`. The leader used `scripts/dev/verify.sh --all` (`all checks passed`) instead; the step should say so.
- **Size:** trivial
- **Found:** 2026-10-26, while taking the binds-child segfault from the roadmap

### A notification's avatar warns when its saved image is gone
- **Where:** `components/content/parts/notifications/NotificationAvatar.qml` (`picture`)
- **What:** A history notification whose image file in `~/.local/state/axiom/notifications/` no longer exists logs `Cannot open: file:///…/notifications/<id>.png` on every build of its row. The avatar should fall back to the app icon quietly (check `picture.status`, or drop the image path from history when the file is removed).
- **Size:** small
- **Found:** 2026-10-24, while moving services to the axiom daemon

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

### The scrolling layout's workspaces don't come back with their monitor
- **Where:** `services/compositor/HyprlandManager.qml` (`dynamicByLayout`, `_compaction`), `components/methods/DynamicWorkspaces.qml`
- **What:** niri keeps an unplugged monitor's workspaces and gives them back when it returns; under Hyprland's scrolling layout, Hyprland moves them to another monitor, where they're outside its block, so they drop out of its list (`DynamicWorkspaces.workspaces`) until `workspaces reconcile`. Workspaces the user's config makes persistent stay empty in the middle of the list, as compaction moves no workspace without windows. Neither is tried yet.
- **Size:** needs a plan
- **Found:** 2026-10-19, while adding the scrolling layout

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

### A supervise test times out under a loaded run
- **Where:** `backend/internal/supervise/supervise_test.go` (`TestOrphanOfAnEarlierDaemonIsStopped`, `eventually`)
- **What:** One `scripts/check_go.sh` run failed with `supervise_test.go:143: timed out` (the orphan wasn't seen stopped within `eventually`'s 2 s), then passed on the next two runs with nothing changed in `supervise`. The test runs `t.Parallel()` with the rest of the package and `go test` runs packages at once, so 2 s is tight under load; a flaky CI failure blocks an unrelated PR. A possible fix: a longer bound for this wait, or stop the orphan before polling.
- **Size:** trivial
- **Found:** 2026-10-26, while reviewing the takeover hold on config.json reloads

### A daemon test finds the instance lock still held
- **Where:** `backend/internal/daemon/reexec_test.go` (`TestStaleSocketIsRemovedOnlyUnderTheInstanceLock`)
- **What:** One `scripts/dev/verify.sh` run failed with `reexec_test.go:42: the daemon stopped: axiom is already running on wayland-test: held by process …` and `daemon_test.go:90: the daemon didn't stop`, then passed on a rerun with nothing changed in `daemon`: after `held.Release()`, the daemon `td.start` runs still found the lock held, likely by the refused `runBriefly` daemon's open lock file (or the test's own) not yet closed under a loaded parallel run. A possible fix: wait for `runBriefly`'s daemon to close everything before releasing, or retry the start briefly.
- **Size:** trivial
- **Found:** 2026-10-27, while verifying the Tailscale revamp

### A binds test fails with pthread_create failed in CI
- **Where:** `backend/internal/compositor/binds/isolate_test.go` (`TestIsolatedExtractSurvivesAFileTakingAllMemory`)
- **What:** CI on PR #124 (which touched no Go) failed with `isolate_test.go:115: got reading the binds: runtime/cgo: pthread_create failed: Resource temporarily unavailable: exit status 2`, then passed on a rerun. The test expects the child to be ended by its memory limit (an error naming `MiB`); this time the child couldn't start a thread (`EAGAIN`, likely the limit or a loaded runner's thread cap reached while the Go runtime was still starting threads) and failed with the cgo error instead. A flaky CI failure blocks an unrelated PR.
- **Size:** trivial
- **Found:** 2026-10-27, while finishing the singletons plan (#123)

### A dev-mode build test fails with text file busy
- **Where:** `backend/internal/daemon/dev_test.go` (`TestDevBuild`, `fakeGo`)
- **What:** One `scripts/check_go.sh` run failed with `dev_test.go:55: err go generate: fork/exec …/go: text file busy`, then passed on the next run with nothing changed in `daemon`. `fakeGo` writes an executable script while parallel subtests fork: a fork made while the file is still open for writing carries that descriptor, and exec of the script fails with ETXTBSY until that child execs. A possible fix: write the fake to a temp name and rename it into place, or retry the exec on ETXTBSY in the test helper.
- **Size:** trivial
- **Found:** 2026-10-26, while renaming the backend's `system` and `lock` packages

### A bar popout's stroke flashes off its fill switching content on niri
- **Where:** `components/hosts/popout/BarPopouts.qml` (`shownBoxWidth`/`shownBoxHeight`, the box gliding to new content), `shell/BlurBackingWindow.qml` (its fill), `components/hosts/popout/SwitchStill.qml`
- **What:** With blur on under niri, a bar popout switching to another widget's content in the same window shows its old stroke cutting into the box for a frame or two as it resizes: the stroke is the popout's window's, the fill the blur window's, and niri shows the two windows' frames out of step (no `supports.layerFrameSync`). Tried and reverted (2026-10-18), neither changing what the maintainer saw: holding the switch until the popout's window had drawn the new content twice (`SwitchStill`, its window's `frameSwapped`), and drawing the popout's stroke in the blur window with its fill (a stroke-only `AttachedSurfaceCopy` over the fills, the popout's own stroke transparent). That the second didn't help suggests the stroke isn't what's late: perhaps the popout's content, its clip, or the blur region. Next: log each window's `frameSwapped` with what it drew, during a switch.
- **Size:** small
- **Found:** 2026-10-18, while adding niri's blur


### A fullscreen window on one screen pauses the blur on every screen
- **Where:** `services/ui/BlurManager.qml` (`paused`)
- **What:** `paused` is on while any screen shows a fullscreen window, because Hyprland's layer rules apply to every monitor. On niri the blur is each window's own region (`supports.blurRegion`), so it could pause per screen. Instead, on two monitors with a fullscreen video on one, the other loses its blur, though its surfaces stay translucent (`fillOn` is per screen). A per-screen pause where `supports.blurRegion` would fix it (`regions`/`backdropRegions` per screen).
- **Size:** small
- **Found:** 2026-10-19, while reviewing niri's blur

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

### A screenshot under niri timed out waiting for its frame
- **Where:** `services/apps/ScreenshotManager.qml` (`_grabFrames`, `_grim`, `_watchdog`, `frameArrived`), `components/surfaces/screenshot/ScreenshotPickerWindow.qml` (`still`, `_onFrame`)
- **What:** The live shell on niri logged `The compositor sent no picture of the screen.` with no other warning: three times in `scripts/log.sh --all -g "no picture"` (2026-10-26). niri has no `supports.outputCapture`, so the picker's frame is grim's (`ScreenshotManager.grimFrames`): grim had already written each screen's PPM and exited 0 (a failure says so in its own message), `_grim`'s `onExited` set `picking` and started the 3 s watchdog, and the picker's `still` Image never reached `Image.Ready` in time, so `_onFrame` never called `frameArrived` (or, for an immediate `screen` shot, the capture never reported back through `finish`). An `Image.Error` (a PPM it can't read, a path gone) is never reported either: it waits out the watchdog with this message. Not reproduced; whether the asynchronous load of a large PPM is slow or fails isn't known yet. The maintainer's notes (2026-10-28) report it as "grim fails if it takes too long?" under niri.
- **Size:** small
- **Found:** 2026-10-26, while working on the shell–daemon contract check (in the live log)

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

### CommandOutput's figure text loops on its size
- **Where:** `components/content/CommandOutput/CommandOutput.qml` (the text `StyledText`, `id: body`)
- **What:** The log shows `Binding loop detected for property "textSize"` while a Command output card is on a shown page: in statement mode `body`'s `textSize` comes from `body.height / 5`, and a `Layout.fillHeight` text's height follows its implicit height, which follows the size.
- **Size:** small
- **Found:** 2026-10-18, while adding the todo list and pomodoro timer

### Profile switching runs in the shell on sway and niri
- **Where:** `services/compositor/MonitorManager.qml` (`_applySavedProfile`), `services/compositor/CompositorConfigManager.qml` (`_outputRules`), `services/session/GreetdManager.qml` (`_applyCompositor`), `backend/internal/daemon/compositorsocket.go` (`applyGreeter`)
- **What:** Without `supports.outputProfiles` (sway, niri) the shell picks the saved monitor profile for what's connected (`MonitorLayout.savedRules`) and hands its rules to Go: `MonitorManager` on every hotplug, `CompositorConfigManager` as `compositor.inputs`' `outputRules` fact for the config files, and the greeter once at its start (so a monitor plugged in at the greeter is never matched, where Hyprland's Lua picks again on each hotplug). Maintainer decision (2026-10-28), verbatim: "go owns profile switching for every compositor". The daemon would read the outputs itself (sway's `GET_OUTPUTS`, niri's `Outputs` request), watch hotplugs (niri's event stream is already in Go; sway needs an `output` subscription), pick and apply the profile in the session and the greeter alike, and compute the output rules in `buildInputs`; `_applySavedProfile`, `_outputRules` and the greeter's branch then go. Who reacts to a hotplug changes, so it's designed first.
- **Size:** needs a plan
- **Found:** 2026-10-28, while reviewing row 12's batch (5) (backend stage 7)

### The monitor profile picker exists twice
- **Where:** `components/methods/MonitorLayout.qml` (`matchProfile`, `savedRules`), `backend/internal/compositor/render/hyprlua.go` (`MonitorsLua`)
- **What:** The rule choosing the saved profile for the connected monitors (an exact match wins, else the one turning on most; ties to the earlier) is written twice: in QML for the session's sway and niri switching, the greeter and the Monitors page (`MonitorManager.liveProfile`, `_detect`), and as the Lua Go sends Hyprland (`render.MonitorsLua`), which picks on each hotplug. Kept in step only by `render/hyprlua_test.go`'s cases and comments naming each other. With profile switching in Go (the entry above), the Monitors page can ask the daemon which profile is live, leaving one Go copy (the Lua generated from it or checked against it).
- **Size:** small
- **Found:** 2026-10-28, while reviewing row 12's batch (5) (backend stage 7)

### install.sh still installs the rest of a feature whose COPR was declined
- **Where:** `install.sh` (the declined-COPR loop after the COPR prompts)
- **What:** Declining a COPR on Fedora marks each feature with a package from it as skipped, but drops only that COPR's packages: the feature's other packages stay in the one `dnf install`. Declining `nett00n/hyprland` while setting up niri skips the login screen's feature yet still installs `greetd`. Rebuilding `packages` from the features left (and the required keys) after the prompts would fix it; test with `--dry-run` in a `fedora:latest` container.
- **Size:** small
- **Found:** 2026-10-17, while reviewing the distro-support branch for merge

### A niri module refused in detached mode is only logged
- **Where:** `backend/internal/compositor/manager/niri.go` (`runtimeApply`), `services/compositor/CompositorConfigManager.qml` (`problem`)
- **What:** In the file modes a module `niri validate` refuses sets `CompositorConfigManager.problem` (the Compositor card shows it). The detached mode's module (also the file modes' fallback) is checked the same way, but a refusal is only a `compositor: niri refuses the config axiom made` warning in the daemon's log in the log: the card says nothing, and niri keeps the module before. A raw bind niri refuses is the likely cause.
- **Size:** small
- **Found:** 2026-10-17, while auditing the niri branch for merge

### A fullscreen window re-sends the whole live layer
- **Where:** `services/compositor/CompositorConfigManager.qml` (`_liveInputs`)
- **What:** `BlurManager.active` flips as a fullscreen window opens or closes and is in `_liveInputs`, so each flip re-sends the whole look and input (Hyprland's `hl.config({ input = … })`, sway's `[all] border pixel`, `gaps … all set`), not just the blur rules: a user's runtime tweak (`border toggle`, `gaps current plus`) is undone whenever anything goes fullscreen. A blur-only change should send only the blur lines.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### The takeover makes only some of sway's relative includes absolute
- **Where:** `backend/internal/compositor/takeover/kinds.go` (`sway`'s `absInclude`)
- **What:** Adopting a sway config makes its relative includes absolute (it moves to `user/`), but only an unquoted first path: a quoted relative include, and all but the first path of a multi-path `include`, stay relative and then resolve from `user/`. (The unchecked edit and the unescaped dir in the old script's sed went with the Go port.)
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### Turning sway's window opacity off reloads sway
- **Where:** `services/compositor/CompositorConfigManager.qml` (`_appliedParts`)
- **What:** Opacity counts as an applied part, so turning it off reloads the config (see "Changing a setting under sway can flash the screen"), though SwayManager already sets every window back to 1 itself. A part the backend takes back itself shouldn't count.
- **Size:** trivial
- **Found:** 2026-10-16, while auditing the sway branch for merge

### SwayFX's corner radius reaches only windows opened later
- **Where:** `backend/internal/compositor/render/sway.go` (`SwayFxLines`)
- **What:** `corner_radius` sent at runtime sets SwayFX 0.6's global only (its per-window reset runs only while the config loads), and it has no per-window command, so a changed rounding shows on new windows while open ones keep theirs until sway reloads its config. A fix would need a reload, which takes back the rest of the runtime look.
- **Size:** small
- **Found:** 2026-10-16, while fixing SwayFX's blur on unfocused windows

### Changing a setting under sway can flash the screen
- **Where:** `services/compositor/LayerManager.qml` (`_sequence`), `components/hosts/popout/LayerSlot.qml`, `services/compositor/MonitorManager.qml`
- **What:** Reported on sway: changing a setting flashes the whole settings page. Two causes fixed: the border's shadow window wasn't held, so turning the shadow on remapped every surface ordered under it (`LayerManager: mapping … again, in its place` for the backdrop, bars, border and dock, the backdrop dimming the overlay flashing with them), and a sway reload (any save rewriting axiom's file) reset the outputs to the config's, dropping the monitor profile. A third, on any compositor: the settings page rebuilt every card on each edit (its categories were recomputed from the config through `x-showIf`), fixed in `components/views/Settings/Settings.qml`. Not reproduced with an ordinary setting since (a save then logs no remap and no overlay resize). Without `layerOrder`, a bar remade by a change of kind still remaps everything after it, by design. If it still happens, note which setting and look for those log lines.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch

### Sway's special workspaces are floating scratchpad windows
- **Where:** `services/compositor/SwayManager.qml` (`toggleSpecial`, `moveToSpecial`), `components/methods/SwayState.qml` (`specialToggle`)
- **What:** Hyprland's special workspace is a tiled workspace drawn over the current one; sway has none, so a special group is marked scratchpad windows, and sway's scratchpad makes every window floating, centred and stacked on the others (a group of three shows as three overlapping windows). Options: keep the scratchpad and lay the group's windows out in a grid on show (`move position` / `resize set` per window, over the workspace like Hyprland's), or a hidden named workspace per group (tiles, but replaces the view instead of overlaying it). A group name holding `,` or `;` also breaks its `nop axiom special` bind (sway splits the command there). The maintainer's notes (2026-10-28) list it as "figure out what to do for scratchpad".
- **Size:** needs a plan
- **Found:** 2026-10-16, while auditing the sway branch

### Overview drops on sway nest split containers
- **Where:** `services/compositor/SwayManager.qml` (`placeWindow`)
- **What:** A drop next to a window runs `split h|v` on the target every time, which wraps it in a new container even when its parent already splits that way, so repeated drops nest containers sway then draws as such (tabbed/stacked parents behave oddly). Split only when the parent's layout differs (the tree has it).
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch

### Detached sway keeps the floating modifier after the mouse binds go
- **Where:** `backend/internal/compositor/manager/sway.go`, `backend/internal/compositor/render/sway.go` (`SwayUnbindLines`, `SwayFloatingModifier`)
- **What:** The runtime layer sends `floating_modifier` for the drag/resize binds but its unbind commands don't take it back, so removing them in detached mode leaves sway's floating modifier set until sway reloads. It also overrides a `floating_modifier` of the user's own config, which `render.RuntimeBinds` doesn't see as a taken key.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch

### `noWarps` off maps to sway's `mouse_warping output`
- **Where:** `config/schema/sections/WindowBehaviour.yaml` (`noWarps`, `x-compositor.sway.map`)
- **What:** Hyprland with `cursor.no_warps` off moves the cursor to a window focused by keybind; sway's `mouse_warping output` only moves it when focus changes output (`container` would match Hyprland). Decide which sway value matches what the setting promises.
- **Size:** trivial
- **Found:** 2026-10-16, while auditing the sway branch

### Quickshell's I3 socket warns on every reload
- **Where:** `services/compositor/SwayManager.qml` (Quickshell.I3)
- **What:** Under sway every reload of the shell logs `I3 event socket disconnected` twice (category `quickshell.I3.ipc`), from the old generation's sockets closing. Events still arrive afterwards (checked in nested sway). Quickshell's, not axiom's; nothing to fix here unless it starts dropping events.
- **Size:** trivial
- **Found:** 2026-10-16, while writing the sway backend

### Qt text-input warnings under sway and niri
- **Where:** `components/reusable/StyledTextEntry.qml` (the text fields; Qt's own wayland text-input)
- **What:** Under sway and niri the log fills with `Trying to disable` / `Trying to enable` warnings from `qt.qpa.wayland.textinput` (`QWaylandTextInputv3::disableSurface`) as keyboard focus moves between axiom's surfaces. Seen live on sway and niri (2026-10-17), never under Hyprland; typing still works. Likely Qt's text-input-v3 handling with several layer surfaces taking focus.
- **Size:** small
- **Found:** 2026-10-16, while consolidating compositor settings

### Floating bars sit flush on the border without a backend
- **Where:** `config/BarsConfig.qml` (`enrichBarConfig`: `floatGap`), `services/compositor/CompositorManager.qml` (`gapsOut`)
- **What:** A floating bar's automatic gap (`floatGap` -1) is the compositor's outer gaps (`CompositorManager.gapsOut`). With no backend (an unknown compositor) `gapsOut` is all 0, so a floating bar sits flush against the border. Sway's and niri's backends read their gaps from the config (`SwayState.configInfo`, `axiom compositor niri info`); decide what the gap is with no backend at all (a fixed default, or `Appearance.screenMargin`).
- **Size:** small
- **Found:** 2026-10-16, while testing layer order in nested sway

### niri reports no space reserved by bars, nor where tiled windows are
- **Where:** `components/methods/NiriState.qml` (`outputs`, `windows`)
- **What:** niri's IPC gives no layer surface geometry and, in 26.04, no position for a tiled window (`tile_pos_in_workspace_view` is null; only floating windows have one). So an output's `reserved` is 0 (the dock centres on the whole screen, not its work area), and tiled windows are laid out from their column and place in it from the output's edge, without niri's scroll (`windowGeometry` stays off: no screenshot window mode; the dock hides behind a window's `cover`, its column or the whole output, which ignores struts, reserved space and `center-focused-column`).
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

### niri's flags can't be turned off from axiom
- **Where:** `backend/internal/compositor/render/niri.go` (`niriArgs`), `config/schema/` (`x-compositor.niri.value: flag`)
- **What:** A niri flag (`tap`, `natural-scroll`, `numlock`, `focus-follows-mouse`) is on by being there and has no `false`; axiom writes one on and leaves it out off. Off in axiom while the user's own config has it on, it stays on.
- **Size:** small
- **Found:** 2026-10-17, while adding the niri backend

### Nested niri freezes while its window is hidden
- **Where:** `scripts/dev/nested.sh` (niri)
- **What:** niri's nested (winit) backend stops its event loop while its window isn't shown on the host (another workspace): its IPC times out and the axiom inside it hangs waiting on it, so an `axiom ipc` call never returns. Keep the nested window visible while testing; it carries on once shown again.
- **Size:** trivial
- **Found:** 2026-10-17, while testing the niri backend

### Two exclusive-focus surfaces at once without a native grab
- **Where:** `services/compositor/FocusGrab.qml` (`exclusive`), `components/hosts/overlay/OverlayPanel.qml`, `components/hosts/popout/BarPopouts.qml`, `components/hosts/popout/EdgePopout.qml`
- **What:** Without `supports.focusGrab`, every active grab's surface asks for `WlrKeyboardFocus.Exclusive`. With the overlay open (exclusive the whole time) and a popout with a text field opened over it, two surfaces on the Overlay layer ask for exclusive focus. Which one gets the keyboard is up to the compositor. On niri the older one keeps it (found fixing the polkit prompt, c49b429, which now turns `exclusive` off while `SurfaceManager.modalShown`), so there typing into a popout over the overlay goes to the overlay. Sway is unchecked (`scripts/dev/nested.sh sway`). A fix in the same spirit: only the newest active grab is `exclusive`.
- **Size:** small
- **Found:** 2026-10-16, while auditing the layer-placement branch

### Missing app icons warn in the log
- **Where:** `services/ui/LauncherManager.qml` (`Quickshell.iconPath`), `services/ui/DockManager.qml`
- **What:** An app whose `.desktop` icon isn't in the icon theme (here `xdg-desktop-portal-gtk`'s `applications-system-symbolic`) logs `Could not load icon` at each size it's drawn, though the fallback icon shows. Noise in `scripts/log.sh`; either skip hidden/`NoDisplay` entries or resolve the name before handing it to an Image.
- **Size:** trivial
- **Found:** 2026-10-16, while auditing the layer-placement branch

### Text input warnings when the desktop takes the keyboard
- **Where:** `components/surfaces/desktop/DesktopWindow.qml` (`WlrLayershell.keyboardFocus`)
- **What:** With a typing module (Notes) on the desktop, clicking into it and back to windows logs bursts of `Trying to disable` from `qt.qpa.wayland.textinput` (`QWaylandTextInputv3::disableSurface`; 174 in one session). Typing and handing focus back work. Likely Qt's text-input-v3 noise when focus moves between surfaces; not yet checked whether an edge menu's Notes logs the same.
- **Size:** small
- **Found:** 2026-10-14, while letting typing modules go on the desktop

### Singleton properties warn on every reload
- **Where:** `services/ui/BlurManager.qml` (`paused`), `services/core/SelfUpdateManager.qml`, `services/compositor/HyprlandManager.qml` (`activeWindowId`), `services/system/AudioManager.qml` (`tracker`, `captureTracker`, `micInUse`)
- **What:** Every config reload logs `Unable to assign [undefined] to bool` at the `paused` declaration (and, seen 2026-10-14, at `UpdatesManager.checking` while it was a readonly bool on a singleton (now a plain one): likely the same cause; seen 2026-10-16 as `Unable to assign [undefined] to QString` at `HyprlandManager.activeWindowId`, a readonly string; seen 2026-10-26 as `Unable to assign [undefined] to QList<QObject*>` at `AudioManager`'s two `PwObjectTracker.objects` and `Unable to assign [undefined] to bool` at its `micInUse`, after a reload from saving an unrelated file). The binding itself evaluates to a boolean (a temporary probe logged `boolean false`), and a constant `paused: false` still warned, so it isn't the expression: something in Quickshell's reload of this singleton assigns it. Harmless (the value is right afterwards), but it's noise in every `scripts/log.sh`. Next step: check whether Quickshell carries readonly properties across a reload, or whether making `paused` a plain function helps.
- **Size:** small
- **Found:** 2026-10-13, while checking reload logs during the docs makeover

### Readers read files through a service
- **Where:** `config/Paths.qml` (`packagedVersion`), `config/I18n.qml`
- **What:** Readers read only the data owners and each other (AGENTS.md › Layering), but `Paths.packagedVersion` calls `FileManager.read`, and `I18n` reads with both `FileManager.read` and a FileView of its own. Either the rule names `FileManager` as allowed in readers, or the reads move to a data owner.
- **Size:** small
- **Found:** 2026-10-26, while reviewing the repository's organization

### The check order is kept in three places
- **Where:** `scripts/check_all.sh`, `scripts/dev/verify.sh`, `.github/workflows/checks.yml`
- **What:** The same checks, in the same order, are listed by hand three times; a check added to one can be missed in the others. One list (a file the three read, or `check_all.sh` as the one CI runs) keeps them equal.
- **Size:** small
- **Found:** 2026-10-26, while reviewing the repository's organization

### Small tooling leftovers
- **Where:** `components/methods/IconResolver.qml`, `packaging/aur/`, `docs/dev/core/i18n.md`
- **What:** `IconResolver` is the one methods helper without a test (`tst_IconResolver`) (and the one importing `Quickshell`, for `iconPath`). The `axiom-shell` and `axiom-shell-git` PKGBUILDs are near copies. `check_doc_drift.py` flags `i18n.md` (12 commits behind its files, after the services moved to folders).
- **Size:** trivial
- **Found:** 2026-10-26, while reviewing the repository's organization

### Overlay and popouts close or break each other
- **Where:** `services/ui/ShellManager.qml` (`closeOverlay`), `services/ui/OverlayManager.qml`, `components/hosts/popout/BarPopouts.qml`, `components/hosts/overlay/OverlayPanel.qml` (its `FocusGrab`)
- **What:** From the maintainer's notes, verbatim: "a little bit of a system re-work/look to ensure all popouts are usable as expected while the overlay is open, without closing the overlay. There are a bit more problems here so this likely needs a plan (i.e. currently open popouts break when overlay is opened, nothing should close the overlay (i.e. after installing greetd and the polkit prompt closes, the overlay closes) The one exception is likely launcher (although it can also just open over the overlay and be usable)". The plan covers which surfaces may close the overlay (callers of `ShellManager.closeOverlay`, focus grabs ending when a prompt like polkit's takes and gives back focus), and how a popout open before the overlay keeps working.
- **Size:** needs a plan
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The window switcher's blur and release on sway and niri
- **Where:** `services/compositor/WindowSwitcherManager.qml` (`commit`, `pick`), `components/surfaces/switcher/SwitcherKeys.qml`, `components/surfaces/switcher/SwitcherStrip.qml`
- **What:** From the maintainer's notes: the switcher's blur background is broken, and releasing the modifier doesn't always switch to the picked window on compositors other than Hyprland (sway's binds report steps only, and `SwitcherKeys` has to see the release). It "should work the same on niri since it just shows windows". The plan settles one release path that works on every compositor and the switcher's backing.
- **Size:** needs a plan
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Setting names that still confuse
- **Where:** `config/schema/sections/`
- **What:** From the maintainer's notes: "still confusing option names in settings" (after the look-and-feel renames). The plan lists the settings whose titles or keys read wrong, with a proposed name for each, for the maintainer to decide; a renamed key is a migration step.
- **Size:** needs a plan
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### A note's view jumps while typing and forgets its place
- **Where:** `components/content/parts/notes/NoteEditor.qml` (`ensureVisible`, `_flick`), `components/content/parts/notes/NoteBlock.qml`
- **What:** From the maintainer's notes: a newline (and other edits that rebuild blocks) jumps the view around, so you lose where you were; and reopening a note scrolls back to the top (`_flick.contentY = 0`) instead of where you left it.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The bar editor lost its links to the global bar style
- **Where:** `components/views/BarEditor/BarsPanel.qml`, `components/views/BarEditor/WidgetInspector.qml`
- **What:** From the maintainer's notes: the bar editor used to link to the Look and feel settings that style every bar; those links are gone, and it needs a link to the global bar style.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The layouts editor says a page is shrunk to 99% at the defaults
- **Where:** `components/views/Layouts/PageTarget.qml` (`Shrunk to {0}% on {1}`)
- **What:** From the maintainer's notes: with every scale at its default 100 %, the layouts editor still shows a page as shrunk to 99 %: a fit a hair under 1 is reported as shrinking.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The monitor editor shows changes nobody made
- **Where:** `services/compositor/MonitorManager.qml` (`draft`, `ensureLoaded`), `components/views/Monitors/Monitors.qml`
- **What:** From the maintainer's notes: the monitors page shows unsaved changes when nothing was changed (likely a value the draft normalises on load differing from the saved one).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Updating the greeter closes the overlay and shows no progress
- **Where:** `services/session/GreeterManager.qml` (`update`, `_elevate`, `_notifyOutdated`)
- **What:** From the maintainer's notes: a greeter update needs an indicator while it runs and must not close the overlay; its login screen update notification doesn't go away after the update ("check all notifs for this": every notification that announces something to do should clear once it's done).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Notifications have no blur backing and an invisible border
- **Where:** `components/surfaces/notifications/NotificationToast.qml` (`BoxBlurRegion`, `borderColor`)
- **What:** From the maintainer's notes: a notification gets no blur backing (always, or likely only the first after launch; on sway too), and its border is `Theme.backgroundAlt`, the background's colour, so its edge can't be seen: it wants a foreground colour.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Typing in modules on the overlay and the desktop
- **Where:** `components/hosts/overlay/OverlayPanel.qml` (`keyboardFocus`), `components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`, `wantsKeyboard`)
- **What:** From the maintainer's notes: modules that take typing can't be used while they're on the overlay, and a click outside a desktop module stops its typing.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Warning triangles say nothing on hover
- **Where:** `components/views/Keybinds/BindListRow.qml`, `components/reusable/IssueList.qml`
- **What:** From the maintainer's notes: anywhere the shell shows a yellow warning triangle (a niri bind set while on Hyprland, …) it should be hoverable, with a tooltip saying what's wrong.
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
- **What:** From the maintainer's notes: under niri, Shift+Enter on an emoji in the launcher doesn't type it into the focused window (typing goes through `input.type` on the daemon's virtual keyboard).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### A window takes the keyboard from a desktop module on niri
- **Where:** `components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`), `services/ui/DesktopManager.qml`
- **What:** From the maintainer's notes: under niri, as soon as the mouse leaves a desktop module that takes typing, the window under the pointer takes the keyboard focus (niri's focus follows the mouse onto it), so typing in the module stops. How to hold the focus there is still open ("idk how to handle this").
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Hyprland's default workspace doesn't highlight its first window
- **Where:** `components/bar/widgets/Workspaces/StripWindows.qml` (`focused`), `services/compositor/HyprlandManager.qml`
- **What:** From the maintainer's notes: on the workspace Hyprland starts on, the first window opened isn't highlighted as focused until a workspace move.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap
