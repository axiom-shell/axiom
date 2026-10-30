# popouts
reviewed: c4fc397 2026-10-30  (full)

The registry, switching, stretch choreography and pure helpers hold and are tested. What's open:
- Edge and floating popouts ignore their focus grab's `cleared`, so floating edge menus and the launcher don't close on an outside click (a Blocker).
- EdgePopout leaves its bar input unlatched and works out two geometry rules itself.
- The outline folds at large radii.
- Older content panels (NowPlaying, Updates, the workspace popouts, the tray parts) have drifted from the shared pieces.

The next review should reread these fixes, and the content panels skipped here.

## Open findings
- Blocker: [Edge and floating popouts never close when their focus grab clears](../../docs/dev/issues.md#edge-and-floating-popouts-never-close-when-their-focus-grab-clears)
- Major: [An open edge popout's layer and namespace still follow its edge's bar](../../docs/dev/issues.md#an-open-edge-popouts-layer-and-namespace-still-follow-its-edges-bar)
- Major: [EdgePopout works out its attach edge and slide distance itself](../../docs/dev/issues.md#edgepopout-works-out-its-attach-edge-and-slide-distance-itself)
- Major: [A large corner radius folds a pill's or shallow box's outline back on itself](../../docs/dev/issues.md#a-large-corner-radius-folds-a-pills-or-shallow-boxs-outline-back-on-itself)
- Major: [A tray submenu longer than the screen runs off it](../../docs/dev/issues.md#a-tray-submenu-longer-than-the-screen-runs-off-it)
- Major: [The Updates popout's package list is frozen at opening](../../docs/dev/issues.md#the-updates-popouts-package-list-is-frozen-at-opening)
- Major: [NowPlaying builds its strip layout and a second transport hidden in every mode](../../docs/dev/issues.md#nowplaying-builds-its-strip-layout-and-a-second-transport-hidden-in-every-mode)
- Cleanup: [popout_matrix.py crashes on the current config and nothing runs it](../../docs/dev/issues.md#popout_matrixpy-crashes-on-the-current-config-and-nothing-runs-it)
- Cleanup: [PopoutWrapperBase's aboutToDismiss signal has no listener](../../docs/dev/issues.md#popoutwrapperbases-abouttodismiss-signal-has-no-listener)
- Cleanup: [Three EdgePopout members nothing reads](../../docs/dev/issues.md#three-edgepopout-members-nothing-reads)
- Cleanup: [PopoutGeometry handles a phase and a submenu pair the registry never produces](../../docs/dev/issues.md#popoutgeometry-handles-a-phase-and-a-submenu-pair-the-registry-never-produces)
- Cleanup: [PillBarJoin's available repeats what joined already says](../../docs/dev/issues.md#pillbarjoins-available-repeats-what-joined-already-says)
- Cleanup: [Geometry members nothing reads](../../docs/dev/issues.md#geometry-members-nothing-reads)
- Cleanup: [SurfaceContext.layout's pill and merged results have no test row](../../docs/dev/issues.md#surfacecontextlayouts-pill-and-merged-results-have-no-test-row)
- Cleanup: [The tray menu's isVertical and barConfig are never read](../../docs/dev/issues.md#the-tray-menus-isvertical-and-barconfig-are-never-read)
- Cleanup: [Both tray menu lists override the same width cap](../../docs/dev/issues.md#both-tray-menu-lists-override-the-same-width-cap)
- Cleanup: [The tray menu draws its own separator](../../docs/dev/issues.md#the-tray-menu-draws-its-own-separator)
- Cleanup: [The two workspace popouts share 28 lines of payload and colour properties](../../docs/dev/issues.md#the-two-workspace-popouts-share-28-lines-of-payload-and-colour-properties)
- Cleanup: [Small improvements to WorkspaceGrid](../../docs/dev/issues.md#small-improvements-to-workspacegrid)
- Outside: [The dock's footprint assumes fillets at both ends](../../docs/dev/issues.md#the-docks-footprint-assumes-fillets-at-both-ends)

Unrecorded (Minor):
- **Hovering a plain tray entry closes a submenu that isn't open:** `components/content/SystemTray/SystemTray.qml:53` calls `closePopout()` with no submenu open, which delays the next submenu by the close animation. Fix: `if (isClosing || !occupied) return;` in `PopoutWrapperBase.closePopout`.
- **Small improvements to Updates:** the popout says "up to date" during the first check (`Updates.qml:155`, use ModuleHeader + EmptyState), and its width is unbounded (cap at `Widget.px(480)`).
- **The Media popout changes height when a player comes or goes:** `NowPlaying.qml:319`; give the empty state the player layout's height.
- **A system graphs card graphs a GPU or CPU temperature the machine can't report:** `SystemGraphs.qml:24`; filter on `SystemManager.hasGpu`/`hasCpuTemp`.
- **The recipe's copy-me panel hand-rolls its header:** `WeatherForecast.qml:23` and `docs/recipes/bar-popout.md`; use `ModuleHeader`.
- **Stale lines in the popouts docs:** hosts-and-switching.md (windowFrom/To, spareAcross vs wholeDepth, keyboard focus, toast stack), registry.md (toast claim), submenus.md (edge popout stretch, cascade's home, SubmenuSide members, MenuSubmenu path), shadows.md ("unbacked are opaque"), edge-attach.md ("every host through EdgePlacement"), and the `config/PopoutsConfig.qml` header.

## Contract
These hold:
- **Claims:** holders are BarPopouts, EdgePopout, FloatingPopout, SubPopout, DockWindow and ToastStack, with keys matching the doc. Edge and floating claims wait on `LayerOrigin.settled` (400 ms timeout). A stale release is ignored by identity.
- **Resolve:** ranks, exemptions, yield/resume without ping-pong, `closeOn` and footprint re-resolve all match PopoutGeometry and its tests.
- **Never moves:** a bar popout's `anchorRect` and `underBar` are latched. EdgePopout's overlay and fullscreen inputs are latched, but not its bar input (open Major).
- **Switching:** the latest payload wins; a reopen during a close switches or waits; a bad `popoutName` never maps; mapping waits on `_payloadApplied` after `_layOut`; the parked cursor arms only on the anchor's hover loss.
- **Geometry:** from SurfaceContext/EdgeAttach, with `supports` entering only there and in `_slideLead`, except EdgePopout's `attachBase`/`slideDistance` (open Major).
- **Shadows:** only via OutsideShadow, plus FloatingPopout's documented copy.
- **Tests:** every SurfaceContext function is tested (63 rows) except `layout`'s pill and merged results. SurfaceOutline has 21 rows; tst_BarLayout covers every function the docs cite.
- **Submenus:** anchors measured at rest; switching in place gates its Glides on `_updateSettled`; the cascade and SubmenuHost's stretch timing hold; the setRequest maps are per part.
- **Outlines:** radius 0 and stroke 0 close; the detached corners are right on four edges.
- **Log:** no popout warnings in the live log.

## Coverage
- **Read deeply:** every host in components/hosts/popout/ (AttachedSurface and SurfaceOutline whole); PopoutManager, PopoutGeometry, BarPanel, shell/OSD, PopoutsConfig, services/compositor/FocusGrab; EdgeAttach 50-300, SurfaceContext's main functions, ScreenEdgeManager 36-208; BarContainer's request and stretch parts, BarLayout 268-542; Submenu/MenuSubmenu, content/SystemTray and parts/Tray*; the content panels untouched since 2026-10-24 (NowPlaying, SystemGraphs, Updates, WorkspaceStrips, WorkspaceGrid, WeatherForecast, Pomodoro); scripts/dev/popout_matrix.py.
- **Outlined:** EdgeAttach's `_onPill`, SurfaceContext's `endKind`/`opening`/`submenuJoin`, ScreenEdge, the rest of BarContainer, the tests by grep, and the newer panels (Stopwatch, VpnConnections, BluetoothDevices).
- **Skipped:** Calendar, AudioMixer, Notifications, Tailscale, WifiNetworks, Todo, Caffeine, ClaudeUsage, CustomWidget (reworked 2026-10-26 to 10-30). A next review should read the ones then untouched.

## History
- 2026-10-20 full: 6 findings (2 major, 2 cleanups, 2 minor); all six fixed (uncommitted at the time). One out-of-system problem recorded in issues.md (dangling screen object).
- 2026-10-30 full (deep): 26 findings (1 blocker, 6 major, 12 cleanups, 6 minor) plus 1 outside the system; Blocker, Major, Cleanups and Outside recorded, Minor left open.
