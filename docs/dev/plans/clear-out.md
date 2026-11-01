# The clear-out's PR list

> **Roadmap:** [Phase 11](../roadmap.md#phase-11-audits-clear-out-and-hardening) step 2 (row 20), step 2.1 "Triage first"
> **Status:** triage done 2026-11-01; questions answered 2026-11-01; the order stands (maintainer, 2026-11-01: "Start as written (Recommended)"); config-01, platform-01, core-ui-theming-01, compositor-01, compositor-02, compositor-03, compositor-04, bar-popouts-01, overlay-modules-01, features-01, bar-popouts-02, features-02, config-02 and config-03 done

Not an options plan: this is row 20's PR list, combined from the seven area triage passes (compositor, features, bar-popouts, overlay-modules, core-ui-theming, platform, config). The loop takes the next cluster in the order below; each cluster is one item, committed one commit per file group (step 2.6). A cluster's entries leave issues.md as it lands, and this file is deleted with the row's last cluster. Deferred and Phase 13 (on hold) entries aren't in it.

### Answered (maintainer, 2026-11-01)
The product questions, answered in one sitting (step 2.5); each entry quotes its answer under **Decided**, and the deferred ones are under [Deferred](../roadmap.md#deferred).

1. Over a config.json that didn't load at the start, keeping the running config saves the defaults over the active snapshot: b) apply the snapshot with default machine settings.
2. [With Idle on and the user's own locker left at loginctl lock-session, nothing locks](../issues.md#with-idle-on-and-the-users-own-locker-left-at-loginctl-lock-session-nothing-locks): yes, the plan also shows "doesn't lock" as a status.
3. [The onboarder's Integrations page is too long for one step](../issues.md#the-onboarders-integrations-page-is-too-long-for-one-step): split, with the theme page directly after integrations.
4. [Power repeats the session actions' icons, labels and confirm](../issues.md#power-repeats-the-session-actions-icons-labels-and-confirm): a) "Restart" / "Shut down".
5. Deferred: [Setting an awww wallpaper never starts awww's daemon](../issues.md#setting-an-awww-wallpaper-never-starts-awwws-daemon) (awww's own branch).
6. The Hyprland Go code keeps dead and doubled helpers: drop the old-claims fallback.
7. [Gaps to the edges are wider on sway than the setting says](../issues.md#gaps-to-the-edges-are-wider-on-sway-than-the-setting-says): accept the narrower gap.
8. [The bind list's flag icons carry tooltip strings nothing shows](../issues.md#the-bind-lists-flag-icons-carry-tooltip-strings-nothing-shows): show them.
9. Deferred: [A side edge's submenus always open away from the edge](../issues.md#a-side-edges-submenus-always-open-away-from-the-edge).
10. Removed: an edge popout's inconsistent size (fixed, maintainer).
11. Deferred: [A pill bar's end reach trails a sliding popout's wall](../issues.md#a-pill-bars-end-reach-trails-a-sliding-popouts-wall).
12. Deferred: [The lock screen has no settings for allowing or viewing notifications](../issues.md#the-lock-screen-has-no-settings-for-allowing-or-viewing-notifications) (filed apart; overlay-modules-07 goes ahead).
13. [A dock beside another edge's reserving dock is laid out as if that dock weren't there](../issues.md#a-dock-beside-another-edges-reserving-dock-is-laid-out-as-if-that-dock-werent-there): b) reach past it as edge popouts do.
14. [Skipping a focus session counts it as finished](../issues.md#skipping-a-focus-session-counts-it-as-finished): c) count only if the session had started.
15. [PomodoroDial redraws DialControls' ring and buttons](../issues.md#pomodorodial-redraws-dialcontrols-ring-and-buttons): accept the dots and picker under the ring.
16. Deferred: [Calendar times in a Windows zone name with no VTIMEZONE read as local time](../issues.md#calendar-times-in-a-windows-zone-name-with-no-vtimezone-read-as-local-time) (left logged, no table).

### Cross-area merges
Settled in this triage. One real duplicate was merged in issues.md; the rest are entries moved into one cluster because they share code.

- **Duplicate, merged:** "High module padding clips edge menu modules" (bar-popouts, from the maintainer's notes) is folded into [fullMinWidth and fullMinHeight are compared with the slot's size, padding included](../issues.md#fullminwidth-and-fullminheight-are-compared-with-the-slots-size-padding-included). One cause: compact compares the whole slot with the fullMin sizes, so a higher padding clips a module instead of making it compact. The note is quoted in the kept entry, its Phase 7 link removed (the kept entry is in Phase 8), the edge-menus review record points at the kept entry. Cluster overlay-modules-02.
- **Takeover settings, settings page and launcher:** config's preview entry and platform's launcher /config entry are one fix, the decided SchemaLayout predicate (maintainer, 2026-10-31): config-03.
- **Sway's named workspaces share id -1** moves from features to compositor-11, beside sway-lists-disabled-outputs (the same SwayState and CompositorManager code).
- **A popout taller than the screen** (features, needs a plan) joins bar-popouts' tray submenu entry in the plan cluster bar-popouts-13; the tray's most-height can be the plan's first item.
- **NowPlaying's hidden strip and transports** (bar-popouts) ride overlay-modules-03: the code is NowPlaying.qml, whose mini and short switches that cluster recomputes, and the entry says to fix it with them.
- **The Keybinds page on a small monitor** (compositor) joins bar-popouts' 1080p plan, bar-popouts-11, as its entry asks.
- **The Updates popout's frozen list** (bar-popouts) rides core-ui-theming-03 with the failed update check: the same UpdatesManager-to-popout path.
- **The reader-member check:** config-01 fixes the check and deletes what it finds together with core-ui-theming's six and platform's three reader members, so config-usage-baseline.json changes once.
- **Compositor pairs that must land together:** the detached layer's unbind list with noteReload's double count (compositor-15); the sway output rule with no serial with the niri-spelled monitor (compositor-09); sway's title-bar mouse bind with the sway extract's input-device case (compositor-07); three listings of niri's user files with the bind merge's three listings (compositor-01); nothing-reads-userBindsRead-or-lastLoadFailed with niri started on a broken config (the shell's lastLoadFailed goes in compositor-01, the Go fix in compositor-05, in that order).
- **Ordered, not merged** (shared files, different causes): overlay-modules-01 after compositor-02 (OverlayPageNavigator); compositor-16 after config-04 (KeybindEditor's presets); core-ui-theming-04 after platform-05 (/generate's monitor); features-08 after core-ui-theming-02 (DailySchedule's reload fix); features-14 after overlay-modules-04 (Calculator, Stopwatch, TodoList, Agenda); features-11 after overlay-modules-10 (Tailscale, WifiJoinForm); bar-popouts-07 after overlay-modules-02 (module padding in edge menus).

### The PR list
Deletions first, as step 2.4 allows (config-01 ahead of the rest, so the fixed reader check runs before the other deletions), then the three Blockers, then area by area: Majors, then the area's minor sweep (step 2.3), then its plans and live-only clusters, which go through [Items that need a plan](../roadmap.md#items-that-need-a-plan) or wait for a repro and don't hold up the loop. Areas run config, platform, core-ui-theming, compositor, bar-popouts, overlay-modules, features, so each shared piece (the takeover predicate, notify-send in Go, DailySchedule, the ui-kit, KeybindEditor, the module base, OSDTriggers) changes once, in its owner's PR, before the features that use it.

Size gate (~800 lines): none is estimated over it. bar-popouts-04 (seven entries) splits into its reserve three and its editor and rebuild four if it passes; platform-03 (~400, mostly notify-send into Go), overlay-modules-04 and features-14 (~300 each) split by file group if they do. compositor-01 (~550, mostly removed) and compositor-17 (~450) fit. Fixes confirmed only live (platform-02 and -04, core-ui-theming-02 and -04, features-05, -08, -09 and -11) are built and tested offline and add a [Live checks](../roadmap.md#live-checks) line when they land.

| # | Cluster | Kind | Title | Entries | Est. lines | Depends on | Questions |
|---|---|---|---|---|---|---|---|
| 1 | config-01 | deletion | Done: Config pipeline and store dead code, the step-test runner, and every reader member nothing reads | 9 | ~370 (net about -270) | none |  |
| 2 | platform-01 | deletion | Done: Dead code across the daemon, launcher, greeter and security | 6 | ~190 | config-01 |  |
| 3 | core-ui-theming-01 | deletion | Done: Dead members and pure shrinks in core services, ui-kit, theming and Wayland | 7 | ~-100 net | config-01 |  |
| 4 | compositor-01 | deletion | Done: Go compositor backend: dead and doubled helpers | 17 | ~550 (~370 out) | none | Q6 |
| 5 | compositor-02 | deletion | Done: QML compositor services, keybind helpers, workspace strips | 12 | ~450 | none |  |
| 6 | compositor-03 | deletion | Done: The blur system | 5 | ~200 | none |  |
| 7 | bar-popouts-01 | deletion | Done: Dead members, signals and wrappers across popouts, the bar, bar widgets and edge menus | 12 | ~150 | none |  |
| 8 | overlay-modules-01 | deletion | Done: Overlay and modules: dead members and small shrinks | 6 | ~200 touched (~-150 net) | compositor-02 |  |
| 9 | features-01 | deletion | Done: Dead and forwarding members across the feature systems | 14 | ~250 | none |  |
| 10 | compositor-04 | blocker | Done: Sway's look lost after a reload | 1 | ~10 | compositor-02 |  |
| 11 | bar-popouts-02 | blocker | Done: Outside clicks never close edge and floating popouts | 1 | ~4 | none |  |
| 12 | features-02 | blocker | Done: The 12-hour clock's hour, and the Accounts card's read-only and task-list facts | 2 | ~25 | features-01 |  |
| 13 | config-02 | major | Done: The store's load and write safety | 3 | ~220 | config-01 | Q1 |
| 14 | config-03 | major | Done: The settings page's schema predicates, and takeover settings from the launcher | 4 | ~170 | none |  |
| 15 | config-04 | major | Editor fields and draft comparisons | 3 | ~110 | none |  |
| 16 | config-05 | minor-sweep | Config and guardrails | 2 | ~50 | config-03, config-04 |  |
| 17 | platform-02 | major | Locking and the greeter | 5 | ~150 | platform-01 | Q2 |
| 18 | platform-03 | major | Packaging and self-update | 4 | ~400 | none |  |
| 19 | platform-04 | major | Dev-mode re-exec and the protocol | 4 | ~200 | platform-01 |  |
| 20 | platform-05 | major | Launcher and IPC input | 2 | ~80 | platform-01 |  |
| 21 | platform-06 | minor-sweep | The onboarder | 3 | ~150 | platform-03 | Q3 |
| 22 | platform-07 | minor-sweep | The launcher with its providers | 2 | ~80 | platform-05 |  |
| 23 | platform-08 | minor-sweep | Security: the session actions | 1 | ~60 | platform-02 | Q4 |
| 24 | core-ui-theming-02 | major | Services that run with nothing shown, the media pick, schedules lost on reload | 4 | ~220 | core-ui-theming-01 |  |
| 25 | core-ui-theming-03 | major | Daemon failures the shell never sees, and the Updates popout's list | 4 | ~200 | core-ui-theming-01, bar-popouts-01 |  |
| 26 | core-ui-theming-04 | major | Themes changing unbidden, and two integration bugs | 5 | ~130 | core-ui-theming-01, platform-05 |  |
| 27 | core-ui-theming-05 | major | ui-kit bugs users notice | 3 | ~110 | core-ui-theming-01 |  |
| 28 | core-ui-theming-06 | minor-sweep | ui-kit shared pieces | 4 | ~250 touched (~-100 net) | core-ui-theming-05 |  |
| 29 | core-ui-theming-07 | minor-sweep | Core services, theming and theme integrations | 4 | ~60 | core-ui-theming-04 |  |
| 30 | compositor-05 | major | The daemon's mode lifecycle (detect, load, leave, claim) | 6 | ~350 | compositor-01 |  |
| 31 | compositor-06 | major | Takeover and the user's config files | 5 | ~250 | compositor-01 |  |
| 32 | compositor-07 | major | The bind merge's remove, and reading sway and niri binds | 6 | ~200 | compositor-01 |  |
| 33 | compositor-08 | major | What a moved bind becomes | 3 | ~120 | compositor-07 |  |
| 34 | compositor-21 | major | Command text in moved and written binds | 4 | ~150 | compositor-08 |  |
| 35 | compositor-09 | major | Applying monitor rules | 4 | ~150 | compositor-05 |  |
| 36 | compositor-10 | major | The trial Apply and the Monitors page | 3 | ~80 | none |  |
| 37 | compositor-11 | major | Workspace blocks and switching, and sway's workspace ids | 5 | ~110 | compositor-02 |  |
| 38 | compositor-12 | major | Overview and window events | 3 | ~80 | compositor-02 |  |
| 39 | compositor-13 | major | The window look as written and read back | 5 | ~120 | compositor-03, compositor-04 | Q7 |
| 40 | compositor-20 | major | Blur fills | 2 | ~20 | compositor-03 |  |
| 41 | compositor-14 | major | Capability gates in the schema | 3 | ~80 | none |  |
| 42 | compositor-15 | major | The runtime layer's record of what it bound | 3 | ~100 | compositor-05, compositor-09 |  |
| 43 | compositor-16 | major | The Keybinds page | 6 | ~120 | compositor-02, config-04 |  |
| 44 | compositor-17 | minor-sweep | Hyprland, with the keybind helpers and UI it owns | 18 | ~450 | compositor-01, -02, -07, -16 | Q8 |
| 45 | compositor-18 | plan | Touchpad settings apart from the mouse's | 1 | needs a plan | none |  |
| 46 | bar-popouts-03 | major | EdgePopout's placement read from SurfaceContext | 2 | ~60 | bar-popouts-01 |  |
| 47 | bar-popouts-04 | major | The bar's reserve and rebuild identity | 7 | ~120 | bar-popouts-01 |  |
| 48 | bar-popouts-06 | major | Bar widgets that clip or glide | 4 | ~60 | bar-popouts-01 |  |
| 49 | bar-popouts-07 | major | Edge menu sizing, placement and zones | 5 | ~250 | bar-popouts-01, overlay-modules-02 |  |
| 50 | bar-popouts-08 | minor-sweep | Popouts and edge menus | 5 | ~120 | bar-popouts-03, -07 |  |
| 51 | bar-popouts-09 | minor-sweep | The bar and bar widgets, with the workspace popouts | 7 | ~200 | bar-popouts-04, -06 |  |
| 52 | bar-popouts-11 | plan | The 1080p pass: text clips, and the Keybinds page on a small monitor | 2 | needs a plan | compositor-16 |  |
| 53 | bar-popouts-12 | plan | Nineteen windows mapped on one monitor | 1 | needs a plan | none |  |
| 54 | bar-popouts-13 | plan | Popouts and tray submenus taller than the screen | 2 | needs a plan | bar-popouts-08 |  |
| 55 | overlay-modules-02 | major | Slot padding and grow in the module base | 4 | ~150 | overlay-modules-01 |  |
| 56 | overlay-modules-03 | major | Per-module full minimums, and NowPlaying's hidden parts | 5 | ~280 | overlay-modules-02 |  |
| 57 | overlay-modules-04 | major | Parts built hidden, and images decoded more than once | 2 | ~300 | overlay-modules-03 |  |
| 58 | overlay-modules-05 | major | The overlay host and the Layouts editor | 4 | ~80 | none |  |
| 59 | overlay-modules-06 | major | Custom widgets | 4 | ~150 | none |  |
| 60 | overlay-modules-07 | major | What reaches the lock screen | 2 | ~150 | overlay-modules-06 |  |
| 61 | overlay-modules-08 | major | OSD volume and brightness (done with the OSD's statuses) | 0 | none left | overlay-modules-01 |  |
| 62 | overlay-modules-09 | minor-sweep | The overlay and custom widgets | 6 | ~80 | overlay-modules-05, -06 |  |
| 63 | overlay-modules-10 | minor-sweep | Modules | 5 | ~200 touched (~-130 net) | overlay-modules-03 |  |
| 64 | overlay-modules-11 | minor-sweep | Hot corners | 2 | ~120 | none |  |
| 65 | overlay-modules-12 | live-only | The overlay grid's model of -1 | 1 | ~5 | none |  |
| 66 | overlay-modules-13 | plan | Compact cards build their full layout | 1 | needs a plan | overlay-modules-02, -04 |  |
| 67 | features-03 | major | Notifications | 5 | ~200 (net about -80) | platform-03 |  |
| 68 | features-04 | major | The dock | 2 | ~30 | features-01 | Q13 |
| 69 | features-05 | major | Todo, pomodoro and timers | 7 | ~200 | features-01 | Q14, Q15 |
| 70 | features-06 | major | Calendar saves (the editor and the daemon) | 3 | ~250 | features-01 |  |
| 71 | features-07 | major | Calendar surfaces and accounts | 3 | ~80 | features-02 |  |
| 72 | features-08 | major | Brightness | 1 | ~20 | features-01, core-ui-theming-02 |  |
| 73 | features-09 | major | The chat | 6 | ~180 | features-01 |  |
| 74 | features-10 | major | Notes | 6 | ~180 | features-01, core-ui-theming-05 |  |
| 75 | features-11 | major | Networking and Bluetooth, the VPN list and Tailscale | 5 | ~150 | features-01, overlay-modules-10 |  |
| 76 | features-12 | major | Community setups | 5 | ~30 | features-01 |  |
| 77 | features-13 | major | Screenshots and recording | 4 | ~80 | features-03 |  |
| 78 | features-14 | major | Unbounded lists, and the chat's hidden parts | 2 | ~300 | features-05, -07, -09, overlay-modules-04 |  |
| 79 | features-15 | minor-sweep | The clock format | 1 | ~5 | features-02, -06 |  |

#### Entries by cluster

**Deletions**

- **config-01** (9, done): Takes core-ui-theming's and platform's reader-member entries: the fixed check runs first, then one pass deletes what it and they find, so config-usage-baseline.json changes once.
  - Format-1 secrets plumbing nothing fills or reads
  - The validator and the schema check carry patternProperties nothing uses
  - The config Pipeline interface has one implementation
  - Store.Reschema repeats reload's load-and-apply
  - OpenAdopting repeats Open's setup
  - Every step test copies the same case runner
  - The unused reader member check counts a member named after its key as used
  - Six more reader members nothing reads
  - Three reader members nothing reads
- **platform-01** (6, done):
  - PolkitAgents.isAgentCommand is dead since the autostart moved to Go
  - GreetdManager.available is never read
  - EmojiManager's groups() is never called
  - LauncherManager keeps a dead clear() and a cliphist test
  - The shell's unused daemon-call paths
  - Two dead Go helpers and a forwarding wrapper
- **core-ui-theming-01** (7, done):
  - Small shrinks in the core services
  - setWallpaperAndGenerate only forwards for one caller
  - ~/.current_wallpaper is written but nothing reads it
  - StyledRectButton's badge and border press colour have no user
  - TileGrid and StyledVolumeBar keep lines nothing reads
  - Two hand-written cmp.Or in the theme packages
  - Three Wayland client members nothing in the daemon calls
- **compositor-01** (17, done): One commit per package, the old-claims fallback's 6 lines included (Q6).
  - Hyprland's exit command is kept in two packages
  - The Hyprland Go code keeps dead and doubled helpers
  - Nothing reads userBindsRead or lastLoadFailed
  - The niri writer's runtimeOn and unread-binds guards are dead
  - Three listings of niri's user files
  - RunningNested has its own niri socket client
  - A second KDL writer in the kdl package
  - Small shrinks in the compositor manager
  - niri's bind plan is a copy of runtimeLayer.plan
  - Go copies of bind helpers that only the parity replay calls
  - sway and niri each fit the shadow to axiom's themselves
  - SwayConfigBinds keeps its own copy of sway's $variables
  - Small shrinks in the sway writer and IPC
  - binds and takeover each keep their own isFile and git check
  - The bind merge lists user/ files three times, once per compositor
  - sway's and niri's merges build a moved bind the same way twice
  - The merge keeps key and variable tables render already has
- **compositor-02** (12, done): Leaves the keybind tables entry's _bindMods change to compositor-17.
  - Backends keep stubs for calls the facade gates
  - Small shrinks in the compositor layer
  - HyprlandManager keeps members only it reads
  - KeybindManager keeps tables the methods helpers already hold (its _bindMods part listed under compositor-17)
  - Bind helpers keep JS halves the daemon owns now
  - NiriManager queues actions the daemon could order
  - Small shrinks in SwayManager
  - Sway and niri each forward withMainBinds to the daemon
  - sway and niri build output details and descriptions twice
  - The workspace strips repeat ActiveStrip's loader
  - The workspace strips' panel property is never read
  - Three copies of the wheel-notch accumulator
- **compositor-03** (5, done):
  - SlideAnimation's fade, easing and container aliases are dead
  - The blur window builds stand-ins and copies it never uses
  - BlurBacking spells out four near-identical blur windows
  - The border frame's path is built three times
  - Small shrinks in the blur system
- **bar-popouts-01** (12, done): The layoutUpdated entry is filed Major; its fix is a pure deletion.
  - PopoutWrapperBase's aboutToDismiss signal has no listener
  - Three EdgePopout members nothing reads
  - PopoutGeometry handles a phase and a submenu pair the registry never produces
  - PillBarJoin's available repeats what joined already says
  - Geometry members nothing reads
  - The tray menu's isVertical and barConfig are never read
  - Nothing listens to the bar's layoutUpdated any more
  - StandaloneBar only wraps BarPanel's BarContainer
  - BarContainer._withEntry rebuilds Utils.withEntry
  - enrichBarConfig hands out two fields nothing reads and keeps three dead fallbacks
  - BaseWidget's background box and panel-size defaults are dead
  - IntegratedEdgeMenu's empty engage exists only for EdgeMenuSync's call
- **overlay-modules-01** (6, done): After compositor-02, which also edits OverlayPageNavigator (the wheel notch).
  - GridEditor's canAdd and canMove have no caller
  - ScreenLayoutEditor.savedLayout is dead, and DesktopTarget forwards the editor's room
  - Three row options nothing sets
  - PipewireVolumeBar keeps a mute toggle nothing calls and its own volume icon
  - Three keycap parts draw the same cap, and KeyCap's icon slot has no user
  - Small shrinks in the overlay
- **features-01** (14, done):
  - Calendar results and members nothing reads
  - The Accounts card's fallbacks for a renamed key and for empty account ids
  - Two members of the brightness system nothing needs
  - package chat's Log option is never used
  - ChatManager.copy only forwards to ClipboardManager.copyText
  - Notes documents count a revision nothing reads
  - NoteMarkdown's reparse repeats _normalize
  - net.join's first-Wi-Fi fallback is never reached
  - The VPN state's device and autoconnect fields nothing reads
  - Tailscale carries two state fields and a guard nothing needs
  - CommunityCatalog's setups carry three fields nothing reads
  - Dead and forwarding members in the timer services and helpers
  - Small shrinks in TimeZoneManager and WorldClocks
  - The dock's trigger placement and window focus go the long way round

**Blockers**

- **compositor-04** (1, done):
  - After a sway reload, gapsOut and SwayFX's per-window blur and shadows stay off until the look changes
- **bar-popouts-02** (1, done):
  - Edge and floating popouts never close when their focus grab clears
- **features-02** (2, done):
  - A 12-hour Clock shows the hour in 24-hour time
  - The Accounts card reads read-only and task-list facts from config entries that never hold them

**config**

- **config-02** (3, done):
  - A format-2 config without a version runs every step again
  - A save overwrites an outside edit of config.json the store hasn't read yet
  - Over a config.json that didn't load at the start, keeping the running config saves the defaults over the active snapshot
- **config-03** (4, done): The two takeover entries are one fix (decided 2026-10-31).
  - Takeover settings go live through the settings page's preview before Save
  - The launcher's /config can switch a takeover setting
  - Changed from default never lists the bar widget style
  - The condition grammar has no shared fixtures
- **config-04** (3): Before compositor-16 and -17, which edit KeybindEditor's presets too.
  - [A number box keeps its typed text when the setting it edits switches under it](../issues.md#a-number-box-keeps-its-typed-text-when-the-setting-it-edits-switches-under-it)
  - [Escape in a settings-page number box leaves the half-typed value in the draft](../issues.md#escape-in-a-settings-page-number-box-leaves-the-half-typed-value-in-the-draft)
  - [Restoring a saved keybind preset marks every bind new, and Revert deletes it](../issues.md#restoring-a-saved-keybind-preset-marks-every-bind-new-and-revert-deletes-it)
- **config-05** (2):
  - [After a refused save, a draft's edits show unsaved but not live](../issues.md#after-a-refused-save-a-drafts-edits-show-unsaved-but-not-live)
  - [The guard reads the branch from the session's folder, not a `cd` before the push](../issues.md#the-guard-reads-the-branch-from-the-sessions-folder-not-a-cd-before-the-push)

**platform**

- **platform-02** (5): The nested-Hyprland timing gets a Live checks line.
  - [A shell started locked locks again on every reload](../issues.md#a-shell-started-locked-locks-again-on-every-reload)
  - [With Idle on and the user's own locker left at loginctl lock-session, nothing locks](../issues.md#with-idle-on-and-the-users-own-locker-left-at-loginctl-lock-session-nothing-locks)
  - [Nested Hyprland acknowledges a lock too late for axiom lock](../issues.md#nested-hyprland-acknowledges-a-lock-too-late-for-axiom-lock)
  - [Uninstall keeps a stale greetd backup when greetd points elsewhere](../issues.md#uninstall-keeps-a-stale-greetd-backup-when-greetd-points-elsewhere)
  - [The greeter reads its keyboard layouts before the bundle's are applied](../issues.md#the-greeter-reads-its-keyboard-layouts-before-the-bundles-are-applied)
- **platform-03** (4): notify-send moves into Go here (NotificationManager, ScreenshotManager, CompositorConfigManager), so it lands before the compositor and features majors. Splits by file group if it passes 800.
  - [install.sh and the AUR packages never install notify-send, gio or pactl](../issues.md#installsh-and-the-aur-packages-never-install-notify-send-gio-or-pactl)
  - [A main-channel update applied after edge moved on needs go to rebuild the binary](../issues.md#a-main-channel-update-applied-after-edge-moved-on-needs-go-to-rebuild-the-binary)
  - [install.sh still installs the rest of a feature whose COPR was declined](../issues.md#installsh-still-installs-the-rest-of-a-feature-whose-copr-was-declined)
  - [The onboarder's Checks-page purposes don't match their declared keys](../issues.md#the-onboarders-checks-page-purposes-dont-match-their-declared-keys)
- **platform-04** (4): Dev mode only; the three re-exec races get Live checks lines.
  - [A dev build during a branch switch re-execs onto the defaults](../issues.md#a-dev-build-during-a-branch-switch-re-execs-onto-the-defaults)
  - [A protocol bump in dev mode leaves the installed CLI on the old protocol](../issues.md#a-protocol-bump-in-dev-mode-leaves-the-installed-cli-on-the-old-protocol)
  - [The shell's hello can be refused across a dev re-exec](../issues.md#the-shells-hello-can-be-refused-across-a-dev-re-exec)
  - [daemon.shutdown starts its goroutine past tasks.Go](../issues.md#daemonshutdown-starts-its-goroutine-past-tasksgo)
- **platform-05** (2): Before core-ui-theming-04, whose other-monitor theme fix assumes /generate reads the right monitor.
  - [The launcher's /generate reads a monitor setting that doesn't exist](../issues.md#the-launchers-generate-reads-a-monitor-setting-that-doesnt-exist)
  - [A word passed to an int IPC parameter is 0](../issues.md#a-word-passed-to-an-int-ipc-parameter-is-0)
- **platform-06** (3):
  - [The onboarder's Integrations page names Hyprland's tools everywhere](../issues.md#the-onboarders-integrations-page-names-hyprlands-tools-everywhere)
  - [The onboarder's Integrations page is too long for one step](../issues.md#the-onboarders-integrations-page-is-too-long-for-one-step)
  - [The Look page offers Hyprland's wallpapers under any compositor](../issues.md#the-look-page-offers-hyprlands-wallpapers-under-any-compositor)
- **platform-07** (2):
  - [A clip's label and detail are written in both the launcher and the clipboard module](../issues.md#a-clips-label-and-detail-are-written-in-both-the-launcher-and-the-clipboard-module)
  - [App scoring is written twice and the use bonus three times](../issues.md#app-scoring-is-written-twice-and-the-use-bonus-three-times)
- **platform-08** (1):
  - [Power repeats the session actions' icons, labels and confirm](../issues.md#power-repeats-the-session-actions-icons-labels-and-confirm)

**core-ui-theming**

- **core-ui-theming-02** (4): Before features-08, which gives idle dimming the same reload fix. SystemManager's self-consumer went with the graphs' history moving into the daemon (its own PR).
  - [MediaManager ticks the position with nothing showing it](../issues.md#mediamanager-ticks-the-position-with-nothing-showing-it)
  - [The active media player is Spotify first and never follows playback](../issues.md#the-active-media-player-is-spotify-first-and-never-follows-playback)
  - [Album art piles up in the runtime folder for the whole session](../issues.md#album-art-piles-up-in-the-runtime-folder-for-the-whole-session)
  - [DailySchedule's persisted state never survives a reload](../issues.md#dailyschedules-persisted-state-never-survives-a-reload)
- **core-ui-theming-03** (4): Takes bar-popouts' Updates popout entry: same UpdatesManager-to-card path.
  - [A failed update check shows as up to date](../issues.md#a-failed-update-check-shows-as-up-to-date)
  - [A weather fetch that fails shows Loading forever](../issues.md#a-weather-fetch-that-fails-shows-loading-forever)
  - [A Wayland protocol error leaves every client claiming its protocol](../issues.md#a-wayland-protocol-error-leaves-every-client-claiming-its-protocol)
  - [The Updates popout's package list is frozen at opening](../issues.md#the-updates-popouts-package-list-is-frozen-at-opening)
- **core-ui-theming-04** (5):
  - [Rescanning the theme folders lists the shell's working directory as themes](../issues.md#rescanning-the-theme-folders-lists-the-shells-working-directory-as-themes)
  - [A generated theme from a wallpaper reached through a symlink is regenerated at every start](../issues.md#a-generated-theme-from-a-wallpaper-reached-through-a-symlink-is-regenerated-at-every-start)
  - [A theme generated from another monitor's wallpaper is replaced by the primary's at the next start](../issues.md#a-theme-generated-from-another-monitors-wallpaper-is-replaced-by-the-primarys-at-the-next-start)
  - [ncspot's splice keeps nothing after a begin marker that follows the end marker](../issues.md#ncspots-splice-keeps-nothing-after-a-begin-marker-that-follows-the-end-marker)
  - [Kitty reloads only when its socket is /tmp/kitty-*](../issues.md#kitty-reloads-only-when-its-socket-is-tmpkitty-)
- **core-ui-theming-05** (3):
  - [Icons.overrides never reaches window icons](../issues.md#iconsoverrides-never-reaches-window-icons)
  - [A cancelled rename's typed text comes back in the notes and chat rename fields](../issues.md#a-cancelled-renames-typed-text-comes-back-in-the-notes-and-chat-rename-fields)
  - [Nine shared controls animate with their own easing, written out where Glide does it](../issues.md#nine-shared-controls-animate-with-their-own-easing-written-out-where-glide-does-it)
- **core-ui-theming-06** (4):
  - [Every StyledSlider overrides its look and its value the same way](../issues.md#every-styledslider-overrides-its-look-and-its-value-the-same-way)
  - [Eleven StyledIconButtons undo its stretching to be FlatIconButtons](../issues.md#eleven-stylediconbuttons-undo-its-stretching-to-be-flaticonbuttons)
  - [ActionTile and ActionPill carry the same countdown bar](../issues.md#actiontile-and-actionpill-carry-the-same-countdown-bar)
  - [StyledTextEntry and StyledTextArea carry the same blinking cursor](../issues.md#styledtextentry-and-styledtextarea-carry-the-same-blinking-cursor)
- **core-ui-theming-07** (4):
  - [runDetached warns about a lost connection](../issues.md#rundetached-warns-about-a-lost-connection)
  - [AGENTS.md's funnel rule doesn't name FileManager.write and watch](../issues.md#agentsmds-funnel-rule-doesnt-name-filemanagerwrite-and-watch)
  - [fzf's flags rebuilt in Go where a template does](../issues.md#fzfs-flags-rebuilt-in-go-where-a-template-does)
  - [The onboarder's integration commands are a hand-kept list in ThemeManager](../issues.md#the-onboarders-integration-commands-are-a-hand-kept-list-in-thememanager)

**compositor**

- **compositor-05** (6): The niri entry's shell-side lastLoadFailed is deleted in compositor-01.
  - [The daemon picks a compositor the shell may not run under](../issues.md#the-daemon-picks-a-compositor-the-shell-may-not-run-under)
  - [A file mode that stops loading keeps the saved monitor profile off](../issues.md#a-file-mode-that-stops-loading-keeps-the-saved-monitor-profile-off)
  - [Leaving included between sessions leaves the full module loaded](../issues.md#leaving-included-between-sessions-leaves-the-full-module-loaded)
  - [A failed takeover leaves no layer and no problem](../issues.md#a-failed-takeover-leaves-no-layer-and-no-problem)
  - [A failed takeover check reuses the last answer and can adopt without approval](../issues.md#a-failed-takeover-check-reuses-the-last-answer-and-can-adopt-without-approval)
  - [niri started on a broken config reads as loaded](../issues.md#niri-started-on-a-broken-config-reads-as-loaded)
- **compositor-06** (5):
  - [Claim keeps writing a symlinked or git-tracked config that release refuses to give back](../issues.md#claim-keeps-writing-a-symlinked-or-git-tracked-config-that-release-refuses-to-give-back)
  - [sway's hookup and takeover use ~/.config/sway/config whatever config sway runs](../issues.md#sways-hookup-and-takeover-use-configswayconfig-whatever-config-sway-runs)
  - [A relative -c is read from the daemon's folder](../issues.md#a-relative--c-is-read-from-the-daemons-folder)
  - [A claim comments out axiom's start inside a long string, breaking the script](../issues.md#a-claim-comments-out-axioms-start-inside-a-long-string-breaking-the-script)
  - [A sway include path with a space breaks after a takeover](../issues.md#a-sway-include-path-with-a-space-breaks-after-a-takeover)
- **compositor-07** (6):
  - [Hyprland's remove deletes whatever hl.bind is on a site's line now](../issues.md#hyprlands-remove-deletes-whatever-hlbind-is-on-a-sites-line-now)
  - [The bind merge deletes an hl.bind inside a helper, losing binds it never read](../issues.md#the-bind-merge-deletes-an-hlbind-inside-a-helper-losing-binds-it-never-read)
  - [A niri merge of two binds on one line loses one](../issues.md#a-niri-merge-of-two-binds-on-one-line-loses-one)
  - [A sway line continuing a non-bind line is moved as a bind of its own](../issues.md#a-sway-line-continuing-a-non-bind-line-is-moved-as-a-bind-of-its-own)
  - [A sway title-bar mouse bind moves in as a whole-window bind](../issues.md#a-sway-title-bar-mouse-bind-moves-in-as-a-whole-window-bind)
  - [The sway extract's input-device case and isSwayFlag repeat the general rule](../issues.md#the-sway-extracts-input-device-case-and-isswayflag-repeat-the-general-rule)
- **compositor-08** (3; two entries fixed by the bind actions PR):
  - [The Hyprland and sway bind merges each skip half of compositor/actions](../issues.md#the-hyprland-and-sway-bind-merges-each-skip-half-of-compositoractions)
  - [sway's merge moves workspace binds as raw sway commands](../issues.md#sways-merge-moves-workspace-binds-as-raw-sway-commands)
  - [niri's confirming quit moves in as an instant log out](../issues.md#niris-confirming-quit-moves-in-as-an-instant-log-out)
- **compositor-21** (4):
  - [A sway bind using a variable from an include moves as a literal $name](../issues.md#a-sway-bind-using-a-variable-from-an-include-moves-as-a-literal-name)
  - [A niri spawn of one word with a space moves as a broken shell command](../issues.md#a-niri-spawn-of-one-word-with-a-space-moves-as-a-broken-shell-command)
  - [A sway exec chained with ; or , moves in as one shell command](../issues.md#a-sway-exec-chained-with--or--moves-in-as-one-shell-command)
  - [A $' or $& in a bind's argument is read as a replacement pattern](../issues.md#a--or--in-a-binds-argument-is-read-as-a-replacement-pattern)
- **compositor-09** (4):
  - [A failed monitor profile apply is never retried for the same outputs](../issues.md#a-failed-monitor-profile-apply-is-never-retried-for-the-same-outputs)
  - [A sway output rule by description misses a monitor with no serial](../issues.md#a-sway-output-rule-by-description-misses-a-monitor-with-no-serial)
  - [The Monitors page's Apply misses a niri-spelled monitor on Hyprland and sway](../issues.md#the-monitors-pages-apply-misses-a-niri-spelled-monitor-on-hyprland-and-sway)
  - [Managed mode's monitor-conflict check misses quoted and block output lines](../issues.md#managed-modes-monitor-conflict-check-misses-quoted-and-block-output-lines)
- **compositor-10** (3): The reload entry is a rare path: smallest fix.
  - [A trial monitor Apply that turns a monitor off drops its Keep/Revert](../issues.md#a-trial-monitor-apply-that-turns-a-monitor-off-drops-its-keeprevert)
  - [A shell reload during a trial monitor Apply loses the way back](../issues.md#a-shell-reload-during-a-trial-monitor-apply-loses-the-way-back)
  - [Where the compositor can't mirror, a profile's mirror can't be turned off or its monitor placed](../issues.md#where-the-compositor-cant-mirror-a-profiles-mirror-cant-be-turned-off-or-its-monitor-placed)
- **compositor-11** (5): Takes features' sway named-workspaces entry (SwayState, CompositorManager).
  - [A remap runs at startup, from the layout before the config loaded](../issues.md#a-remap-runs-at-startup-from-the-layout-before-the-config-loaded)
  - [A monitor a profile names by description gets the next block until its description arrives](../issues.md#a-monitor-a-profile-names-by-description-gets-the-next-block-until-its-description-arrives)
  - [sway lists disabled outputs as outputs](../issues.md#sway-lists-disabled-outputs-as-outputs)
  - [In the standard layout, a switch past `count` slides through an unrelated workspace](../issues.md#in-the-standard-layout-a-switch-past-count-slides-through-an-unrelated-workspace)
  - [sway's named workspaces all share workspace id -1](../issues.md#sways-named-workspaces-all-share-workspace-id--1)
- **compositor-12** (3):
  - [The overview stays open with nothing shown after its monitor goes away](../issues.md#the-overview-stays-open-with-nothing-shown-after-its-monitor-goes-away)
  - [niri's overview drop moves a window's whole column and switches workspace](../issues.md#niris-overview-drop-moves-a-windows-whole-column-and-switches-workspace)
  - [niri doesn't send windowFocused for a window that opens focused](../issues.md#niri-doesnt-send-windowfocused-for-a-window-that-opens-focused)
- **compositor-13** (5):
  - [A user's blur off overrides axiom's blur on niri](../issues.md#a-users-blur-off-overrides-axioms-blur-on-niri)
  - [Gaps to the edges are wider on sway than the setting says](../issues.md#gaps-to-the-edges-are-wider-on-sway-than-the-setting-says)
  - [A failed options read sets Hyprland's gaps to 0](../issues.md#a-failed-options-read-sets-hyprlands-gaps-to-0)
  - [The Translucency card reads the window look's blur object as a switch](../issues.md#the-translucency-card-reads-the-window-looks-blur-object-as-a-switch)
  - [A failed cursor theme call keeps the theme's own name all session](../issues.md#a-failed-cursor-theme-call-keeps-the-themes-own-name-all-session)
- **compositor-20** (2): Two majors; may ride in compositor-13 (TranslucencyStatus is next to it).
  - [A backed toast's blur fill is at the surface opacity twice](../issues.md#a-backed-toasts-blur-fill-is-at-the-surface-opacity-twice)
  - [A keepFill opening leaves an unfilled row in an unbacked translucent pill](../issues.md#a-keepfill-opening-leaves-an-unfilled-row-in-an-unbacked-translucent-pill)
- **compositor-14** (3):
  - ["Fire on release" is offered on niri and silently dropped](../issues.md#fire-on-release-is-offered-on-niri-and-silently-dropped)
  - [Three settings stay editable on niri though its writer drops them](../issues.md#three-settings-stay-editable-on-niri-though-its-writer-drops-them)
  - [Wide active is hidden in the perMonitor layout but still applies there](../issues.md#wide-active-is-hidden-in-the-permonitor-layout-but-still-applies-there)
- **compositor-15** (3):
  - [The detached layer's unbind list can drift from what sway holds](../issues.md#the-detached-layers-unbind-list-can-drift-from-what-sway-holds)
  - [noteReload counts every compositor reload a second time](../issues.md#notereload-counts-every-compositor-reload-a-second-time)
  - [One refused line stops the rest of a Hyprland eval](../issues.md#one-refused-line-stops-the-rest-of-a-hyprland-eval)
- **compositor-16** (6):
  - [The Keybinds page goes stale after a detached-mode Save](../issues.md#the-keybinds-page-goes-stale-after-a-detached-mode-save)
  - [A combo lookup says nothing holds a key the search or chips hide, and offers to bind it](../issues.md#a-combo-lookup-says-nothing-holds-a-key-the-search-or-chips-hide-and-offers-to-bind-it)
  - [The bind inspector's typed label and argument miss Save](../issues.md#the-bind-inspectors-typed-label-and-argument-miss-save)
  - [Picking a key in the key map under an edit search selects a bind the list doesn't show](../issues.md#picking-a-key-in-the-key-map-under-an-edit-search-selects-a-bind-the-list-doesnt-show)
  - [Renaming a saved preset after switching presets renames the wrong one](../issues.md#renaming-a-saved-preset-after-switching-presets-renames-the-wrong-one)
  - [The reference's sections and both chip rows are built while hidden](../issues.md#the-references-sections-and-both-chip-rows-are-built-while-hidden)
- **compositor-17** (18): Six file groups, one commit each; fine under the gate.
  - [The bind merge removes an hl.unbind whether or not its bind went](../issues.md#the-bind-merge-removes-an-hlunbind-whether-or-not-its-bind-went)
  - [A user/ file with a dot in its name never loads](../issues.md#a-user-file-with-a-dot-in-its-name-never-loads)
  - [A moved raw bind with a Lua keyword key compiles to nothing](../issues.md#a-moved-raw-bind-with-a-lua-keyword-key-compiles-to-nothing)
  - [The managed file's catch-all monitor line is copied into M.monitors](../issues.md#the-managed-files-catch-all-monitor-line-is-copied-into-mmonitors)
  - [A workspace slide throws when animations go off between its legs](../issues.md#a-workspace-slide-throws-when-animations-go-off-between-its-legs)
  - [Direct Hyprland dispatches can overtake queued Lua](../issues.md#direct-hyprland-dispatches-can-overtake-queued-lua)
  - [Recording two keys within 30 s can end the second recording early on Hyprland](../issues.md#recording-two-keys-within-30-s-can-end-the-second-recording-early-on-hyprland)
  - [Two keybind reference paths drop a key's binds](../issues.md#two-keybind-reference-paths-drop-a-keys-binds)
  - [KeybindManager keeps tables the methods helpers already hold](../issues.md#keybindmanager-keeps-tables-the-methods-helpers-already-hold) (its _bindMods part, left by compositor-02)
  - [A bind description's section is parsed three ways](../issues.md#a-bind-descriptions-section-is-parsed-three-ways)
  - [Keybind sections log null reads as they're torn down](../issues.md#keybind-sections-log-null-reads-as-theyre-torn-down)
  - [WorkspaceStrip's Grid briefly has more items than cells](../issues.md#workspacestrips-grid-briefly-has-more-items-than-cells)
  - [The key map and the keyboard reference each carry the same modifier chips and legend](../issues.md#the-key-map-and-the-keyboard-reference-each-carry-the-same-modifier-chips-and-legend)
  - [A reference section's folded count re-derives BindRows.byModifiers' grouping](../issues.md#a-reference-sections-folded-count-re-derives-bindrowsbymodifiers-grouping)
  - [PresetSheet defers its re-choose a tick for a config that updates at once](../issues.md#presetsheet-defers-its-re-choose-a-tick-for-a-config-that-updates-at-once)
  - [The bind list's flag icons carry tooltip strings nothing shows](../issues.md#the-bind-lists-flag-icons-carry-tooltip-strings-nothing-shows)
  - [A reference section's title is worked out twice](../issues.md#a-reference-sections-title-is-worked-out-twice)
  - [Stale lines in the Hyprland docs and comments](../issues.md#stale-lines-in-the-hyprland-docs-and-comments)
- **compositor-18** (1): Decided that they separate; the plan settles how on Hyprland.
  - [Mouse speed, acceleration and left-handed reach the touchpad only on Hyprland](../issues.md#mouse-speed-acceleration-and-left-handed-reach-the-touchpad-only-on-hyprland)

**bar-popouts**

- **bar-popouts-03** (2):
  - [An open edge popout's layer and namespace still follow its edge's bar](../issues.md#an-open-edge-popouts-layer-and-namespace-still-follow-its-edges-bar)
  - [EdgePopout works out its attach edge and slide distance itself](../issues.md#edgepopout-works-out-its-attach-edge-and-slide-distance-itself)
- **bar-popouts-04** (4; its three reserve entries fixed by the stacked bars PR): the editor and rebuild entries.
  - [Plugging in or unplugging a monitor remakes the bar that stays](../issues.md#plugging-in-or-unplugging-a-monitor-remakes-the-bar-that-stays)
  - [A bar made while the bar editor is open may never report to it](../issues.md#a-bar-made-while-the-bar-editor-is-open-may-never-report-to-it)
  - [Removing or copying another bar moves the editor's selection to a different bar](../issues.md#removing-or-copying-another-bar-moves-the-editors-selection-to-a-different-bar)
  - [Bar widget hosts settle after they're gone](../issues.md#bar-widget-hosts-settle-after-theyre-gone)
- **bar-popouts-06** (4):
  - [Media squeezed to its minimum in the fill style shows the meter, not its icon](../issues.md#media-squeezed-to-its-minimum-in-the-fill-style-shows-the-meter-not-its-icon)
  - [SystemStats' used memory clips on a vertical bar](../issues.md#systemstats-used-memory-clips-on-a-vertical-bar)
  - [The stacked style clips on a thin bar](../issues.md#the-stacked-style-clips-on-a-thin-bar)
  - [The Workspaces widget's measured length glides when the active cell widens](../issues.md#the-workspaces-widgets-measured-length-glides-when-the-active-cell-widens)
- **bar-popouts-07** (5): Its module-padding entry was merged into overlay-modules-02's slot padding entry.
  - [An edge menu can be bigger than its screen](../issues.md#an-edge-menu-can-be-bigger-than-its-screen)
  - [The layouts editor says a menu fits its edge when it scrolls](../issues.md#the-layouts-editor-says-a-menu-fits-its-edge-when-it-scrolls)
  - [A whole-edge menu's hover strip covers only its modules' length while closed](../issues.md#a-whole-edge-menus-hover-strip-covers-only-its-modules-length-while-closed)
  - [An integrated menu's zone stays behind when it changes edge or screen](../issues.md#an-integrated-menus-zone-stays-behind-when-it-changes-edge-or-screen)
  - [Previewing a submenu menu doesn't open it once a module above its row has grown](../issues.md#previewing-a-submenu-menu-doesnt-open-it-once-a-module-above-its-row-has-grown)
- **bar-popouts-08** (5):
  - [SurfaceContext.layout's pill and merged results have no test row](../issues.md#surfacecontextlayouts-pill-and-merged-results-have-no-test-row)
  - [Both tray menu lists override the same width cap](../issues.md#both-tray-menu-lists-override-the-same-width-cap)
  - [The tray menu draws its own separator](../issues.md#the-tray-menu-draws-its-own-separator)
  - [The dock's footprint assumes fillets at both ends](../issues.md#the-docks-footprint-assumes-fillets-at-both-ends)
  - [MenuSubmenu repeats EdgeMenuBody's module grid](../issues.md#menusubmenu-repeats-edgemenubodys-module-grid)
- **bar-popouts-09** (7):
  - [The pill merge in BarContainer repeats BarLayout's, untested](../issues.md#the-pill-merge-in-barcontainer-repeats-barlayouts-untested)
  - [Missing test rows for two helper decisions](../issues.md#missing-test-rows-for-two-helper-decisions)
  - [WindowLookConfig rebuilds BarStyle.look](../issues.md#windowlookconfig-rebuilds-barstylelook)
  - [SystemStats works out ValueStyleWidget's style fallbacks again](../issues.md#systemstats-works-out-valuestylewidgets-style-fallbacks-again)
  - [The workspace switchers find a workspace by id with hand-written loops](../issues.md#the-workspace-switchers-find-a-workspace-by-id-with-hand-written-loops)
  - [The two workspace popouts share 28 lines of payload and colour properties](../issues.md#the-two-workspace-popouts-share-28-lines-of-payload-and-colour-properties)
  - [Small improvements to WorkspaceGrid](../issues.md#small-improvements-to-workspacegrid)
- **bar-popouts-11** (2): Takes compositor's small-monitor Keybinds entry, which says to ride the 1080p pass.
  - [Text clips on 1080p screens](../issues.md#text-clips-on-1080p-screens)
  - [The keybinds page on a small monitor with large binds](../issues.md#the-keybinds-page-on-a-small-monitor-with-large-binds)
- **bar-popouts-12** (1): Phase 12.
  - [Nineteen windows stay mapped on one monitor](../issues.md#nineteen-windows-stay-mapped-on-one-monitor)
- **bar-popouts-13** (2): Takes features' popout entry; the tray fix (a most-height on TrayMenuList) can be the plan's first item.
  - [A tray submenu longer than the screen runs off it](../issues.md#a-tray-submenu-longer-than-the-screen-runs-off-it)
  - [A popout taller than the screen runs off it](../issues.md#a-popout-taller-than-the-screen-runs-off-it)

**overlay-modules**

- **overlay-modules-02** (4): Holds the merged edge-menu padding note (confirm in an edge menu).
  - [fullMinWidth and fullMinHeight are compared with the slot's size, padding included](../issues.md#fullminwidth-and-fullminheight-are-compared-with-the-slots-size-padding-included)
  - [Card and Panel each spell out the grow and expand members](../issues.md#card-and-panel-each-spell-out-the-grow-and-expand-members)
  - [Modules inside borders aren't sized evenly](../issues.md#modules-inside-borders-arent-sized-evenly)
  - [A DeviceList squeezed to nothing wants no growth](../issues.md#a-devicelist-squeezed-to-nothing-wants-no-growth)
- **overlay-modules-03** (5): Takes bar-popouts' NowPlaying entry: its Loaders gate on the switches this cluster recomputes.
  - [Eight modules' full layouts need more room than their fullMin sizes, even inside the padding](../issues.md#eight-modules-full-layouts-need-more-room-than-their-fullmin-sizes-even-inside-the-padding)
  - [SystemGraphs has no px minimum, so its full panels are cut on strips and tall columns](../issues.md#systemgraphs-has-no-px-minimum-so-its-full-panels-are-cut-on-strips-and-tall-columns)
  - [The Clock's date and label keep their room while the time shrinks to nothing](../issues.md#the-clocks-date-and-label-keep-their-room-while-the-time-shrinks-to-nothing)
  - [The Cheatsheet's keyboard view is cut off below about 530 px, with no scroll and no small layout](../issues.md#the-cheatsheets-keyboard-view-is-cut-off-below-about-530-px-with-no-scroll-and-no-small-layout)
  - [NowPlaying builds its strip layout and a second transport hidden in every mode](../issues.md#nowplaying-builds-its-strip-layout-and-a-second-transport-hidden-in-every-mode)
- **overlay-modules-04** (2): Splits by file group if it passes the gate.
  - [Parts shown in one mode are built hidden in every mode, in ten modules and parts](../issues.md#parts-shown-in-one-mode-are-built-hidden-in-every-mode-in-ten-modules-and-parts)
  - [Images decoded at full size or more than once](../issues.md#images-decoded-at-full-size-or-more-than-once)
- **overlay-modules-05** (4):
  - [Reopening the overlay while it closes leaves it open but hidden](../issues.md#reopening-the-overlay-while-it-closes-leaves-it-open-but-hidden)
  - [A clean layout's problem blocks saving the others in the Layouts editor](../issues.md#a-clean-layouts-problem-blocks-saving-the-others-in-the-layouts-editor)
  - [The five layouts drafts are listed by hand in eight places](../issues.md#the-five-layouts-drafts-are-listed-by-hand-in-eight-places)
  - [A turned-off primary desktop layout blanks the primary monitor instead of falling back to all monitors](../issues.md#a-turned-off-primary-desktop-layout-blanks-the-primary-monitor-instead-of-falling-back-to-all-monitors)
- **overlay-modules-06** (4):
  - [A custom widget's module past 8 grid units can't be saved](../issues.md#a-custom-widgets-module-past-8-grid-units-cant-be-saved)
  - [A custom widget's Tooltip switch does nothing](../issues.md#a-custom-widgets-tooltip-switch-does-nothing)
  - [A stale exec-if check can block a widget after its exec-if changed](../issues.md#a-stale-exec-if-check-can-block-a-widget-after-its-exec-if-changed)
  - [A command naming a program shows the program as its script](../issues.md#a-command-naming-a-program-shows-the-program-as-its-script)
- **overlay-modules-07** (2):
  - [Any custom widget reaches the lock screen past its Offer switch](../issues.md#any-custom-widget-reaches-the-lock-screen-past-its-offer-switch)
  - [What a lock screen module may do is a list kept by hand in two docs that disagree](../issues.md#what-a-lock-screen-module-may-do-is-a-list-kept-by-hand-in-two-docs-that-disagree)
- **overlay-modules-08** (0): Done: its three entries were fixed with the OSD's statuses (the OSD's items, config v86), which rewrote the same files.
- **overlay-modules-09** (6):
  - [The Layouts canvas logs null reads as it's torn down](../issues.md#the-layouts-canvas-logs-null-reads-as-its-torn-down)
  - [The monitor prompt's padding is a bare 18 px, and check_sizes misses it](../issues.md#the-monitor-prompts-padding-is-a-bare-18-px-and-check_sizes-misses-it)
  - [A custom Ring element logs an undefined `inside` on load](../issues.md#a-custom-ring-element-logs-an-undefined-inside-on-load)
  - [A custom layout's element rect reads an undefined place](../issues.md#a-custom-layouts-element-rect-reads-an-undefined-place)
  - [CustomElement's six Binding blocks are Qt.binding in its setSource](../issues.md#customelements-six-binding-blocks-are-qtbinding-in-its-setsource)
  - [A custom layout without elements rebuilds its default elements every sample](../issues.md#a-custom-layout-without-elements-rebuilds-its-default-elements-every-sample)
- **overlay-modules-10** (5):
  - [A tray menu logs an undefined menu handle](../issues.md#a-tray-menu-logs-an-undefined-menu-handle)
  - [Tailscale's PeerRow redraws DeviceRow without its buttons](../issues.md#tailscales-peerrow-redraws-devicerow-without-its-buttons)
  - [WifiNetworks' WPA password form repeats WifiJoinForm's](../issues.md#wifinetworks-wpa-password-form-repeats-wifijoinforms)
  - [Login and Password each carry the same required-field report](../issues.md#login-and-password-each-carry-the-same-required-field-report)
  - [WeatherForecast repeats the Weather card's current conditions](../issues.md#weatherforecast-repeats-the-weather-cards-current-conditions)
- **overlay-modules-11** (2): The v71 entry is a rare path: smallest fix.
  - [Hot corners' action list is a hand-kept copy of the keybind one](../issues.md#hot-corners-action-list-is-a-hand-kept-copy-of-the-keybind-one)
  - [A shared file older than v71 resets niri's hot corner](../issues.md#a-shared-file-older-than-v71-resets-niris-hot-corner)
- **overlay-modules-12** (1): Needs the live log at a first sizing; folds into overlay-modules-09 if found first.
  - [A model of size -1 when the overlay grid resizes](../issues.md#a-model-of-size--1-when-the-overlay-grid-resizes)
- **overlay-modules-13** (1):
  - [Compact cards still build their full layout](../issues.md#compact-cards-still-build-their-full-layout)

**features**

- **features-03** (5):
  - [A transient notification toasts blank](../issues.md#a-transient-notification-toasts-blank)
  - [removeOnClick never removes a clicked toast's entry](../issues.md#removeonclick-never-removes-a-clicked-toasts-entry)
  - [The notification list's delegates animate with their own easing](../issues.md#the-notification-lists-delegates-animate-with-their-own-easing)
  - [The history's group and entry delegates repeat one swipe-away mechanism](../issues.md#the-historys-group-and-entry-delegates-repeat-one-swipe-away-mechanism)
  - [clearAll removes each cached image twice, one process per entry](../issues.md#clearall-removes-each-cached-image-twice-one-process-per-entry)
- **features-04** (2):
  - [The dock's menu and drag state outlive the icons they point at](../issues.md#the-docks-menu-and-drag-state-outlive-the-icons-they-point-at)
  - [A dock beside another edge's reserving dock is laid out as if that dock weren't there](../issues.md#a-dock-beside-another-edges-reserving-dock-is-laid-out-as-if-that-dock-werent-there)
- **features-05** (7): The suspend entry gets a Live checks line.
  - [A pomodoro, timer or caffeine end due during a suspend fires up to an hour after waking](../issues.md#a-pomodoro-timer-or-caffeine-end-due-during-a-suspend-fires-up-to-an-hour-after-waking)
  - [Skipping a focus session counts it as finished](../issues.md#skipping-a-focus-session-counts-it-as-finished)
  - [A recent timer chip reads its label back as part of the duration](../issues.md#a-recent-timer-chip-reads-its-label-back-as-part-of-the-duration)
  - [A todo.json deleted while unreadable blocks every save until restart](../issues.md#a-todojson-deleted-while-unreadable-blocks-every-save-until-restart)
  - [PomodoroDial redraws DialControls' ring and buttons](../issues.md#pomodorodial-redraws-dialcontrols-ring-and-buttons)
  - [Focus and Pomodoro build the parts their properties turn off](../issues.md#focus-and-pomodoro-build-the-parts-their-properties-turn-off)
  - [A dropdown in an edge menu card with nothing scrolling gets two rows](../issues.md#a-dropdown-in-an-edge-menu-card-with-nothing-scrolling-gets-two-rows)
- **features-06** (3):
  - [A save conflict reloads nothing, so trying again conflicts again](../issues.md#a-save-conflict-reloads-nothing-so-trying-again-conflicts-again)
  - [Moving a recurring event to another calendar drops its earlier occurrences and exceptions](../issues.md#moving-a-recurring-event-to-another-calendar-drops-its-earlier-occurrences-and-exceptions)
  - [Enter in the editor's title saves again while busy and picks All events while asking](../issues.md#enter-in-the-editors-title-saves-again-while-busy-and-picks-all-events-while-asking)
- **features-07** (3):
  - [A Calendar card on the desktop or in an edge menu takes the page's request](../issues.md#a-calendar-card-on-the-desktop-or-in-an-edge-menu-takes-the-pages-request)
  - [Removing a CalDAV account deletes its password before the draft is saved](../issues.md#removing-a-caldav-account-deletes-its-password-before-the-draft-is-saved)
  - [Event titles from a feed render as styled text and load remote images](../issues.md#event-titles-from-a-feed-render-as-styled-text-and-load-remote-images)
- **features-08** (1): Its two OSD entries (the own set's refresh, the icon thresholds) were fixed with the OSD's statuses.
  - [Idle dimming is forgotten across a shell reload](../issues.md#idle-dimming-is-forgotten-across-a-shell-reload)
- **features-09** (6): The fast-reply entry is a rare path (smallest fix); it and the Anthropic one get Live checks lines.
  - [A fast chat reply can drop the shell's connection](../issues.md#a-fast-chat-reply-can-drop-the-shells-connection)
  - [Replacing the chat's conversation leaves its reply and attachments behind](../issues.md#replacing-the-chats-conversation-leaves-its-reply-and-attachments-behind)
  - [Images dropped together on the chat overwrite each other](../issues.md#images-dropped-together-on-the-chat-overwrite-each-other)
  - [An image sent without text to Anthropic carries a whitespace-only text block](../issues.md#an-image-sent-without-text-to-anthropic-carries-a-whitespace-only-text-block)
  - [Stop is ignored while chat.send still looks up the key](../issues.md#stop-is-ignored-while-chatsend-still-looks-up-the-key)
  - [An attachment's thumbnail pokes past its rounded corners](../issues.md#an-attachments-thumbnail-pokes-past-its-rounded-corners)
- **features-10** (6):
  - [Renaming a note whose new name holds a dot drops its extension and hides it](../issues.md#renaming-a-note-whose-new-name-holds-a-dot-drops-its-extension-and-hides-it)
  - [A folder name holding `#` or `?` opens the wrong folder in the note list](../issues.md#a-folder-name-holding--or--opens-the-wrong-folder-in-the-note-list)
  - [A changed notes folder keeps showing the old folder's note and saves it into the new one](../issues.md#a-changed-notes-folder-keeps-showing-the-old-folders-note-and-saves-it-into-the-new-one)
  - [Typing in a note creates a linked notes folder that doesn't exist](../issues.md#typing-in-a-note-creates-a-linked-notes-folder-that-doesnt-exist)
  - [Two toolbar edits skip the re-parse, so the editor's blocks aren't what parse() gives](../issues.md#two-toolbar-edits-skip-the-re-parse-so-the-editors-blocks-arent-what-parse-gives)
  - [NotesConfig expands ~ by hand where Paths.expandHome does it](../issues.md#notesconfig-expands--by-hand-where-pathsexpandhome-does-it)
- **features-11** (5): The relative-times entry gets a Live checks line.
  - [Two Bluetooth menus share one discovery scan, and one closing stops the other's](../issues.md#two-bluetooth-menus-share-one-discovery-scan-and-one-closing-stops-the-others)
  - [The join form stays incomplete when CA file is picked without a file and the security changed](../issues.md#the-join-form-stays-incomplete-when-ca-file-is-picked-without-a-file-and-the-security-changed)
  - [The VPN list's Tailscale row misreads Tailscale's errors, actions and login](../issues.md#the-vpn-lists-tailscale-row-misreads-tailscales-errors-actions-and-login)
  - [The panel's relative times go stale while Tailscale's state stays the same](../issues.md#the-panels-relative-times-go-stale-while-tailscales-state-stays-the-same)
  - [The Network card shows Tailscale's raw state, untranslated](../issues.md#the-network-card-shows-tailscales-raw-state-untranslated)
- **features-12** (5):
  - [Re-applying a community setup over its edited copy never shows Applied](../issues.md#re-applying-a-community-setup-over-its-edited-copy-never-shows-applied)
  - [IPC community apply does nothing until the catalog was read](../issues.md#ipc-community-apply-does-nothing-until-the-catalog-was-read)
  - [Turning the gallery on while its card is shown leaves it empty](../issues.md#turning-the-gallery-on-while-its-card-is-shown-leaves-it-empty)
  - [community.fetch isn't sent again after a daemon re-exec, and blanks every thumbnail](../issues.md#communityfetch-isnt-sent-again-after-a-daemon-re-exec-and-blanks-every-thumbnail)
  - [The apply's wallpaper rides in a property instead of the callback](../issues.md#the-applys-wallpaper-rides-in-a-property-instead-of-the-callback)
- **features-13** (4):
  - [Switching an open picker between screenshot and recording keeps the first kind's folder and sound](../issues.md#switching-an-open-picker-between-screenshot-and-recording-keeps-the-first-kinds-folder-and-sound)
  - [Clicking an older capture's notification opens the newest capture](../issues.md#clicking-an-older-captures-notification-opens-the-newest-capture)
  - [The screenshot's Edit notification rebuilds sendNotification's actions](../issues.md#the-screenshots-edit-notification-rebuilds-sendnotifications-actions)
  - [ScreenRecord's recording time repeats StopwatchClock.format, and the bar's differs past an hour](../issues.md#screenrecords-recording-time-repeats-stopwatchclockformat-and-the-bars-differs-past-an-hour)
- **features-14** (2): After overlay-modules-04 (same Calculator, Stopwatch, TodoList and Agenda files). Splits by file group if it passes the gate.
  - [Unbounded lists still built in full](../issues.md#unbounded-lists-still-built-in-full)
  - [The chat builds its conversation lists and model picker while hidden](../issues.md#the-chat-builds-its-conversation-lists-and-model-picker-while-hidden)
- **features-15** (1):
  - [A custom clock format without spaces spills past a vertical bar](../issues.md#a-custom-clock-format-without-spaces-spills-past-a-vertical-bar)

### Counts
- Entries: 348 in the list (354 at the answers, less 6 fixed with the OSD's statuses: overlay-modules-01 one, overlay-modules-08 three, features-08 two; 359 at triage, from 360 open outside Deferred and Phase 13 less the one merged duplicate; the answers deferred 4 and removed 1). By the area whose clusters hold them: config 21, platform 27, core-ui-theming 32, compositor 113, bar-popouts 48, overlay-modules 45, features 68. By the area that filed them: config 18, platform 29, core-ui-theming 32, compositor 113, bar-popouts 48, overlay-modules 44, features 70.
- Clusters: 79: 9 deletion, 3 blocker, 48 major, 13 minor-sweep, 5 plan, 1 live-only.
- Product questions: 16, answered 2026-11-01 (5 deferred, 1 removed).
- Checked by a script (2026-11-01, again after the answers): every assign entry outside Deferred and Phase 13 appears exactly once under Entries by cluster, the merged duplicate excepted, and every issues.md link here names an existing heading.
