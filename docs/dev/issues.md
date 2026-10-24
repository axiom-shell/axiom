# Known issues

> **Files:** this file only
> **Config:** none
> **Related:** [Developer docs](README.md), [testing](testing.md)

Problems found while working on something else: not fixed yet, but recorded so they aren't lost. **Add an entry whenever you find a problem outside the task at hand** rather than fixing it unasked or only mentioning it. Remove the entry in the change that fixes it. Before starting work in an area, check here for what's already known about it. This is a working list for coding agents and the maintainer, meant to move to GitHub over time: it's not where to report or look up problems, which is [GitHub issues](https://github.com/axiom-shell/axiom/issues). Agents never open a GitHub issue themselves; the maintainer moves an entry there.

Each entry is a `###` heading plus these four bullets, in this order (`scripts/check_docs.py` checks the shape and that cited paths and members exist):

```
### <Short title>
- **Where:** `path/File.qml` (symbol, or several paths)
- **What:** what's wrong and the evidence (log line, grep count, failing case); quote a log warning's message in backticks so verify.sh marks it known (one from Qt or Quickshell that names no file: quote its category too, `quickshell.I3.ipc`)
- **Size:** trivial | small | needs a plan
- **Found:** YYYY-MM-DD, while <task>
```

## Open

### A greeter clock set to another time zone shows the system's time
- **Where:** `services/TimeZoneManager.qml` (`offsetOf`), `components/content/Clock/Clock.qml`
- **What:** Zone offsets come from the axiom daemon (`tz.offsets`), and no daemon runs in the greeter (`BackendManager` stays inactive), so a Clock module on the login screen with a `timezone` shows the system's local time. The greeter could get offsets from `axiom greeter` (a small socket of its own, or the bundle carrying them), or the greeter host could hide the setting.
- **Size:** small
- **Found:** 2026-10-24, while moving TimeZoneManager to the daemon

### Leaving managed, the runtime layer can go on before the given-back config reloads
- **Where:** `backend/internal/compositor/manager/manager.go` (`SetInputs`, `liveChanged`, `apply`)
- **What:** The shell's first inputs arm both `debounce` and `liveDebounce` (300 ms each). When the live one fires first, `liveChanged` sees `AppliedMode != mode` and calls `apply`, which releases the managed config and asks for a reload; the layer debounce's `apply` then runs `runtimeApply` before that reload lands, so the runtime layer reads the managed config's binds (every axiom key looks taken, each logged once) and goes on over it. It's corrected after the reload (`configReloaded` applies again). Holding `runtimeApply` until `configReloaded` after a release that reloads would close it, but a missed reload event would then leave no runtime layer.
- **Size:** small
- **Found:** 2026-10-24, while reviewing the Go backend branch

### `axiom lock` fails with no screen connected
- **Where:** `services/LockManager.qml` (`_report`), `backend/internal/lock/lock.go` (`State.confirmed`)
- **What:** `_report` sends `surfaces` and `outputs` from the same number (`Quickshell.screens.length`), so the daemon's `Surfaces >= Outputs` check can never catch a screen without a lock surface, and with no screen connected `confirmed()` needs `Surfaces > 0`, so `axiom lock` reports a failure. Locking should lock the session with no screens connected, and a screen connected while locked should get the lock surface; the shell should report the surfaces it actually built, and the daemon confirm on the session lock with zero outputs.
- **Size:** small
- **Found:** 2026-10-24, while reviewing the Go backend branch

### The shell's socket warns when the daemon re-execs
- **Where:** `services/BackendManager.qml` (its `Socket`)
- **What:** Every daemon re-exec (each dev-mode rebuild) logs `quickshell.io.socket` `QLocalSocket::PeerClosedError` (a `Socket error for Socket(0x…)`) once: the old image closing the connection reaches the shell as an error, though `BackendManager` reconnects and it's expected. Five in one session's log (`scripts/log.sh --all -g PeerClosed`). Quieting it means telling a close the daemon announced (re-exec, quit) from a real failure, maybe with a notification before the exec.
- **Size:** small
- **Found:** 2026-10-24, while moving the compositor takeover into the binary

### backend.json points at a protocol doc that doesn't exist
- **Where:** `config/json/backend.json` (`_comment`)
- **What:** The comment says "see docs/dev/backend/protocol.md", which was never written: what counts as a protocol change (and that push topics and new methods don't need one) is only in `docs/dev/backend/README.md`. Writing the page, or pointing the comment at the README, fixes it.
- **Size:** small
- **Found:** 2026-10-24, while auditing the Go backend

### Some backend security checks have no tests
- **Where:** `backend/internal/fsx/` (`Adopt`), `backend/internal/rpc/server.go` (`Listen`), `backend/internal/cli/greeter.go` (`greeterEnv`), `backend/internal/daemon/reexec.go` (`adopt`)
- **What:** `backend/AGENTS.md` asks that every security check has a test. The daemon's (`daemon_test.go`: the handoff's parsing, the lockscreen refusal, the shell-peer check, `writable`) are covered; still untested: the stale socket removed only under the instance lock, `fsx.Adopt` refusing a wrong inode or an unheld lock (only its close-on-exec part is tested), the socket's 0600, an adopted handoff end to end, and the greeter's environment.
- **Size:** small
- **Found:** 2026-10-24, while reviewing the Go backend

### The greeter's environment is a denylist
- **Where:** `backend/internal/cli/greeter.go` (`greeterDropped`, `greeterEnv`)
- **What:** The greeter drops four named `AXIOM_*` variables, so others (`AXIOM_BIN`, `AXIOM_REEXEC`, `AXIOM_TREE`) inherited by `axiom greeter` reach it. `supervise` strips every inherited `AXIOM_*` and sets its own: the greeter should do the same.
- **Size:** trivial
- **Found:** 2026-10-24, while reviewing the Go backend

### Small backend error and robustness gaps
- **Where:** `backend/internal/fsx/fsx.go` (`WriteFile`), `backend/internal/logfile/`, `backend/internal/ipcroute/ipcroute.go` (`exec`), `backend/internal/wayland/wire/wire.go` (`Globals`), `backend/internal/cli/cli.go` (`Main`), `backend/internal/config/format.go`, `backend/internal/saved/saved.go` (`Import`)
- **What:** Raw errors reach the CLI as `Internal`: `fsx.WriteFile` (`fmt.Errorf`), `logfile.Open`, `daemon logs`' `ReadFile`. `ipcroute`'s exec path labels a timeout `NotFound` (should be `Unavailable`). `wire.Globals` slices `body[4:]`/`body[8:]` without checking a short message's length. `cli.Main` doesn't catch SIGHUP: closing the terminal kills a `--dev` daemon outright, leaving its shell for the next start to stop. `format: 1` is refused with "it reads 1 and 2", and `format: null` prints `<nil>`. The keys a format-1 load drops (`Removed`) are never logged. `saved.Import` reads the file twice, so the preview and what's applied can differ.
- **Size:** small
- **Found:** 2026-10-24, while reviewing the Go backend

### Schema build gaps
- **Where:** `backend/internal/schema/yamlsrc/kinds.go` (`orderKeys`), `backend/internal/cli/schema.go` (`schema check`), `backend/internal/config/pipeline.go` (patterns)
- **What:** `orderKeys` overwrites an author-written `x-order` on every object with more than one property, though `config/schema/annotations.yaml` lets authors write one. `axiom schema check` passes when `config/json/config.schema.json` is missing. Go's RE2 `\S`/`\s` are ASCII-only while JS's are Unicode: a value of only U+00A0 passes `"\\S"` in Go and fails in JS. Translating the classes, or refusing them in `check.go`, keeps the two sides equal.
- **Size:** small
- **Found:** 2026-10-24, while reviewing the Go backend

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

### An edge menu can be bigger than its screen
- **Where:** `services/EdgeMenuManager.qml` (`cardUnitOf`), `components/methods/GridPlacement.qml` (`menuPlacement`)
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

### An outside edit of config.json can release a managed compositor config
- **Where:** `services/CompositorConfigManager.qml` (`apply`, `_leave`), `services/ConfigManager.qml` (its file-watch reload)
- **What:** Takeover settings (`x-takeover`) are kept from changing only by `SavedConfigsManager`'s load and import. Writing `config.json` from outside while axiom runs, without `Compositor.mode` or with another mode, reloads it; `apply()` takes that as a switch away from managed and releases the compositor's config (`writer.release()`). Seen 2026-10-20: a saved example copied over `config.json` gave `hyprland.lua` back. A hand edit, a sync tool or a restored backup would do the same. A possible guard: hold every `x-takeover` value on a plain file reload, and change one only through its own card.
- **Size:** small
- **Found:** 2026-10-20, while testing popout fixes on saved configs

### Surfaces touch a dead screen after the outputs go away
- **Where:** `config/General.qml` (`outputs`: whatever is built on it while no monitor is connected)
- **What:** After the monitors drop out (`qt.qpa.wayland` `There are no outputs - creating placeholder screen`, e.g. DPMS off), the log fills with `attempted to use dangling screen object` (68 lines in one session, no file named). Something holds a `ShellScreen` past its removal and reads it. Which surface it is hasn't been found yet: next step, reproduce with a nested compositor dropping its output and bisect by commenting out surfaces in `shell.qml`.
- **Size:** needs a plan
- **Found:** 2026-10-20, while reviewing the popouts system

### ChatProvidersCard runs its own requests
- **Where:** `components/views/Settings/ChatProvidersCard.qml` (Test, Fetch models)
- **What:** The card creates its own `ChatRequest` for Test and Fetch models, so a UI file owns a process, against the rule that services own every side effect (AGENTS.md › Services). Kept as a known exception; moving the requests into `ChatManager` would end it.
- **Size:** small
- **Found:** 2026-10-20, while tightening AGENTS.md (it was listed there under Known housekeeping)

### The community setups' check doesn't take monitor places yet
- **Where:** `services/SavedConfigsManager.qml` (`exportConfig`'s `places`), `components/views/Settings/CommunitySetupsCard.qml` (Export and submit), `backend/internal/share/share.go` (`Pick`'s `monitors`)
- **What:** An export names each per-monitor part's monitor (`x-monitorRef`: a bar's, dock's, OSD's, edge menu's, strip's, a monitor's own desktop) by its place (`#2`, `@primary`, `*`), so a multi-monitor setup lands on the importer's monitors. Those fields are `machine` scope, and the community-setups repo's CI admits only `look` keys (a walk mirroring `share.Pick`), so it would refuse such a file: Export and submit leaves the places out (`exportConfig(false, false, false)`), and a shared setup's second-monitor bar still lands on the importer's bar by position. Its CI needs to admit an `x-monitorRef` field holding a place, and then the card can export with them.
- **Size:** small
- **Found:** 2026-10-20, while aligning the schema's scopes

### The scrolling layout's workspaces don't come back with their monitor
- **Where:** `services/HyprlandManager.qml` (`dynamicByLayout`, `_compaction`), `components/methods/DynamicWorkspaces.qml`
- **What:** niri keeps an unplugged monitor's workspaces and gives them back when it returns; under Hyprland's scrolling layout, Hyprland moves them to another monitor, where they're outside its block, so they drop out of its list (`DynamicWorkspaces.workspaces`) until `workspaces reconcile`. Workspaces the user's config makes persistent stay empty in the middle of the list, as compaction moves no workspace without windows. Neither is tried yet.
- **Size:** needs a plan
- **Found:** 2026-10-19, while adding the scrolling layout

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


### A fullscreen window on one screen pauses the blur on every screen
- **Where:** `services/BlurManager.qml` (`paused`)
- **What:** `paused` is on while any screen shows a fullscreen window, because Hyprland's layer rules apply to every monitor. On niri the blur is each window's own region (`supports.blurRegion`), so it could pause per screen. Instead, on two monitors with a fullscreen video on one, the other loses its blur, though its surfaces stay translucent (`fillOn` is per screen). A per-screen pause where `supports.blurRegion` would fix it (`regions`/`backdropRegions` per screen).
- **Size:** small
- **Found:** 2026-10-19, while reviewing niri's blur

### A hot reload while locked leaves niri's red screen
- **Where:** `services/LockManager.qml` (its `PersistentProperties` locked state), `components/surfaces/lockscreen/LockSurface.qml`
- **What:** A QML reload while the session is locked destroys the lock object: `Session lock object was destroyed without unlocking. The session will stay locked in case this was accidental.` The locked state is kept, so the new generation should lock again, but on niri (2026-10-18) the screen stayed niri's red locked background with no way out, and only restarting niri got the session back. Saving any loaded file while the idle locker has locked the screen does it. Check whether the new generation's `WlSessionLock` takes over the old lock on niri (and on sway/Hyprland), or have the lock object survive a reload.
- **Size:** small
- **Found:** 2026-10-18, while adding niri's blur (an edit hot-reloaded while the screen was idle-locked)


### Quickshell's wlr screencopy crashes the shell on niri
- **Where:** `services/ScreenshotManager.qml` (`grimFrames`, the workaround), `components/surfaces/screenshot/ScreenshotPickerWindow.qml` (its `ScreencopyView`); the bug is Quickshell's
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

### CommandOutput's figure text loops on its size
- **Where:** `components/content/CommandOutput/CommandOutput.qml` (the text `StyledText`, `id: body`)
- **What:** The log shows `Binding loop detected for property "textSize"` while a Command output card is on a shown page: in statement mode `body`'s `textSize` comes from `body.height / 5`, and a `Layout.fillHeight` text's height follows its implicit height, which follows the size.
- **Size:** small
- **Found:** 2026-10-18, while adding the todo list and pomodoro timer

### The greeter on sway can't use a cursor theme's companion
- **Where:** `services/GreetdManager.qml` (`_applyCompositor`), `services/CursorThemeManager.qml`
- **What:** On sway the greeter sets `seat * xcursor_theme` to the theme's own name: the `axiom-cursor-<theme>` companion a theme like Oxygen needs for the standard cursor names lives in the user's `$XDG_DATA_HOME/icons`, which greetd's user can't read. Such a theme shows the default theme's arrow at the login screen. Copying the companion into the bundle (as the wallpapers are) and pointing the greeter's `XCURSOR_PATH` at it would fix it.
- **Size:** small
- **Found:** 2026-10-18, while moving the greeter to sway

### install.sh still installs the rest of a feature whose COPR was declined
- **Where:** `install.sh` (the declined-COPR loop after the COPR prompts)
- **What:** Declining a COPR on Fedora marks each feature with a package from it as skipped, but drops only that COPR's packages: the feature's other packages stay in the one `dnf install`. Declining `nett00n/hyprland` while setting up niri skips the login screen's feature yet still installs `greetd`. Rebuilding `packages` from the features left (and the required keys) after the prompts would fix it; test with `--dry-run` in a `fedora:latest` container.
- **Size:** small
- **Found:** 2026-10-17, while reviewing the distro-support branch for merge

### The window shadow's offset is always 0 but still passed through every writer
- **Where:** `services/CompositorConfigManager.qml` (`spec`: `"offset": 0`), `components/methods/CompositorLayer.qml` (`look`), `components/methods/HyprLua.qml`, `components/methods/SwayConf.qml`, `components/methods/NiriConf.qml`
- **What:** Since config v66 axiom's shadow only spreads evenly, so the spec's shadow `offset` is a constant 0 that `look()` hands on and each writer writes (`decoration.shadow.offset`, `shadow_offset`, niri's `offset`). Writing 0 still matters (it resets a user's own offset), so each writer could write 0 itself and the field go from the spec and its tests.
- **Size:** small
- **Found:** 2026-10-17, while reviewing the shadow-on-or-off change

### A niri module refused in detached mode is only logged
- **Where:** `backend/internal/compositor/manager/niri.go` (`runtimeApply`), `services/CompositorConfigManager.qml` (`problem`)
- **What:** In the file modes a module `niri validate` refuses sets `CompositorConfigManager.problem` (the Compositor card shows it). The detached mode's module (also the file modes' fallback) is checked the same way, but a refusal is only a `compositor: niri refuses the config axiom made` warning in the daemon's log in the log: the card says nothing, and niri keeps the module before. A raw bind niri refuses is the likely cause.
- **Size:** small
- **Found:** 2026-10-17, while auditing the niri branch for merge

### SwayFX remaps the chrome on a fresh qs start
- **Where:** `services/SwayManager.qml` (`surfacesReady`), `shell/BlurBacking.qml`
- **What:** `surfacesReady` is always true, so bars, border and docks map at once, while the held blur window (order 9) and the shadow window beside it (`axiom-shadows`, order 8) wait for `supports.blur`, known only from the `get_version` reply. Mapped after them, they make LayerManager map each lower-ordered window again. Hot reloads keep the variant, so only a fresh start does it. Waiting for `ready` would fix it, but hides the chrome until sway answers.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### The blur window's Top/Overlay switch may land over the bars on SwayFX
- **Where:** `shell/BlurBacking.qml`, `shell/BlurBackingWindow.qml`
- **What:** The blur window changes `stackLayer` while a fullscreen window shows; LayerManager keeps its place in the order. If SwayFX puts a window that changed layer on top of its new layer, then after fullscreen ends it draws over the bars. Needs a look in `scripts/dev/nested.sh sway` with SwayFX.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### A fullscreen window re-sends the whole live layer
- **Where:** `services/CompositorConfigManager.qml` (`_liveInputs`)
- **What:** `BlurManager.active` flips as a fullscreen window opens or closes and is in `_liveInputs`, so each flip re-sends the whole look and input (Hyprland's `hl.config({ input = … })`, sway's `[all] border pixel`, `gaps … all set`), not just the blur rules: a user's runtime tweak (`border toggle`, `gaps current plus`) is undone whenever anything goes fullscreen. A blur-only change should send only the blur lines.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### Any change of the mode to managed approves the takeover
- **Where:** `services/CompositorConfigManager.qml` (`onModeChanged`)
- **What:** Picking managed while axiom runs counts as approval, which includes editing config.json by hand or a sync tool writing it, not only the card's Save that `docs/dev/compositor/config-modes.md` describes. Imports keep `x-takeover`, so only direct edits reach it. Approving from SettingsManager's save only, or saying so in the doc.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### Unreadable sway config means axiom binds over the user's keys
- **Where:** `backend/internal/compositor/manager/runtime.go` (`_start`)
- **What:** When `axiom compositor sway-text` fails (it logs `Can't read your sway config`) the layer treats the user as binding nothing, and binds with `--no-warn` over their keys after every reload. Hyprland's layer does the same. Binding nothing (look and input only) with a problem shown would be safer, at the cost of axiom's binds.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### The takeover makes only some of sway's relative includes absolute
- **Where:** `backend/internal/compositor/takeover/kinds.go` (`sway`'s `absInclude`)
- **What:** Adopting a sway config makes its relative includes absolute (it moves to `user/`), but only an unquoted first path: a quoted relative include, and all but the first path of a multi-path `include`, stay relative and then resolve from `user/`. (The unchecked edit and the unescaped dir in the old script's sed went with the Go port.)
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### Turning sway's window opacity off reloads sway
- **Where:** `services/CompositorConfigManager.qml` (`_appliedParts`)
- **What:** Opacity counts as an applied part, so turning it off reloads the config (see "Changing a setting under sway can flash the screen"), though SwayManager already sets every window back to 1 itself. A part the backend takes back itself shouldn't count.
- **Size:** trivial
- **Found:** 2026-10-16, while auditing the sway branch for merge

### The onboarding's Compositor page names Hyprland
- **Where:** `components/surfaces/onboarding/pages/CompositorPage.qml`, `services/OnboardingManager.qml` (`detectCompositor`)
- **What:** It gates on `CompositorManager.kind !== "hyprland"` and reads `HyprlandManager.withVersion` (and the page shows Hyprland's legacy notice) rather than a capability, and calls `CompositorManager.backend?.unsupportedHint` from UI. A writer hook (`legacyConfig`, `configProblem`) and a CompositorManager passthrough would keep it neutral.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch for merge

### SwayFX's corner radius reaches only windows opened later
- **Where:** `components/methods/SwayConf.qml` (`fxLines`)
- **What:** `corner_radius` sent at runtime sets SwayFX 0.6's global only (its per-window reset runs only while the config loads), and it has no per-window command, so a changed rounding shows on new windows while open ones keep theirs until sway reloads its config. A fix would need a reload, which takes back the rest of the runtime look.
- **Size:** small
- **Found:** 2026-10-16, while fixing SwayFX's blur on unfocused windows

### Changing a setting under sway can flash the screen
- **Where:** `services/LayerManager.qml` (`_sequence`), `components/hosts/popout/LayerSlot.qml`, `services/MonitorManager.qml`
- **What:** Reported on sway: changing a setting flashes the whole settings page. Two causes fixed: the border's shadow window wasn't held, so turning the shadow on remapped every surface ordered under it (`LayerManager: mapping … again, in its place` for the backdrop, bars, border and dock, the backdrop dimming the overlay flashing with them), and a sway reload (any save rewriting axiom's file) reset the outputs to the config's, dropping the monitor profile. A third, on any compositor: the settings page rebuilt every card on each edit (its categories were recomputed from the config through `x-showIf`), fixed in `components/views/Settings/Settings.qml`. Not reproduced with an ordinary setting since (a save then logs no remap and no overlay resize). Without `layerOrder`, a bar remade by a change of kind still remaps everything after it, by design. If it still happens, note which setting and look for those log lines.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch

### Sway's special workspaces are floating scratchpad windows
- **Where:** `services/SwayManager.qml` (`toggleSpecial`, `moveToSpecial`), `components/methods/SwayState.qml` (`specialToggle`)
- **What:** Hyprland's special workspace is a tiled workspace drawn over the current one; sway has none, so a special group is marked scratchpad windows, and sway's scratchpad makes every window floating, centred and stacked on the others (a group of three shows as three overlapping windows). Options: keep the scratchpad and lay the group's windows out in a grid on show (`move position` / `resize set` per window, over the workspace like Hyprland's), or a hidden named workspace per group (tiles, but replaces the view instead of overlaying it). A group name holding `,` or `;` also breaks its `nop axiom special` bind (sway splits the command there).
- **Size:** needs a plan
- **Found:** 2026-10-16, while auditing the sway branch

### Overview drops on sway nest split containers
- **Where:** `services/SwayManager.qml` (`placeWindow`)
- **What:** A drop next to a window runs `split h|v` on the target every time, which wraps it in a new container even when its parent already splits that way, so repeated drops nest containers sway then draws as such (tabbed/stacked parents behave oddly). Split only when the parent's layout differs (the tree has it).
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch

### Detached sway keeps the floating modifier after the mouse binds go
- **Where:** `backend/internal/compositor/manager/sway.go`, `components/methods/SwayConf.qml` (`unbindLines`, `floatingModifier`)
- **What:** The runtime layer sends `floating_modifier` for the drag/resize binds but its unbind commands don't take it back, so removing them in detached mode leaves sway's floating modifier set until sway reloads. It also overrides a `floating_modifier` of the user's own config, which `render.RuntimeBinds` doesn't see as a taken key.
- **Size:** small
- **Found:** 2026-10-16, while auditing the sway branch

### `noWarps` off maps to sway's `mouse_warping output`
- **Where:** `config/schema/sections/WindowBehaviour.yaml` (`noWarps`, `x-compositor.sway.map`)
- **What:** Hyprland with `cursor.no_warps` off moves the cursor to a window focused by keybind; sway's `mouse_warping output` only moves it when focus changes output (`container` would match Hyprland). Decide which sway value matches what the setting promises.
- **Size:** trivial
- **Found:** 2026-10-16, while auditing the sway branch

### Quickshell's I3 socket warns on every reload
- **Where:** `services/SwayManager.qml` (Quickshell.I3)
- **What:** Under sway every reload of the shell logs `I3 event socket disconnected` twice (category `quickshell.I3.ipc`), from the old generation's sockets closing. Events still arrive afterwards (checked in nested sway). Quickshell's, not axiom's; nothing to fix here unless it starts dropping events.
- **Size:** trivial
- **Found:** 2026-10-16, while writing the sway backend

### Qt text-input warnings under sway and niri
- **Where:** `components/reusable/StyledTextEntry.qml` (the text fields; Qt's own wayland text-input)
- **What:** Under sway and niri the log fills with `Trying to disable` / `Trying to enable` warnings from `qt.qpa.wayland.textinput` (`QWaylandTextInputv3::disableSurface`) as keyboard focus moves between axiom's surfaces. Seen live on sway and niri (2026-10-17), never under Hyprland; typing still works. Likely Qt's text-input-v3 handling with several layer surfaces taking focus.
- **Size:** small
- **Found:** 2026-10-16, while consolidating compositor settings

### Floating bars sit flush on the border without a backend
- **Where:** `config/Bar.qml` (`enrichBarConfig`: `floatGap`), `services/CompositorManager.qml` (`gapsOut`)
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
- **What:** On a left or right edge a submenu always opens away from that edge (`openToLeft` is `edge === Bar.Right`), so a floating menu on the right edge opens every submenu to its left, across the menu's own content side. The maintainer finds that unexpected for a right-edge menu: which way it should open there (and whether by the box's place on screen, as top and bottom edges do) needs deciding. Seen with a `Submenu` module in a right-edge floating menu in nested niri.
- **Size:** small
- **Found:** 2026-10-18, while checking shadow seams on side-edge menus

### A pill bar's end reach trails a sliding popout's wall
- **Where:** `components/hosts/popout/PillBarJoin.qml`, `components/hosts/popout/EdgePlacement.qml` (`_slideLead`), `components/bar/BarContainer.qml` (`_endReach`)
- **What:** Seen on niri with a solid bottom bar (border off) whose SystemStats popout joins the left pill bar: while the popout slides in or out, the left bar's end pill, run on to the popout's top wall, trails it by about 8px for two or three frames (below the wall while opening, above it while closing), so the two strokes and their shadows step at the left bar's inner edge. At rest they line up. Probably the other bar's window committing a frame or so after the popout's (as `AttachedSurface`'s fillet opening is taken a stroke ahead for). The end pill leads the wall by a stroke there (niri has no `supports.layerFrameSync`, `EdgePlacement._slideLead`), which helps but doesn't close the gap; sway and Hyprland move the two as one without it.
- **Size:** small
- **Found:** 2026-10-18, while fixing shadow seams where a wall runs on into another surface

### niri's flags can't be turned off from axiom
- **Where:** `components/methods/NiriConf.qml` (`_niriArgs`), `config/schema/` (`x-compositor.niri.value: flag`)
- **What:** A niri flag (`tap`, `natural-scroll`, `numlock`, `focus-follows-mouse`) is on by being there and has no `false`; axiom writes one on and leaves it out off. Off in axiom while the user's own config has it on, it stays on.
- **Size:** small
- **Found:** 2026-10-17, while adding the niri backend

### Nested niri freezes while its window is hidden
- **Where:** `scripts/dev/nested.sh` (niri)
- **What:** niri's nested (winit) backend stops its event loop while its window isn't shown on the host (another workspace): its IPC times out and the axiom inside it hangs waiting on it, so a `qs ipc` call never returns. Keep the nested window visible while testing; it carries on once shown again.
- **Size:** trivial
- **Found:** 2026-10-17, while testing the niri backend

### Two exclusive-focus surfaces at once without a native grab
- **Where:** `services/FocusGrab.qml` (`exclusive`), `components/hosts/overlay/OverlayPanel.qml`, `components/hosts/popout/BarPopouts.qml`, `components/hosts/popout/EdgePopout.qml`
- **What:** Without `supports.focusGrab`, every active grab's surface asks for `WlrKeyboardFocus.Exclusive`. With the overlay open (exclusive the whole time) and a popout with a text field opened over it, two surfaces on the Overlay layer ask for exclusive focus. Which one gets the keyboard is up to the compositor. On niri the older one keeps it (found fixing the polkit prompt, c49b429, which now turns `exclusive` off while `ShellManager.modalShown`), so there typing into a popout over the overlay goes to the overlay. Sway is unchecked (`scripts/dev/nested.sh sway`). A fix in the same spirit: only the newest active grab is `exclusive`.
- **Size:** small
- **Found:** 2026-10-16, while auditing the layer-placement branch

### Missing app icons warn in the log
- **Where:** `services/LauncherManager.qml` (`Quickshell.iconPath`), `services/DockManager.qml`
- **What:** An app whose `.desktop` icon isn't in the icon theme (here `xdg-desktop-portal-gtk`'s `applications-system-symbolic`) logs `Could not load icon` at each size it's drawn, though the fallback icon shows. Noise in `scripts/log.sh`; either skip hidden/`NoDisplay` entries or resolve the name before handing it to an Image.
- **Size:** trivial
- **Found:** 2026-10-16, while auditing the layer-placement branch

### Self-update and the greeter installer assume git
- **Where:** `services/SelfUpdateManager.qml`, `scripts/greeter/greeter_install.sh`
- **What:** Self-update and the greeter installer work on `Paths.axiomPath` as a git clone. A package manager owns updates, so these should hide or switch when there is no `.git`. Blocks packaging, not the XDG move.
- **Size:** needs a plan
- **Found:** 2026-10-15, while moving config and state to the XDG folders

### Text input warnings when the desktop takes the keyboard
- **Where:** `components/surfaces/desktop/DesktopWindow.qml` (`WlrLayershell.keyboardFocus`)
- **What:** With a typing module (Notes) on the desktop, clicking into it and back to windows logs bursts of `Trying to disable` from `qt.qpa.wayland.textinput` (`QWaylandTextInputv3::disableSurface`; 174 in one session). Typing and handing focus back work. Likely Qt's text-input-v3 noise when focus moves between surfaces; not yet checked whether an edge menu's Notes logs the same.
- **Size:** small
- **Found:** 2026-10-14, while letting typing modules go on the desktop

### `Bar` reader holds the edges enum and breaks reader naming
- **Where:** `config/Bar.qml` (`enum Location`, the `Bars` reader)
- **What:** The `Bars` section's reader is named `Bar` (other readers are named for their section, with a `Config` suffix where needed), and the same file declares the `Location` edge enum (`Bar.Top`, `Bar.Left`, …) that docks, OSDs, popouts and edge menus use. About 302 `Bar.` references in 57 files, 204 of them the enum. Plan: move the enum to a new `Edge` singleton in config/ (`Edge.Top`), then rename the reader (e.g. `BarsConfig`). `gen_docs.py` needs no change; add the old names to `RETIRED` in `scripts/check_docs.py`, and force a reload afterwards (testing.md › Reloads and logs).
- **Size:** needs a plan
- **Found:** 2026-10-13, while assessing reader renames for the docs makeover

### `BlurManager.paused` warns on every reload
- **Where:** `services/BlurManager.qml` (`paused`), `services/UpdatesManager.qml` (`checking`), `services/SelfUpdateManager.qml`, `services/HyprlandManager.qml` (`activeWindowId`)
- **What:** Every config reload logs `Unable to assign [undefined] to bool` at the `paused` declaration (and, seen 2026-10-14, at `UpdatesManager.checking`, also a readonly bool on a singleton: likely the same cause; seen 2026-10-16 as `Unable to assign [undefined] to QString` at `HyprlandManager.activeWindowId`, a readonly string). The binding itself evaluates to a boolean (a temporary probe logged `boolean false`), and a constant `paused: false` still warned, so it isn't the expression: something in Quickshell's reload of this singleton assigns it. Harmless (the value is right afterwards), but it's noise in every `scripts/log.sh`. Next step: check whether Quickshell carries readonly properties across a reload, or whether making `paused` a plain function helps.
- **Size:** small
- **Found:** 2026-10-13, while checking reload logs during the docs makeover

