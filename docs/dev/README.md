# Developer docs

How every service and surface of axiom works. The rules are in [AGENTS.md](../../AGENTS.md); these docs hold the mechanics. Each doc opens with the files it covers, the config it reads and related docs, so you can jump to the code or stop reading early. `grep -n '^###' <doc>` gives its outline.

Local rules for a directory are in its own `AGENTS.md` (`components/bar/`, `components/bar/widgets/`, `components/content/`, `components/views/`, `components/methods/`, `components/hosts/popout/`, `services/`, `config/`, `scripts/`).

Read the doc for a feature before changing it, and update it when you change how the feature works. One fact has one home: link to it rather than restating it.

## Layering

Dependencies point one way, methods → data owners → readers → services → UI: [AGENTS.md › Layering](../../AGENTS.md).

## Index

### Recipes
- [../recipes/](../recipes/): step-by-step for each recurring change (files to touch, file to copy, gotchas, checks). Wrapped as skills in `.claude/skills/`.

### Generated references (`scripts/gen_docs.py`; never edit by hand)
- [config/](config/README.md): every setting per section: type, default, annotations, description, reader member, files that use it. Plus one page per bar widget, overlay module and view type.
- [generated/api.md](generated/api.md): public members of every service and config reader, one page each.
- [generated/files.md](generated/files.md): every QML file with its purpose comment. Long: grep it.
- [generated/ipc.md](generated/ipc.md): every IPC target and its functions.
- [generated/rpc.md](generated/rpc.md): every method, push and call between the shell and the axiom daemon, with the files on each side.
- [generated/layers.md](generated/layers.md): every layer namespace's `order` and why, from `LayerStack.layers`.

### Known issues
- [issues.md](issues.md): coding agents' working list of problems found in the code but not fixed yet (add one when you find something out of scope; remove it with the fix). Not where people report or look up problems: that's GitHub issues, which agents never open.

### Installing
- [packaging.md](packaging.md): install.sh (distributions, compositors, `--dry-run`), the AUR packages, what a packaged shell does differently, and `check_packages.py`.

### Testing
- [testing.md](testing.md): how to look at, exercise and debug the running shell safely; the testing sections of every doc.

### backend/: the axiom binary
- [backend](backend/README.md): the Go binary (parent of the shell, owner of the config, the command line): what exists so far, building and checking it, its security rules, and the shared fixtures both sides replay.
- [roadmap](backend/roadmap.md): the staged plan for moving the services' side effects (processes, files, sockets, HTTP, polling) into the binary: the end state, the rules for each move, and each stage's status.
- [protocol](backend/protocol.md): how the shell and the binary talk: the environment, runtime files, the socket's calls and pushes, a session, topics, guards, and when to bump the protocol (every method and push: [generated/rpc.md](generated/rpc.md)).

### core/: config, services, schema, shared UI
- [services-pattern](core/services-pattern.md): one singleton per domain, acquire/release for anything polled, CommandManager, the other domain services.
- [config-manager](core/config-manager.md): load pipeline, write API, `ConfigDraft`, previews.
- [config-readers](core/config-readers.md): the reader singletons, `General.outputs`, `Paths`, `Theme`.
- [schema-annotations](core/schema-annotations.md): the schema as source of truth and the complete list of `x-*` annotations.
- [settings-page](core/settings-page.md): how the schema becomes the settings page (layout, cards, folding, sidebar, search).
- [saved-configs-sharing](core/saved-configs-sharing.md): snapshots, shipped examples, import/export, `x-scope`, `x-takeover`.
- [editors-pattern](core/editors-pattern.md): the shape every editor follows (draft, selection, page, unsaved reminders, drag, inspector).
- [shell-manager-targeting](core/shell-manager-targeting.md): cross-cutting UI signals, monitor modes, which screen answers a shortcut.
- [secrets](core/secrets.md): API keys and passwords (`SecretsManager`).
- [file-picker](core/file-picker.md): the desktop's file/folder picker (`FilePickerManager`, `pick_path.py`), folder settings' Browse button.
- [i18n](core/i18n.md): translation mechanics, language files, `check_i18n.py`.
- [shared-ui-pieces](core/shared-ui-pieces.md): index of reusable widgets and helpers. Check it before drawing anything.
- [streamed-building](core/streamed-building.md): how pages show at once and fill in over frames (`BuildQueueManager`, `StreamedLoader`), what made them slow, and measuring it (`bench_overlay.sh`).
- [qml-pitfalls](core/qml-pitfalls.md): traps of QML, its JS engine and URL-loaded files that have each bitten. Read it before writing QML.

### bar/
- [composition](bar/composition.md): bars from config, widget hosts, layout math, popout anchors, icons, drawn-not-measured motion.
- [widget-style](bar/widget-style.md): widget base classes, sizes, widget style, Auto colors, look groups, Workspaces cells.
- [widget-shapes-runs](bar/widget-shapes-runs.md): background shapes, merged/powerline runs, hit shapes, separators, shadow, accent line.
- [bar-ends-pills](bar/bar-ends-pills.md): what a bar's ends meet, pill bars merging at corners, pill stretch.
- [layering-and-corners](bar/layering-and-corners.md): bars and the screen border sharing an edge, corner ownership, transparent bars, border off.
- [bar-editor](bar/bar-editor.md): the BarEditor page and live reports.

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
- [content-roots](overlay/content-roots.md): `content/<Name>/<Name>.qml`, `Card` / `Panel` roots, what hosts pass in.
- [writing-modules](overlay/writing-modules.md): any-size modules, shared parts, data sources, Repeater models, safe live testing.
- [grow-expand](overlay/grow-expand.md): modules growing rows and expanding over the grid.
- [utility-modules](overlay/utility-modules.md): Calculator, Clipboard, Emoji, WorldClocks, CommandOutput, Cheatsheet.
- [layouts-editor](overlay/layouts-editor.md): the Layouts page and its edit targets (pages, menus, desktop, lock screen, greeter).
- [grid-canvas](overlay/grid-canvas.md): `GridCanvas`, `GridDragLayer`, `GridEditor` plans and undo.

### edge-menus/
- [overview](edge-menus/overview.md): entry fields, open/pinned state, pin, module hosts.
- [hosts](edge-menus/hosts.md): floating and integrated hosts, the lattice, sync.
- [editing-submenus](edge-menus/editing-submenus.md): editing on the Layouts page, Submenu modules.

### compositor/
- [README](compositor/README.md): `CompositorManager`, detection, capabilities, gating what a compositor can't do, `FocusGrab`.
- [contract](compositor/contract.md): the neutral shapes and the members a backend provides.
- [sway-backend](compositor/sway-backend.md): the sway backend (SwayManager), the plan for its config writer, and running a nested compositor (`scripts/dev/nested.sh`: sway, niri or Hyprland).
- [niri-backend](compositor/niri-backend.md): the niri backend (NiriManager): its socket, per-output workspaces and strips, and its config writer (files only, validated, the detached wrapper).
- [config-modes](compositor/config-modes.md): `CompositorConfigManager`, detached / included / managed, leaving a mode, the live parts, the config writer contract.
- [window-look](compositor/window-look.md): `WindowLook` (borders, shape, gaps, blur, opacity): `CompositorLayer.look`, and Hyprland's one `hl.config`.
- [layer-arrangement](compositor/layer-arrangement.md): how compositors arrange and stack layer windows (measured on sway and niri), and how axiom reproduces it.

### hyprland/
- [ipc](hyprland/ipc.md): `HyprlandIpcManager` (the request socket), Quickshell.Hyprland and `HyprlandManager`, the Hyprland backend; who may talk to Hyprland.
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
- [theme-integrations](theming/theme-integrations.md): `theme_<key>.sh` scripts, hookups, adding an integration.
- [wallpaper-and-schedules](theming/wallpaper-and-schedules.md): wallpaper backends, rotation, light/dark wallpapers and schedule.
- [night-light](theming/night-light.md): hyprsunset / wlsunset, schedule, NightLightControls.
- [translucency-blur](theming/translucency-blur.md): the translucency setting, fills, Hyprland blur rules, per-screen and fullscreen behaviour.
- [blur-window-openings](theming/blur-window-openings.md): the shared blur backing window, shadows in it, strokes opened at joins.

### features/
- [launcher](features/launcher.md): rows, placement, routing, `/` commands, `/config`, IPC.
- [launcher-providers](features/launcher-providers.md): calculator, clipboard history, emoji.
- [lockscreen](features/lockscreen.md): lock modes, the module layout, password, editing and preview.
- [greeter-install](features/greeter-install.md): installing/updating the greetd login screen, status.
- [greeter-runtime](features/greeter-runtime.md): the bundle, session script, greeter mode, `GreetdManager`.
- [desktop](features/desktop.md): modules on the desktop.
- [dock](features/dock.md): docks, pinning, visibility modes, placement.
- [osd](features/osd.md): on-screen displays.
- [notifications](features/notifications.md): server, history, toasts, DND.
- [chat](features/chat.md): LLM chat, providers, streaming.
- [notes](features/notes.md): Markdown notes, block editor, browser.
- [calendar](features/calendar.md): CalDAV / .ics / local calendars, sync helper, reminders, calendar parts.
- [todo-pomodoro](features/todo-pomodoro.md): the todo list, the pomodoro timer, the timer & stopwatch and the Focus module.
- [clock-timezones](features/clock-timezones.md): other time zones, Clock module styles.
- [screenshots-recording](features/screenshots-recording.md): screenshots, recording, the picker.
- [brightness](features/brightness.md): backlight / DDC, the module, OSD bars.
- [networking-bluetooth](features/networking-bluetooth.md): Wi-Fi, wired, Bluetooth.
- [idle](features/idle.md): hypridle and idle inhibit.
- [polkit](features/polkit.md): the polkit agent.
- [onboarding](features/onboarding.md): the first-run onboarder.
- [self-update](features/self-update.md): axiom updating its own clone.
- [community-setups](features/community-setups.md): the community setups gallery, its catalog, downloading and applying one.
