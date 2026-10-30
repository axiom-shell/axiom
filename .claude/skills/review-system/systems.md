# Systems

The systems `/review-system` knows. `scope.py` reads this file: each `## <name>` entry's **Docs** (under `docs/dev/`, globs allowed) give the code through their `> **Files:**` headers; **Extra** adds files no doc lists (globs allowed; a folder `dir/` means the files directly in it, as in a header); **Mode** is `files` (default), `collection` (many files of one kind: compare them against their rules and each other, read the odd ones out) or `parity` (compare the backends member by member). **Checks** are what's most worth verifying here, beyond the lenses. Anything not listed: `feature:<name>` (`docs/dev/features/<name>.md`), `doc:<path>`, `files:<glob>`.

## compositor
Scope: the neutral compositor layer: the contract, `supports`, layers and their order, config modes, window look.
Docs: compositor/README.md compositor/contract.md compositor/config-modes.md compositor/layer-arrangement.md compositor/window-look.md
Extra: components/methods/CompositorKind.qml backend/internal/compositor/edit/edit.go components/hosts/popout/LayerSlot.qml services/ui/BackdropManager.qml components/surfaces/backdrop/ScreenBackdrop.qml shell/Backdrops.qml
Checks:
- Every consumer goes through `CompositorManager` (neutral shapes, `goToWorkspace`/`focusWindow`); no backend object leaks out of it.
- Every `supports.<key>` read anywhere is one each backend sets (true or false), and every gated feature reads a key rather than a compositor name.
- Nothing writes compositor config unless `supports.configModes`; leaving `included`/`managed` gives the config back.
- Layer order only from `LayerStack.layers`; bars and the border never over fullscreen, nothing maps a Top window in response to fullscreen (a recurring regression).
Seams: every feature reading windows, outputs, workspaces or `supports`.

## hyprland
Scope: the Hyprland backend: services, Lua, config writer, binds merge, claim, monitors, workspaces, switcher, strips, managed takeover.
Docs: hyprland/*.md
Extra: backend/internal/compositor/takeover/kinds.go backend/internal/compositor/binds/hypr.go backend/internal/compositor/binds/hyprlua.go shell/WorkspaceOverlay.qml config/WorkspaceOverlayConfig.qml components/surfaces/switcher/SwitcherTile.qml
Checks:
- Only the `Hyprland*` services import `Quickshell.Hyprland` or send `hl.*` Lua.
- The writer's output is the same as what the runtime layer applies (one table, two renderers), and it never touches the user's own files outside its module.
- Bind merge round-trips: `remove` gives back exactly what was there.
- Special workspaces and fullscreen: layers stay under fullscreen windows.
Seams: CompositorManager; OnboardingManager and GreetdManager (the Hyprland-only features).

## sway
Scope: the sway / SwayFX backend: IPC, state parsing, config writer, claim, binds merge.
Docs: compositor/sway-backend.md
Extra: backend/internal/compositor/takeover/kinds.go backend/internal/compositor/binds/sway.go backend/internal/compositor/userconf/sway.go
Checks:
- Every contract member behaves as the Hyprland one does, or is a declared `supports` gap.
- SwayFX-only features (blur, shadows, corners) are gated on detecting SwayFX, not assumed.
- IPC reconnects after sway reloads; events don't double-subscribe across QML reloads.
Seams: CompositorManager.

## niri
Scope: the niri backend: IPC event stream, state parsing, KDL config writer, claim, binds merge.
Docs: compositor/niri-backend.md
Extra: backend/internal/compositor/takeover/kinds.go backend/internal/compositor/binds/niri.go backend/internal/compositor/userconf/niri.go backend/internal/compositor/kdl/kdl.go
Checks:
- The event stream recovers when niri restarts or the socket drops; state rebuilt, not patched.
- KDL is written and parsed by one module, round-trips the user's own nodes untouched, and is never loaded into the live session from a test.
- Every contract member behaves as the Hyprland one does, or is a declared `supports` gap; known niri gaps (no `layerFrameSync`, no `outputCapture`) are gated, not special-cased by name.
Seams: CompositorManager.

## compositor-parity
Scope: the three backends compared: same contract, same semantics, same edge cases.
Mode: parity
Docs: compositor/contract.md compositor/sway-backend.md compositor/niri-backend.md hyprland/config-modes.md hyprland/bind-merge.md
Extra: services/compositor/HyprlandManager.qml services/compositor/SwayManager.qml services/compositor/NiriManager.qml
Checks:
- Build a table: each contract member and `supports` key × backend. Every cell is implemented the same way, or the difference is a declared `supports` key, or it's a finding.
- Same inputs → same outputs: workspace numbering and naming, focus order, output names and scale, window shapes (class/app id, title, workspace, floating, fullscreen).
- Writers: same settings produce the equivalent config in each; the takeover and the merge share behaviour (`takeover.Kind`, `compositor/actions`) rather than three copies.
- Runtime layers: same layer rules applied, same reaction to fullscreen.
Seams: everything gated on `supports`.

## popouts
Scope: every surface growing out of an edge: bar popouts, edge popouts, submenus, placement, claims, shadows.
Docs: popouts/*.md
Extra: components/hosts/popout/EdgeTrigger.qml components/methods/ScreenEdge.qml config/PopoutsConfig.qml
Checks:
- Geometry only from `SurfaceContext`/`EdgeAttach`; no host works out a rule itself (grep hosts for `vertical`, `location`, edge math).
- Every popout holds a `PopoutClaim`; an open popout never moves.
- Shadows only through `OutsideShadow`.
- Each `SurfaceContext` rule has a `tst_SurfaceContext` row.
Seams: bar widgets (`PopoutAnchor`), edge menus, OSD, dock, launcher.

## bar
Scope: the bar window, container, sections, pills, ends and corners, bar editor.
Docs: bar/*.md
Extra: components/bar/StandaloneBar.qml
Checks:
- Which bar owns a corner and what each end meets is only `BarEnds` (`ends`); no host re-derives it.
- Geometry animates what's drawn, never what's measured.
- Bars never draw over fullscreen; a namespace change remakes the window.
- Every bar position (four edges, vertical, pill, transparent, several bars, border off) has a path.
Seams: widgets, popouts, the screen border.

## bar-widgets
Scope: every bar widget type, against the widget rules.
Mode: collection
Docs: bar/widget-style.md bar/composition.md
Extra: components/bar/widgets/*/*.qml
Checks:
- Sized from `barConfig`, never `Widget.*`; a changing number never resizes a label (`minimumText` for one whose digit count changes).
- Polled data: request from `properties` only, acquire/release paired.
- Popout through `PopoutAnchor` with `EdgeMenusConfig.opensOwnPopout`.
- Each has its schema `oneOf` entry with the required fields; color fields shown only where they apply.
- Odd ones out: a widget doing what a base class or shared piece already does.
Seams: BarContainer, the schema.

## overlay
Scope: overlay pages, the module grid, grow/expand, the Layouts editor.
Docs: overlay/pages-and-grid.md overlay/grid-canvas.md overlay/grow-expand.md overlay/layouts-editor.md core/streamed-building.md
Extra: components/hosts/overlay/OverlayView.qml
Checks:
- Placement only from `GridPlacement`; the editor edits a `ConfigDraft` with selection through `select*()`.
- Only the current page and its neighbours exist, only while the overlay is open.
- Repeater models from config or counts, never live values.
Seams: modules, views, edge menus, desktop.

## modules
Scope: every overlay module (content type), against the module rules.
Mode: collection
Docs: overlay/writing-modules.md overlay/content-roots.md overlay/utility-modules.md
Extra: components/content/*/*.qml
Checks:
- Root is `Card` or `Panel`; min sizes set and `compactContent` below them.
- Acquire in `onCompleted`, release in `onDestruction`; lasting state in a service.
- `x-hosts` lists overlay, edgeMenu, desktop; `lockscreen` only for modules that launch, dispatch and write nothing and show nothing private; greeter modules inert outside the real greeter.
- Text fields set `x-keyboard`.
- Odd ones out: a module drawing what a part in `content/parts/` or `reusable/` already draws.
Seams: overlay pages, edge menus, desktop, lockscreen, greeter, bar popouts.

## custom-widgets
Scope: custom JSON widgets: definitions, the data helper, the service, the bar widget, the module and its elements, the editor page.
Docs: features/custom-widgets.md
Extra: components/content/parts/custom/**/*.qml components/views/CustomWidgets/*.qml config/schema/definitions/custom/*.yaml backend/internal/migrate/steps/v81.go
Checks:
- A Waybar script runs unchanged: its JSON (or text lines), format, format-icons, classes, escape and hide-on-empty read as Waybar reads them (`CustomWidgetData`, its test).
- One script per definition however many surfaces show it (`CustomWidgetsManager` acquires per id through `CommandManager`); nothing runs with no consumer.
- No actions on the lock screen or in previews, nothing at all in the greeter.
- Element Repeaters by count; lists are ListModels updated in place; history rings fixed length.
- The module editor reuses the layouts editor's canvas (`GridCanvas`, `GridDragLayer`, `GridEditor`) rather than growing its own.
Seams: CommandManager and exec streams, the bar editor and module libraries (`CustomWidget:<id>` keys), the layouts editor's canvas, popouts.

## edge-menus
Scope: edge menus, their hosts, editing and submenus.
Docs: edge-menus/*.md
Checks:
- Placement and claims go through the popout system, not their own rules.
- The editor follows the editors pattern.
Seams: bar widgets' `popoutMenu`, popouts.

## config
Scope: config loading, readers, schema and annotations, migrations, drafts and previews, the settings page, saved configs, i18n.
Docs: core/config-manager.md core/config-readers.md core/schema-annotations.md core/editors-pattern.md core/settings-page.md core/saved-configs-sharing.md core/i18n.md
Extra: backend/internal/migrate/steps/steps.go components/methods/LibraryOrder.qml components/methods/ConfigOps.qml components/methods/SettingsSearch.qml config/Apps.qml
Checks:
- Readers have no `??` default fallbacks (they read `ConfigManager.live`; only a saved-config reader like `BarsConfig.savedBars` reads `config`), read only owners and each other.
- No write path except `ConfigManager`/`SettingsManager`; an invalid file never replaces the running config.
- Migrations are idempotent, each has a `tst_Config` case, schema and `currentVersion` agree.
- `x-scope` and `x-takeover` right on every setting that names a monitor, path, account or command, or takes something over.
- Schema keys no reader or UI uses (dead settings), reader members nothing reads.
Seams: every reader user; every editor.

## config-pipeline
Scope: the Go config pipeline's pure core: the ordered JSON tree, the schema (built from YAML, validation), config ops and formats, migrations (format-1 legacy, conversion, format-2 steps).
Docs: core/config-v2.md
Extra: backend/internal/jsonx/ backend/internal/schema/ backend/internal/config/ backend/internal/migrate/convert/ backend/internal/migrate/steps/ backend/internal/share/zz_generated_movedkeys.go
Checks:
- The tree keeps key order, unknown keys and old shapes, and its bytes match the JS reference (`jsonx`, the shared fixtures).
- Nothing hand-copies a key list, default or annotation from the schema; the YAML build rejects what `strict.go` says it does.
- Every format-2 step is idempotent with a Go test; `legacy.js` (format 1) is frozen: read the Go around it, not the JS.
Seams: config (the store, `ConfigManager`, `ConfigOps.qml`); saved configs and sharing.

## services-core
Scope: the services pattern, ConsumerRegistry, commands, state and files, shell targeting, file picker; the polled data services behind modules and widgets (audio, media, battery, system stats, weather, Claude usage, updates).
Docs: core/services-pattern.md core/shell-manager-targeting.md core/file-picker.md
Extra: services/core/ConsumerRegistry.qml services/core/StateManager.qml services/core/FileManager.qml services/ui/ShellManager.qml components/methods/KeyboardLayouts.qml services/system/KeyboardLayoutManager.qml services/system/AudioManager.qml services/system/MediaManager.qml services/system/BatteryManager.qml services/apps/WeatherManager.qml services/apps/ClaudeUsageManager.qml config/BatteryConfig.qml config/WeatherConfig.qml config/ClaudeUsageConfig.qml config/UpdatesConfig.qml backend/internal/sysmon/ backend/internal/media/ backend/internal/weather/ backend/internal/claudeusage/ backend/internal/updates/
Checks:
- Every polled service uses `acquire`/`release` with the Timer gated on `_registry.active`; requests from config only.
- Persisted state written atomically, under XDG paths, never under `Paths.axiomPath`.
- Only `ShellManager.isTarget` answers shortcuts, IPC and OSD; IPC handlers enabled on the target instance only.
Seams: every service.

## ui-kit
Scope: the shared UI pieces: reusable controls, forms, content parts, motion.
Docs: core/shared-ui-pieces.md
Extra: components/reusable/*.qml components/forms/*.qml components/content/parts/*.qml components/methods/IconResolver.qml services/system/AppIconManager.qml config/Widget.qml config/IconsConfig.qml
Mode: collection
Checks:
- Pieces nothing uses, and pieces two of which do the same job.
- Durations from `Appearance.anim*` with `Appearance.easing`; looping animations gated on `Appearance.animations`; radii rule.
- The `StyledTextEntry` write-back contract held by every user.
Seams: all UI.

## theming
Scope: themes, ThemeManager, wallpaper and schedules, night light.
Docs: theming/themes.md theming/wallpaper-and-schedules.md theming/night-light.md
Extra: components/methods/ColorTemperature.qml
Checks:
- Missing theme keys filled from `theme-defaults.json`; config colour names through `Theme.resolveColor`.
- Generated files under XDG paths, written atomically.
- Schedules survive reloads and don't double-fire.
Seams: every colour user; theme integrations.

## theme-integrations
Scope: every app theme integration, against the recipe.
Mode: collection
Docs: theming/theme-integrations.md
Extra: backend/internal/theme/integrations/ backend/internal/theme/integrate.go backend/internal/theme/effects.go backend/internal/hookup/ backend/internal/compositor/edit/hookup.go backend/internal/daemon/hookup.go
Checks:
- Each writes only its own `axiom.*` file; only the hookup's Apply (`hookup.apply`) edits a user's config, on the user's click.
- Each follows the recipe shape (a `Table` entry, a template where it renders one, reloads as `live` effects), has goldens and a schema switch with `x-hookup`.
- Odd ones out: a table entry or effect reimplementing what `tmpl`, `Each` or a shared effect helper does.
Seams: ThemeManager, the settings page.

## blur
Scope: translucency and compositor blur: blur regions, backing windows, openings, shadows; on all three backends.
Mode: parity
Docs: theming/translucency-blur.md theming/blur-window-openings.md popouts/shadows.md
Checks:
- One rule table (`render.SurfaceBlur`) rendered by each backend; no backend-specific list kept by hand.
- Every self-blurring surface sends its region where `supports.blurRegion`, and its shape matches what's drawn (radii, joins, cut-outs).
- Pausing for fullscreen and translucency off both stop blur on every backend.
Seams: every translucent surface.

## security
Scope: the lock screen, idle, polkit, auth, secrets, the power menu.
Docs: features/lockscreen.md features/idle.md features/polkit.md core/secrets.md
Extra: services/session/SessionManager.qml shell/PowerMenu.qml components/surfaces/powermenu/ config/PowerMenuConfig.qml backend/internal/logind/logindtest/
Checks:
- Only `LockManager.lock()` locks; only PAM success unlocks; no IPC path unlocks.
- What the lock screen shows and lets you do: modules with `lockscreen` in `x-hosts` launch, dispatch and write nothing and show nothing private.
- Secrets never in argv, config.json or logs; passwords cleared after use.
- A reload while locked keeps the session locked (known issue on niri: check its status).
Seams: idle, the power menu, the lock screen modules.

## greeter
Scope: the greeter runtime and its installer.
Docs: features/greeter-install.md features/greeter-runtime.md
Extra: backend/internal/greeterinstall/rules/
Checks:
- The greeter reads only the exported bundle (data, never code).
- Every side effect reachable in greeter mode checks `Paths.greeter`.
- The installer is safe to rerun and to undo, and is only tested on a scratch root.
Seams: config export, the lock screen modules (greeter host).

## launcher
Scope: the launcher, its providers and slash commands.
Docs: features/launcher.md features/launcher-providers.md
Extra: shell/AppLauncher.qml config/LauncherConfig.qml
Checks:
- One row shape for every provider.
- `/config` can never edit `Bars` or `Overlay.views`.
- Commands follow the `LauncherCommands` entry shape; every tool page has a `_page` entry.
Seams: tool pages, clipboard, emoji, calculator.

## packaging
Scope: install, packages, self-update, onboarding.
Docs: packaging.md features/self-update.md features/onboarding.md
Extra: install.sh backend/internal/release/fetch/ components/surfaces/onboarding/**/*.qml
Checks:
- install.sh's package table, `Packages.packages` and the PKGBUILDs agree.
- Self-update never applies on a dirty or live repo without the user.
Seams: CI, the AUR, the guardrails (`check_packages.py`).

## daemon
Scope: the axiom binary's core: the daemon and its parts, the RPC protocol and topics, the CLI, supervising the shell, commands, files and paths, the shared Go helpers.
Docs: backend/README.md backend/protocol.md core/memory.md
Extra: backend/cmd/axiom/ backend/internal/cli/ backend/internal/command/ backend/internal/daemon/{dev,exec,files,reexec,tasks}.go backend/internal/{files,fsx,xdg,axerr,buildinfo,logfile,assets,tree,shellcmd,deps,netif,testkit}/ backend/tools/syncassets/ shell/NoParentNotice.qml
Checks:
- The tiers and rules in `backend/AGENTS.md` hold (pure → edge → `daemon` → `cli`; no globals; `axerr` kinds across every boundary); `archtest` enforces what it claims to.
- Every method and topic is in `methodSets` and the generated contract; whole-state pushes are latest-wins; a polled topic runs only while a connection subscribes.
- Every goroutine starts through `tasks.Go` and stops with its context; a re-exec or a shell crash loses no state and leaks no descriptor or child.
- The security rules in `docs/dev/backend/README.md` (sockets, locks, runtime dirs, atomic writes, the child's environment) each have a test.
Seams: every QML service that calls the daemon (`BackendManager`); config (the store); the compositor and feature parts.

## dbus-wayland
Scope: the daemon's own D-Bus and Wayland clients: wire formats, connections, the protocols built on them.
Docs: backend/dbus.md backend/wayland.md
Extra: backend/internal/wayland/wire/wiretest/
Checks:
- Marshalling round-trips every type and signature, and a malformed or hostile message is an error, never a panic or an unbounded allocation.
- Descriptors passed over a socket are closed on every path; sealed memfds stay sealed.
- A dropped bus or compositor connection is noticed and reported, not retried in a tight loop; objects and proxies are released with their owner.
Seams: idle, night light, clipboard, polkit and every feature using them; the daemon.

## guardrails
Scope: the checks, the tests' runners, CI and the agent rules: what stops a bad change before it merges.
Docs: testing.md
Extra: scripts/check_*.py scripts/check_*.sh scripts/check_all.sh scripts/generate.sh scripts/gen_docs.py scripts/ci_summary.py scripts/qml_modules.py scripts/run_tests.sh scripts/lib/qt_paths.sh scripts/dev/*.sh scripts/dev/*.py scripts/qmllint-baseline.json scripts/quickshell-io-allowlist.json .github/workflows/checks.yml .githooks/pre-commit .claude/hooks/guard.py .claude/settings.json tests/scripts/*.py tests/RepoFiles.qml tests/Shared.qml AGENTS.md */AGENTS.md .claude/skills/*/SKILL.md docs/recipes/*.md
Checks:
- Every check in `docs/dev/testing.md` › The checks runs in CI (`checks.yml`) and in `check_all.sh`, with the same arguments; the order lives in one place.
- Each check fails on what its doc says it catches (try a bad input against it), and a check that can't fail is a finding.
- Every baseline only shrinks (qmllint, the allowlist, sizes): growth fails CI, not only a local run.
- The guard covers every rule in AGENTS.md › "Never, while testing", with a test each in `test_guard.py`; a refusal can't be dodged by a trivial rewording (another flag order, `env`, a subshell).
- verify.sh runs what a change touches (its maps from file to test or check are complete), and a skipped step says so rather than printing `verify ok`.
- The rules in AGENTS.md, the skills and the recipes name files, members and steps that still exist and agree with each other.
- CI caches and path filters can't skip a check a change needs.
Seams: every system (each is held by these checks); packaging (`check_packages.py`); the Go checks' own rules in `backend/AGENTS.md`.
