# Developer docs

How every service and surface of axiom works. Each doc opens with the files it covers, the config it reads and related docs, so you can jump to the code or stop reading early; `grep -n '^###' <doc>` gives a doc's outline. Read a feature's doc before changing it and update it when you change how the feature works. One fact has one home: docs link to it rather than restate it. Coding agents: [CLAUDE.md](../../CLAUDE.md).

## Layering

Dependencies point one way: pure helpers (`qml/components/methods/`) at the bottom, then the data owners (`ConfigManager`, `ThemeManager`, `I18n`), the config readers, the services (which own every side effect: processes, dispatches, file writes, polling), and the UI on top. A lower layer never reads a higher one; [services-pattern](core/services-pattern.md) and [config-readers](core/config-readers.md) have the detail. Side effects are moving into the Go daemon: the shell's services run commands, read files and keep state through `CommandManager`, `FileManager` and `StateManager`, which ask the `axiom` binary ([backend](backend/README.md)).

## Where to look

| Task / area | Read |
|---|---|
| **Writing any QML** (JS engine gaps, binding traps) | `docs/dev/core/qml-pitfalls.md` |
| Services, polling, `acquire`/`release` | `docs/dev/core/services-pattern.md` |
| A toggle or one-tap action (tile, OSD icon, command, keybind, hot corner) | `docs/dev/core/actions.md` |
| What axiom changed outside its folders (ledger, undo, `axiom footprint`) | `docs/dev/backend/footprint.md` |
| Taking axiom out of the home and session (`axiom uninstall`, `install.sh --uninstall`) | `docs/dev/backend/uninstall.md` |
| Config loading, writes, drafts, previews, XDG paths | `docs/dev/core/config-manager.md`, `config-readers.md` |
| Schema `x-*` annotations (complete list) | `docs/dev/core/schema-annotations.md` |
| Settings page, saved configs, import/export | `docs/dev/core/settings-page.md`, `saved-configs-sharing.md` |
| A new editor (draft, selection, inspector) | `docs/dev/core/editors-pattern.md` |
| Before drawing any card, row, chip, drag | `docs/dev/core/shared-ui-pieces.md` |
| Bar / popouts, edge surfaces / overlay / menus | `docs/dev/bar/`, `popouts/` (start at `surface-context.md`), `overlay/`, `menus/` |
| Compositor: windows, outputs, workspaces, capabilities, sway/niri | `docs/dev/compositor/` |
| Config modes (detached / included / managed), the config writer | `docs/dev/compositor/config-modes.md` |
| Where the tree is found and installed; dev mode, dev trees, the dev config | `docs/dev/backend/README.md` (What exists now, Dev mode), `docs/dev/packaging.md` |
| What axiom takes out of the session when it stops (the runtime layer, stopped agents, the portal line), the guard | `docs/dev/backend/session-teardown.md` |
| The shell ↔ axiom binary connection (env, socket, methods, pushes) | `docs/dev/backend/protocol.md`; every method and push: `docs/dev/generated/rpc.md` (generated) |
| Hyprland's writer, binds, monitors, workspaces | `docs/dev/hyprland/` |
| Themes, integrations, wallpaper, blur | `docs/dev/theming/` |
| A feature (launcher, lockscreen, greeter, dock, OSD, chat, …) | `docs/dev/features/<feature>.md` |
| Looking at or debugging the live shell; what each check catches | `docs/dev/testing.md` |
| A page or panel slow to open, streaming (`StreamedLoader`), measuring it | `docs/dev/core/streamed-building.md` |
| install.sh, AUR packages, packaged installs | `docs/dev/packaging.md` |
| A setting: meaning, default, readers | `docs/dev/config/<Section>.md` (generated; `grep -rn 'Section.key' docs/dev/config/`) |
| A bar widget / overlay module / view type's settings | `docs/dev/config/{BarWidgets,OverlayModules,OverlayViews}/<Type>.md` (generated) |
| A service's or reader's public API | `docs/dev/generated/api/<Name>.md` (generated) |
| Which file does X | `grep -n '<word>' docs/dev/generated/files.md` (generated; grep it, never read it whole) |
| IPC targets / layer stacking order | `docs/dev/generated/ipc.md`, `layers.md` (generated) |

## Layout

```
qml/              the QML tree quickshell runs (`qs -p <tree>/qml`); `qs.` imports resolve from here
  shell.qml       entrypoint: one top-level Item per surface, plus `_services` (services only reached by IPC)
  greeter.qml     the login screen's entrypoint
  shell/          top-level pieces, one per surface
  components/
    methods/      pure singleton helpers (unit-tested)
    reusable/     generic Styled* widgets, no feature logic (only the plumbing pieces read services: `check_structure`)
    forms/        schema-driven form widgets
    content/      loadable panels by name: overlay module types, bar popouts (base/, parts/)
    hosts/        where content appears: popout/, overlay/, window/ (page windows)
    views/        overlay pages by view type
    bar/          the bar; widgets/ = bar widget types
    surfaces/     standalone windows (launcher, lockscreen, toasts, dock, onboarding, …)
  services/       pragma Singleton managers: state and side effects; core/ compositor/ session/ system/ ui/ apps/ 
  config/         reader singletons; schema/ (the schema's YAML), json/ (the built schema, theme defaults), themes/, i18n/
  assets/         fonts/, icons/
data/             runtime files that aren't QML: greeter/ (session scripts, polkit policy), templates/ (theme integrations), examples/ (example setups)
backend/          the axiom binary (Go)
scripts/          dev tooling only: the checks, generators, scripts/dev/
tests/            qmltestrunner tests, fixtures, tests/scripts/
docs/             user docs; dev/ developer docs, recipes/, screenshots/
packaging/        the AUR packages (install.sh stays at the root)
```

- Imports use the `qs.` namespace (`import qs.services.core`); no qmldir files. Every file starts with `pragma ComponentBehavior: Bound` or `pragma Singleton` (`check_structure`).
- Types are loaded by name (under `qml/components/`): `bar/widgets/<type>/<type>.qml`, `content/<Name>/<Name>.qml`, `views/<type>/<type>.qml`; a new one is the file plus its `schema.yaml` beside it ([config-manager](core/config-manager.md) › The shape of config.json).
- Naming: services `*Manager`, the non-singleton parts beside them named for what they are (`ConfigDraft`, `ConsumerRegistry`, `DeadlineTicker`); readers per section, `Config`-suffixed where the name is a type (`OSDConfig`), and one exposing the saved config says so (`BarsConfig.savedBars`); hosts say what they host (`BarWidgetHost`, `OverlaySlot`); content by module type or popout name; Qt control stand-ins `Styled*`; composites named for what they are. A surface window gets a `Window` suffix when its shell entry shares the name (`qml/shell/PowerMenu` → `PowerMenuWindow`). Root ids are `root`. Bar widget and content names may overlap, but no file may see both.

## Index

### Recipes
- [../recipes/](../recipes/): step-by-step for each recurring change (files to touch, file to copy, gotchas, checks).

### Generated references (`scripts/gen_docs.py`, run by `scripts/generate.sh`; built, never committed)
- [config/](config/README.md): every setting per section: type, default, annotations, description, reader member, files that use it (the daemon's too: `x-compositor`, or its Go reading the key by name). Plus one page per bar widget, overlay module and view type. A setting nobody reads, or a reader member with no user, fails `gen_docs.py`.
- [generated/api.md](generated/api.md): public members of every service and config reader, one page each.
- [generated/files.md](generated/files.md): every QML file with its purpose comment. Long: grep it.
- [generated/ipc.md](generated/ipc.md): every IPC target and its functions.
- [generated/rpc.md](generated/rpc.md): every method, push and call between the shell and the axiom daemon, with their fields and the files on each side.
- [generated/layers.md](generated/layers.md): every layer namespace's `order` and why, from `LayerStack.layers`.

### Installing
- [packaging.md](packaging.md): install.sh (distributions, compositors, `--dry-run`), the AUR packages, what a packaged shell does differently, and `check_packages.py`.

### Testing
- [testing.md](testing.md): how to look at, exercise and debug the running shell safely; the testing sections of every doc.

### backend/: the axiom binary
- [backend](backend/README.md): the Go binary (parent of the shell, owner of the config, the command line): what exists so far, building and checking it, its security rules, and the shared fixtures both sides replay.
- [inputmethod](backend/inputmethod.md): the input method framework (fcitx5, ibus) from the daemon: finding it, following and switching its input method, pushing axiom's list, its options, outside edits, the `inputMethod` topic and `supports.inputMethod`.
- [dbus](backend/dbus.md): the daemon's own D-Bus client (pure Go): connection, calls and signals, descriptors, what uses it.
- [wayland](backend/wayland.md): the daemon's own Wayland connection and what each compositor offers for idle, gamma, clipboard and typing.
- [session-teardown](backend/session-teardown.md): what axiom leaves in the session and takes out when it stops however it stops: the session records, scope, the teardown order, the guard process, heal, the niri portal line.
- [protocol](backend/protocol.md): how the shell and the binary talk: the environment, runtime files, the socket's calls and pushes, a session, topics, guards, and when to bump the protocol (every method and push: [generated/rpc.md](generated/rpc.md)).

### core/: config, services, schema, shared UI
- [services-pattern](core/services-pattern.md): one singleton per domain, acquire/release for anything polled, CommandManager, the other domain services.
- [config-manager](core/config-manager.md): load pipeline, the shape of config.json (format 2, type folders, what the schema builder supplies), write API, `ConfigDraft`, previews.
- [config-readers](core/config-readers.md): the reader singletons, `General.outputs`, `Paths`, `Theme`.
- [schema-annotations](core/schema-annotations.md): the schema as source of truth and the complete list of `x-*` annotations.
- [settings-page](core/settings-page.md): how the schema becomes the settings page (layout, cards, folding, sidebar, search).
- [saved-configs-sharing](core/saved-configs-sharing.md): snapshots, shipped examples, import/export, `x-scope`, `x-takeover`.
- [editors-pattern](core/editors-pattern.md): the shape every editor follows (draft, selection, page, unsaved reminders, drag, inspector).
- [actions](core/actions.md): the one catalogue of the shell's actions (the keybind table plus `ActionsManager`): tiles, OSD icons, launcher commands, buttons, keys and hot corners all run them the same way.
- [shell-manager-targeting](core/shell-manager-targeting.md): cross-cutting UI signals, monitor modes, which screen answers a shortcut, the surface registry (`SurfaceManager`).
- [secrets](core/secrets.md): API keys and passwords (`SecretsManager`).
- [icons](core/icons.md): the bundled Material Symbols font, its catalog and update script, the icon field (`x-control: icon`, `IconManager`) and `check_icons.py`.
- [file-picker](core/file-picker.md): the desktop's file/folder picker (`FilePickerManager`, axiom's `filepicker.pick`), folder settings' Browse button.
- [i18n](core/i18n.md): translation mechanics, language files, `check_i18n.py`.
- [shared-ui-pieces](core/shared-ui-pieces.md): index of reusable widgets and helpers. Check it before drawing anything.
- [streamed-building](core/streamed-building.md): how pages show at once and fill in over frames (`BuildQueueManager`, `StreamedLoader`), what made them slow, and measuring it (`bench_overlay.sh`).
- [memory](core/memory.md): reading the shell's memory (`mem.sh`, `bench_overlay.sh --mem`) in a nested session, and a recorded baseline.
- [qml-pitfalls](core/qml-pitfalls.md): traps of QML, its JS engine and URL-loaded files that have each bitten. Read it before writing QML.

### bar/
- [composition](bar/composition.md): bars from config, widget hosts, layout math, popout anchors, icons, drawn-not-measured motion.
- [widget-style](bar/widget-style.md): widget base classes, sizes, widget style, Auto colors, look groups, Workspaces cells.
- [widget-shapes-runs](bar/widget-shapes-runs.md): background shapes, merged/powerline runs, hit shapes, separators, shadow, accent line.
- [bar-ends-pills](bar/bar-ends-pills.md): what a bar's ends meet, pill bars merging at corners, pill stretch.
- [layering-and-corners](bar/layering-and-corners.md): bars and the screen border sharing an edge, corner ownership, transparent bars, border off.
- [bar-editor](bar/bar-editor.md): the BarEditor page and live reports.
- [style-block](bar/style-block.md): the Bar style block (settings card and editor Style tab), its tiles, presets, and the one file drawing bars.
- [display-styles](bar/display-styles.md): how a widget draws its value (ring, fill, sparkline, ticker, stacked, …), shared with custom widgets.

### popouts/: everything growing out of an edge
- [surface-context](popouts/surface-context.md): what a surface meets at its ends (`SurfaceContext`, `EdgePlacement`), the window model.
- [edge-attach](popouts/edge-attach.md): placement along an edge, walls, nudges, pill growth.
- [registry](popouts/registry.md): `PopoutManager` claims, footprints, ranks, residents.
- [hosts-and-switching](popouts/hosts-and-switching.md): host pieces, bar popout window sizing, switching in place, screen-edge popouts.
- [submenus](popouts/submenus.md): one-level submenus and how they join their parent.
- [shadows](popouts/shadows.md): the shadow every surface casts.
- [pill-and-floating-bars](popouts/pill-and-floating-bars.md): popouts on floating, pill and transparent bars.
- [held-off-edge](popouts/held-off-edge.md): detached islands (edge menus, docks, OSDs) and fullscreen hold.

### overlay/: pages and modules
- [pages-and-grid](overlay/pages-and-grid.md): views, `GridPlacement`, card sizing, loading, the navigator, tool pages.
- [page-windows](overlay/page-windows.md): tool pages popped out into windows of their own (`PageWindowManager`, `x-window`), the box left in the overlay, links and desktop entries.
- [content-roots](overlay/content-roots.md): `content/<Name>/<Name>.qml`, `Card` / `Panel` roots, what hosts pass in.
- [writing-modules](overlay/writing-modules.md): any-size modules, shared parts, data sources, Repeater models, safe live testing.
- [grow-expand](overlay/grow-expand.md): modules growing rows and expanding over the grid.
- [utility-modules](overlay/utility-modules.md): Calculator, Clipboard, Emoji, WorldClocks, Cheatsheet (a command's output is a [custom widget](features/custom-widgets.md)).
- [layouts-editor](overlay/layouts-editor.md): the Layouts page and its edit targets (pages, menus, desktop, lock screen, greeter).
- [grid-canvas](overlay/grid-canvas.md): `GridCanvas`, `GridDragLayer`, `GridEditor` plans and undo.

### menus/
- [overview](menus/overview.md): entry fields, open/pinned state, pin, module hosts.
- [hosts](menus/hosts.md): the edge and strip hosts, the lattice, sync.
- [editing-submenus](menus/editing-submenus.md): editing on the Layouts page, Submenu modules.
- [free-menus](menus/free-menus.md): free menus' own window, where it opens, its claim and layer.

### compositor/
- [README](compositor/README.md): `CompositorManager`, detection, capabilities, gating what a compositor can't do, `FocusGrab`.
- [contract](compositor/contract.md): the neutral shapes and the members a backend provides.
- [sway-backend](compositor/sway-backend.md): the sway backend (SwayManager), the plan for its config writer, and running a nested compositor (`scripts/dev/nested.sh`: sway, niri or Hyprland).
- [niri-backend](compositor/niri-backend.md): the niri backend (NiriManager): its socket, per-output workspaces and strips, and its config writer (files only, validated, the detached wrapper).
- [config-modes](compositor/config-modes.md): `CompositorConfigManager`, detached / included / managed, leaving a mode, the live parts, the config writer contract.
- [window-look](compositor/window-look.md): `WindowLook` (borders, shape, gaps, blur, opacity): `render.Look`, and Hyprland's one `hl.config`.
- [layer-arrangement](compositor/layer-arrangement.md): how compositors arrange and stack layer windows (measured on sway and niri), and how axiom reproduces it.

### hyprland/
- [ipc](hyprland/ipc.md): the request socket (`hypr.request`), Quickshell.Hyprland and `HyprlandManager`, the Hyprland backend; who may talk to Hyprland.
- [config-modes](hyprland/config-modes.md): Hyprland's writer: the Lua layer in each mode, `x-compositor` options.
- [managed-takeover](hyprland/managed-takeover.md): the takeover's claim and release (`backend/internal/compositor/takeover`).
- [bind-merge](hyprland/bind-merge.md): `mergeUserBinds` (managed mode).
- [keybinds](hyprland/keybinds.md): bind actions and dispatchers, the Keybinds page, the key recorder.
- [monitors](hyprland/monitors.md): monitor profiles, the Monitors page, Apply/Keep/Revert.
- [workspaces](hyprland/workspaces.md): workspace layouts, ids, navigation, the bar widget.
- [workspace-strips](hyprland/workspace-strips.md): scrolling-layout strips.
- [window-switcher](hyprland/window-switcher.md): Alt+Tab.

### theming/
- [themes](theming/themes.md): theme loading, families, wallpaper-generated themes, the Themes page.
- [theme-integrations](theming/theme-integrations.md): the daemon's integrations table and writer, hookups, adding an integration.
- [wallpaper-and-schedules](theming/wallpaper-and-schedules.md): wallpaper backends, rotation, light/dark wallpapers and schedule.
- [night-light](theming/night-light.md): the daemon's CTM / gamma, wlsunset on niri, schedule, NightLightControls.
- [translucency-blur](theming/translucency-blur.md): the translucency setting, fills, Hyprland blur rules, per-screen and fullscreen behaviour.
- [blur-window-openings](theming/blur-window-openings.md): the shared blur backing window, shadows in it, strokes opened at joins.

### features/
- [custom-widgets](features/custom-widgets.md): Waybar-style scripts as bar widgets, popouts and modules; definitions, fields, running.
- [hot-corners](features/hot-corners.md): axiom's own hot corners, their actions, windows and layer.
- [launcher](features/launcher.md): rows, placement, routing, `/` commands, `/config`, IPC.
- [launcher-providers](features/launcher-providers.md): calculator, clipboard history, emoji, the files' service.
- [file-search](features/file-search.md): the launcher's files (`~`): the daemon's index, its idle-priority crawl child, watches, stat pass and cache, thumbnails, the rows.
- [lockscreen](features/lockscreen.md): lock modes, the module layout, password, editing and preview.
- [greeter-install](features/greeter-install.md): installing/updating the greetd login screen, status.
- [greeter-runtime](features/greeter-runtime.md): the bundle, session script, greeter mode, `GreetdManager`.
- [desktop](features/desktop.md): modules on the desktop.
- [dock](features/dock.md): docks, pinning, visibility modes, placement.
- [window-rules](features/window-rules.md): the user's window rules: the model (`WindowRules`), validation and its issues, the patterns conditions become, written and live kinds, a window's process and the game detector.
- [osd](features/osd.md): on-screen displays.
- [notifications](features/notifications.md): server, history, toasts, DND.
- [chat](features/chat.md): LLM chat, providers, streaming.
- [notes](features/notes.md): Markdown notes, block editor, browser.
- [calendar](features/calendar.md): CalDAV / .ics / local calendars, sync helper, reminders, calendar parts.
- [todo-pomodoro](features/todo-pomodoro.md): the todo list, the pomodoro timer, the timer & stopwatch and the Focus module.
- [clock-timezones](features/clock-timezones.md): other time zones, Clock module styles.
- [default-apps](features/default-apps.md): Settings › General's Default apps (the mimeapps lists, xdg-terminals.list) and `axiom open`, which everything the shell opens goes through.
- [datetime](features/datetime.md): Settings › System › Date & time: the machine's time zone, network time and clock (timedated), and the formats every clock and date follows.
- [screenshots-recording](features/screenshots-recording.md): screenshots, recording, the picker.
- [brightness](features/brightness.md): backlight / DDC, the module, OSD bars.
- [networking-bluetooth](features/networking-bluetooth.md): Wi-Fi, wired, Bluetooth.
- [vpn](features/vpn.md): NetworkManager's VPNs and Tailscale in one list, the secret agent.
- [input-sources](features/input-sources.md): keyboard layouts and input method engines as one list (fcitx5, ibus): the widget and popout, the module, the OSD, switching, what the framework is given.
- [drives](features/drives.md): removable drives through udisks2: the plug-in notification or mount, open, unlock, eject.
- [tailscale](features/tailscale.md): the `tailscale` topic, Connect / Disconnect, the widget, popout and module.
- [markets](features/markets.md): stock and crypto prices (the `markets` topic: Yahoo Finance and CoinGecko), the watchlist, holdings and alerts, the widget, popout and module.
- [idle](features/idle.md): hypridle and idle inhibit.
- [lock-keys](features/lock-keys.md): Caps Lock / Num Lock / Scroll Lock from the keyboard LEDs (the `lockKeys` topic), the password fields' warning, the LockKeys widget.
- [polkit](features/polkit.md): the polkit agent.
- [prompts](features/prompts.md): the one shared prompt (`PromptManager`, `PromptWindow`) for requests the system starts: polkit, Bluetooth pairing.
- [screen-sharing](features/screen-sharing.md): axiom's screen-share picker for every compositor's portal (xdph's custom picker, xdpw's chooser, axiom's own ScreenCast portal under niri), repeats answered without it, the hookup.
- [onboarding](features/onboarding.md): the first-run onboarder.
- [self-update](features/self-update.md): axiom updating its own clone.
- [account](features/account.md): Settings › General's Account card: the user's picture, names and password (AccountsService, `~/.face`, passwd in a pty).
- [system-info](features/system-info.md): Settings › System's first card (the machine and this axiom, Copy system info, renaming through hostnamed) and its Optional packages.
- [community-setups](features/community-setups.md): the community setups gallery, its catalog, downloading and applying one.
