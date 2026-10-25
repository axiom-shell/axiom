# AGENTS.md

The rules for working on axiom, for contributors and coding agents alike (`CLAUDE.md` imports this file).

## What this is

A [Quickshell](https://quickshell.org) desktop environment in QML for Wayland compositors (Hyprland 0.55+ with its Lua config, niri 26.04+, sway 1.12+): bar, notifications, lockscreen, launcher, overlay pages, edge menus, docks, OSD, power menu, workspace overview, screen border. No build step: `qs` interprets the QML at runtime.

This file holds only rules. **How each service and surface works is in `docs/dev/`** (index: `docs/dev/README.md`), one short doc per topic opening with its files, config and related docs. Read the relevant doc before changing a feature; update it when you change how the feature works. Directories with their own `AGENTS.md` add local rules.

## Where to look

**Adding something of a known kind?** Follow its recipe in `docs/recipes/` (also skills in `.claude/skills/`): `bar-widget`, `bar-popout`, `overlay-module`, `overlay-view`, `settings-card`, `launcher-command`, `setting`, `config-section`, `migration`, `service`, `theme-integration`, `methods-helper`, `compositor-backend`.

| Task / area | Read |
|---|---|
| **Writing any QML** (JS engine gaps, binding traps) | `docs/dev/core/qml-pitfalls.md` |
| Services, polling, `acquire`/`release` | `docs/dev/core/services-pattern.md` |
| Config loading, writes, drafts, previews, XDG paths | `docs/dev/core/config-manager.md`, `config-readers.md` |
| Schema `x-*` annotations (complete list) | `docs/dev/core/schema-annotations.md` |
| Settings page, saved configs, import/export | `docs/dev/core/settings-page.md`, `saved-configs-sharing.md` |
| A new editor (draft, selection, inspector) | `docs/dev/core/editors-pattern.md` |
| Before drawing any card, row, chip, drag | `docs/dev/core/shared-ui-pieces.md` |
| Bar / popouts, edge surfaces / overlay / edge menus | `docs/dev/bar/`, `popouts/` (start at `surface-context.md`), `overlay/`, `edge-menus/` |
| Compositor: windows, outputs, workspaces, capabilities, sway/niri | `docs/dev/compositor/` |
| Config modes (detached / included / managed), the config writer | `docs/dev/compositor/config-modes.md` |
| Moving a service's side effects into the axiom binary (the staged plan) | `docs/dev/backend/roadmap.md`; what's left: `scripts/quickshell-io-allowlist.json` |
| The shell ↔ axiom binary connection (env, socket, methods, pushes) | `docs/dev/backend/protocol.md`; every method and push: `docs/dev/generated/rpc.md` (generated) |
| Hyprland's writer, binds, monitors, workspaces | `docs/dev/hyprland/` |
| Themes, integrations, wallpaper, blur | `docs/dev/theming/` |
| A feature (launcher, lockscreen, greeter, dock, OSD, chat, …) | `docs/dev/features/<feature>.md` |
| Looking at or debugging the live shell | `docs/dev/testing.md` |
| A page or panel slow to open, streaming (`StreamedLoader`), measuring it | `docs/dev/core/streamed-building.md` |
| install.sh, AUR packages, packaged installs | `docs/dev/packaging.md` |
| Known unfixed problems (check before working in an area) | `docs/dev/issues.md` |
| A setting: meaning, default, readers | `docs/dev/config/<Section>.md` (generated; `grep -rn 'Section.key' docs/dev/config/`) |
| A bar widget / overlay module / view type's settings | `docs/dev/config/{BarWidgets,OverlayModules,OverlayViews}/<Type>.md` (generated) |
| A service's or reader's public API | `docs/dev/generated/api/<Name>.md` (generated) |
| Which file does X | `grep -n '<word>' docs/dev/generated/files.md` (generated; grep it, never read it whole) |
| IPC targets / layer stacking order | `docs/dev/generated/ipc.md`, `layers.md` (generated) |

**Found a problem outside the task?** Don't fix it unasked and don't only mention it: add an entry to `docs/dev/issues.md` (format at its top) and tell the user. Quote a log warning's message in backticks under **What** so `verify.sh` marks it `(known: …)`. Remove the entry in the change that fixes it. Never open a GitHub issue; the maintainer moves entries there.

## Running / reloading

- **After any change run `scripts/dev/verify.sh`** until it prints `verify ok` (formats, checks, regenerates docs, runs affected tests, shows the log with known issues marked, lists the docs describing what you changed: read them if behaviour changed; `--all` runs every CI check). **To look at something**: `scripts/dev/shot.sh page <ViewType>` / `launcher [text]` / `ipc <target> <open> [close]` prints a screenshot's path.
- The shell runs under `axiom run` (its parent daemon, which owns config.json): never start, stop or restart either from this session. Saving a loaded QML file hot-reloads it, but qs watches by inode: after `sed -i` or `git checkout`, force a reload (`docs/dev/testing.md`). The schema is read once at the daemon's start unless it runs with `--dev`: a YAML change reaches the live shell only after the user restarts axiom (on a rebuilt binary when the schema changed). A second axiom runs only nested: `scripts/dev/nested.sh <sway|niri|hyprland>`.
- **Logs**: `scripts/log.sh` (since the last reload; `--debug` adds `console.log`, `--all`, `-f`, `-g PATTERN`). A clean reload is just `Reloading configuration...` + `Configuration Loaded`; stdout/journalctl show nothing. `console.log` for tracing, `console.warn` only for real problems.
- A settings category has no IPC: add a temporary `IpcHandler` calling `SettingsManager.openCategory(name)` to `shell.qml` (never inside a singleton) and revert it.
- `~/.config/axiom/config.json` belongs to the settings UI but may be edited to test. An invalid file never replaces the running config (`savesBlocked` refuses saves until it's fixed).
- File reads go through `FileManager.read`; `XMLHttpRequest` only for HTTP. Rewrite watched JSON (`config/i18n/*.json`, config.json) atomically (temp file + rename).

## Never, while testing

Enforced by `.claude/hooks/guard.py` (PreToolUse hook plus `permissions.deny` in `.claude/settings.json`; tests: `tests/scripts/test_guard.py`). A refusal names the rule: don't work around it, ask the user. A new rule here gets one there.

- Lock the built-in locker (only the user can type the password): test `LockSurface` in a hidden window.
- Simulate cursor movement to verify UI: read logs and reason through bindings.
- Switch the real compositor config (`Compositor.mode`) into or out of `managed`, or out of `included` (test `axiom compositor claim|release` / `binds remove` on scratch dirs); allow a takeover (`CompositorConfigManager.allowTakeover`, the card's Allow); Keep a monitor layout; `apply` a self-update on the live repo; delete the real config.json (use `ipc call onboarding goTo <n>`); enable `Idle` on the live config without asking (it replaces the user's hypridle).
- Make the live niri session quit, load another config or change outputs (`niri msg action quit` / `load-config-file` / `output`): only a nested one's `NIRI_SOCKET`.
- Apply a theme integration's hookup to the real configs: run `integration_hookup.py` with a scratch `HOME`/`XDG_CONFIG_HOME`.
- Install, update or remove the greeter for real, or restart greetd (it ends the session). Test `scripts/greeter/greeter_install.sh` with a scratch `AXIOM_GREETER_ROOT`; view the greeter with `AXIOM_GREETER_WINDOWED=1 AXIOM_COMPOSITOR=none axiom greeter --tree "$PWD" --dir <scratch>` (a scratch `XDG_RUNTIME_DIR` too, `WAYLAND_DISPLAY` as an absolute path; stop only that instance).
- Run, quit, restart or re-exec the live `axiom` daemon (`axiom run|quit|restart`, `axiom daemon stop|restart|reexec`), or switch its dev mode (`axiom dev on|off|rebuild`; `status` is fine), lock through it (`axiom lock`, `axiom ipc lockscreen …`), or pass `--takeover` against the live config: point it at a scratch instance instead (`XDG_RUNTIME_DIR=<scratch>`, `--socket`, `--config-dir`). A test lock screen's fallback must never be `loginctl lock-session`, which locks the real session.
- Open a GitHub issue (`gh issue create`, or `gh api` posting one).

## Checks

All run in CI; `scripts/dev/verify.sh --all` (= `scripts/check_all.sh`) runs every one. None runs the shell, so still read the log. What they leave to you:
- `scripts/check_structure.py`: run after adding, renaming or moving QML files.
- `scripts/run_tests.sh [Name…]` (`tests/tst_<Name>.qml`; schema defaults are `tst_Config`): add a case when changing a methods helper. A migration step's tests are Go (`scripts/check_go.sh`).
- `scripts/check_qmllint.py` fails on warnings not in `scripts/qmllint-baseline.json`: fix new ones. `--update-baseline` only for Quickshell type-info gaps or baselined warnings gone.
- **Agents never translate**, however easy it looks, and never run `scripts/check_i18n.py --fill`/`--prune`: the pre-commit hook adds new keys empty (shown in English) to every `config/i18n/<code>.json` and drops unused ones. `config/i18n/template/language.json` is generated. Edit i18n files only through the checker's format (2-space JSON; `--format` fixes it).
- `scripts/check_docs.py` fails on a hand-written doc citing a path or `Singleton.member` that's gone (fix the doc with the code), and on an `x-*` annotation missing from `docs/dev/core/schema-annotations.md`.
- `scripts/check_go.sh`: the Go checks for `backend/` (`--fix` regenerates and formats); rules in `backend/AGENTS.md`.
- **Built, never committed** (`.gitignore`; `scripts/generate.sh` builds them when stale, and verify.sh, check_all.sh, check_go.sh and CI run it first; a fresh clone runs it once): `config/json/config.schema.json` (from `config/schema/`), the binary's embedded copies `backend/internal/assets/data/`, and with `--fixtures` the shared fixtures `tests/fixtures/shared/` (recorded from the JS helpers; needs qmltestrunner and the whole git history).
- `scripts/check_packages.py`: a new dependency goes in install.sh's table, `Packages.packages` and the AUR PKGBUILDs (`docs/dev/packaging.md`).
- Generated, never edited by hand: those, `config/themes/template/theme.json` (`scripts/gen_theme_template.py`), `docs/dev/config/` and `docs/dev/generated/` (`scripts/gen_docs.py`; CI fails when stale; verify.sh warns if the hook isn't set up: `git config core.hooksPath .githooks`).
- `scripts/check_doc_drift.py` (warnings) lists docs whose `Files:` changed in 5+ commits since the doc did: reread one against the code before relying on it, and touch it to reset the count.

## Formatting

- verify.sh formats changed QML in place (Qt 6's qmlformat, `.qmlformat.ini`). Never `qmlformat -i` (replaces the inode; the `qmlformat` on PATH is Qt5's and fails silently).
- Each QML file has a short purpose comment above its root object (feeds `docs/dev/generated/files.md`).
- A config read grep can't see (by key name, a whole object handed to a helper) gets a `// reads: Section.path, …` comment (`*` matches any part).

## Layout

```
shell.qml       entrypoint: one top-level Item per surface, plus `_services` (services only reached by IPC)
shell/          top-level pieces, one per surface
components/
  methods/      pure singleton helpers (unit-tested)
  reusable/     generic Styled* widgets, no feature logic
  forms/        schema-driven form widgets
  content/      loadable panels by name: overlay module types, bar popouts (base/, parts/)
  hosts/        where content appears: popout/, overlay/
  views/        overlay pages by view type
  bar/          the bar; widgets/ = bar widget types
  surfaces/     standalone windows (launcher, lockscreen, toasts, dock, onboarding, …)
services/       pragma Singleton managers: state and side effects
config/         reader singletons; json/ (schema, theme defaults), themes/, i18n/
scripts/        external scripts and the dev checks
backend/        the axiom binary (Go): its own AGENTS.md
tests/          qmltestrunner tests, fixtures, tests/scripts/
docs/dev/       developer docs
```

Imports use the `qs.` namespace (`import qs.services`), never relative paths; no qmldir files. Files start with `pragma ComponentBehavior: Bound` or `pragma Singleton`.

## Layering

Dependencies point one way:
- **`components/methods/`**: pure (no files, processes, dispatches or `qs.*` imports).
- **Data owners** load and watch files: `ConfigManager` (config.json, schema; reads no reader), `ThemeManager`, `I18n`.
- **`config/` readers** read only the owners and each other.
- **Services** use readers and methods and own every side effect: processes, dispatches, file writes, polling.
- **UI** uses everything below, but runs no polling Process or repeating Timer and never reads `ConfigManager.config` directly.
- **A methods helper's decision** (`BarEnds`, `SurfaceContext`, `EdgeAttach`, `GridPlacement`, …) is read from its output, never re-derived in a host from `vertical`, a location or a kind: a new case is a rule in the helper plus a test row.

## Services

- One `pragma Singleton QtObject` per domain, named `*Manager`, exposing readonly properties, signals and functions. Non-singleton helpers are named for what they are (`ConfigDraft`, `ConsumerRegistry`, `ChatRequest`). Don't shadow Quickshell singletons (`NetworkingManager`, not `Networking`).
- A service with an IPC target nothing else references is created from `shell.qml`'s `_services`.
- **Quickshell.Io's side effects are moving to the axiom daemon**: only the files in `scripts/quickshell-io-allowlist.json` use `Process`, `FileView`, `Socket`, `IpcHandler` or `Quickshell.execDetached` directly (`check_structure` enforces it, and the list only shrinks). New code runs commands through `CommandManager.run` / `runDetached`, reads files through `FileManager.read`, keeps small state through `StateManager`, takes IPC through `IpcTarget`, and asks the daemon for anything else (a file to watch or write, a socket). Drop a file's entry in the change that moves it.
- **Anything polled goes through `acquire(owner, request)` / `release(owner)`** (`ConsumerRegistry`): fetched once for all consumers at the shortest interval asked, not at all with none. Acquire in `Component.onCompleted` (again when the config-derived request changes), release in `onDestruction`.
- **Config writes** only through `ConfigManager.setTheme` / `setWallpaper(s)` / `saveConfig` / `commit(object)` (validates; false and no change if rejected), or `SettingsManager.setValue` / `commitValue(s)` from UI. Mutating `ConfigManager.config` never persists.
- **Editors** edit a `ConfigDraft`; unsaved edits show live through `ConfigManager.setPreview(section, value)`, and readers read `previews.X ?? config.X`. Selection lives in the manager and changes only through its `select*()` (`selectBar`, `selectView`, …).
- Secrets (API keys, calendar passwords) never go in config.json or argv: `SecretsManager`, through stdin. Clipboard history never touches disk; only pinned clips do.
- **The compositor is reached only through `CompositorManager`** (`docs/dev/compositor/README.md`): neutral shapes, never a compositor's own objects; every workspace switch and window focus via `goToWorkspace` / `stepWorkspace` / `nthWorkspace` / `focusWindow`, never a direct dispatch. Only its backend (`HyprlandManager`, `SwayManager`, `NiriManager`) talks to the compositor; only `Hyprland*` services import `Quickshell.Hyprland` or send Lua; only Hyprland-only features (`OnboardingManager`, `GreetdManager`'s Hyprland branch) use `HyprlandManager` directly (`check_structure` enforces it).
- **Gate on a capability, never a compositor**: `CompositorManager.supports.<key>` in code, `"/$supports.<key>": true` in a schema `x-showIf`, `x-needs` on a page type. Nothing writes a compositor's config unless `supports.configModes`. Surfaces closing on an outside click use `FocusGrab`.
- State surviving a QML reload lives in `PersistentProperties` (JSON for arrays); small persisted state in `StateManager` or `Paths.userStatePath`.
- **Nothing is written under `Paths.axiomPath`** (installed read-only): use `Paths.userConfigPath` / `statePath` / `userStatePath` / `userDataPath` / `generatedThemesPath`.

## Config

- The schema is the single source of truth: shape, defaults, the generated settings page. Its source is YAML, `config/schema/` (`index.yaml`, `sections/`, `definitions/`, `annotations.yaml`), built into `config/json/config.schema.json` (never committed) by `axiom schema build` (`scripts/generate.sh`, which verify.sh runs): never edit the JSON. A new setting = schema entry with a `default` + a reader property. Reshaping existing config is a format-2 step in `backend/internal/migrate/steps/` (`docs/recipes/migration.md`); the format-1 migrations (`backend/internal/migrate/legacy/legacy.js`, kept until format 1 is retired) are frozen at v75 and never change.
- Every default is filled at load, so **readers use no `??` fallbacks**. Readers are named for their section, `Config`-suffixed where the name is a type (`OSDConfig`). A reader exposing the saved config says so (`Bar.savedBars`).
- **Schema annotations drive the UI; prefer a new annotation to a hand-kept list in QML** (complete list: `docs/dev/core/schema-annotations.md`). With rules attached:
  - `x-scope` (`look`/`personal`/`commands`/`machine`, inherited, root `machine`) decides what an example, import or export carries: a setting in a look section naming a monitor, path or account is `machine`, one that runs something `commands`, a preference meaningful on any PC `personal`. A setting moved out of `machine` needs older shared files to keep the user's value (`share.KeepMovedKeys`, format 1 only so far), or applying one resets it.
  - `x-takeover` marks a setting that takes something over on this PC (compositor mode, locker, idle, polkit, greeter): loading or importing a config never changes it, only its own card.
  - A bar widget, overlay module or view type's schema is `schema.yaml` in its folder, expanded over its kind's base (`definitions/kinds/`). Every module is on `desktop`, `overlay` and `edgeMenu` (the base's `x-hosts`); `lockscreen` and `greeter` are opt-in (`hosts`). A module with a text field sets `keyboard`.
  - `oneOf`s are discriminated by `type`.
- An empty monitor means the primary monitor everywhere (`General.screensNamed`) except `General.primaryMonitor` itself.
- A path setting may hold `~`: expand it (`Paths.expandHome`) in its reader, or the service using it, before a process or file read. Processes run without a shell.
- **Theme**: `Theme.base00`–`base0F` plus semantic names; `Theme.resolveColor(name)` for names from config; `config/json/theme-defaults.json` fills omissions. Theme integrations write only their own `axiom.*` file; only the hookup's Apply (user's click) edits a user's config.
- **Animation**: every `duration:` is `Appearance.animFast` / `animNormal` / `animSlow` eased with `Appearance.easing` (Behaviors: `Glide on x {}` / `ColorGlide`); looping animations gate `running` on `Appearance.animations`. Only behaviour timings (blink, timeouts, polling) are literals. Bar geometry animates what's drawn, never what's measured; content changing in place cross-fades through `CrossFade`.

## Translation

- English source text inline: `I18n.tr("Text")`, placeholders for values (`I18n.tr("{0} updates", count)`), never template-string sentences.
- Dates through `I18n.formatDate(date, I18n.dateFormat("longDate" | …))`, never `Qt.formatDateTime`.
- Keys chosen at runtime are declared in a comment as `I18n.tr("…")` so the checker sees them. Schema forms translate their own text.
- Logs, validation errors and migration notes stay English.

## UI conventions

- **Reuse before building**: check `docs/dev/core/shared-ui-pieces.md` first; a second copy of a pattern becomes a shared piece.
- **Data-driven surfaces**: `Bars`, `Overlay.items`, `EdgeMenus`, `Dock.items`, `OSD.items` are config arrays; surfaces are `Variants`/Repeaters over them, keyed by stable ids.
- **Loaded by name**: `bar/widgets/<type>/<type>.qml`, `content/<Name>/<Name>.qml`, `views/<type>/<type>.qml`. A new one = the file + its schema `oneOf` entry (see those directories' `AGENTS.md`).
- **Pages show at once and fill in** (`docs/dev/core/streamed-building.md`): a tool page's panels, cards and sections, and anything long, are `StreamedLoader`s sized from the page, never built in the frame it opens. Nothing is built hidden (a Loader gated on its mode, not `visible: false`), unbounded lists are ListViews, and `scripts/dev/bench_overlay.sh` measures it.
- **Repeater models and `acquire()` requests come from config and tool availability only, never live values** (model by a count or joined string key). A model re-evaluated per sample once pushed qs past 25 GB.
- **Sizes** outside the bars come from `Widget` (`height`, `padding`, `spacing`, `iconButton`, `smallHeight`, `smallPadding`) or `Widget.px(n)` for widths and decorations, and text sizes from `Appearance.fontSize` / `fontSizeBy(n)`, so they follow the Interface scale and Density; only hairlines (≤2 px) stay numbers (`scripts/check_sizes.py`; table: `docs/dev/core/shared-ui-pieces.md` › Sizes).
- **Radii**: `Appearance.borderRadius` only for outer edges (border, bars, pills, popout surfaces, overlay box, windows); `Widget.radius` inside.
- **Rounded clipping** is Quickshell.Widgets' `ClippingRectangle` (set its `color`; it defaults to white), never a MultiEffect mask.
- **Icons**: Material Symbols names drawn by `reusable/StyledIcon`, never sharing a Text with a label.
- **Screen targeting**: surfaces are built on `General.screensFor(target)` (a `ScreenTarget`) or `General.outputs`, never `Quickshell.screens` (stand-ins while no monitor is connected); only `ShellManager.isTarget(screen, target)` answers shortcuts, IPC and OSD events, and IPC handlers are `enabled` on the target instance only.

Subsystem invariants (details in the named files):
- **Overlay modules** exist only while their page is shown (acquire/release, lasting state in a service): `components/content/AGENTS.md`.
- **Bars**: stacking is `LayerStack.layers` (`docs/dev/compositor/layer-arrangement.md`); corner ownership is `BarEnds` alone; bars and border never draw over fullscreen: `components/bar/AGENTS.md`.
- **Popouts**: geometry only from `methods/SurfaceContext`, collisions only through a `PopoutClaim`, an open popout never moves: `components/hosts/popout/AGENTS.md`.
- **Launcher**: one row shape for every provider; `/config` never edits `Bars.items`, `Overlay.items` or `EdgeMenus`: `services/AGENTS.md`.
- **Greeter**: data, never code; a side effect reachable from greeter mode checks `Paths.greeter`: `docs/dev/features/greeter-runtime.md`.
- **Lockscreen**: `LockManager.lock()` only; only PAM unlocks, never IPC: `docs/dev/features/lockscreen.md`.

## Naming

- Services `*Manager`; readers per section; hosts say what they host (`BarWidgetHost`, `OverlaySlot`); content by module type / popout name; Qt control stand-ins `Styled*`; composites named for what they are.
- A surface window gets a `Window` suffix when its shell entry shares the name (`shell/PowerMenu` → `PowerMenuWindow`). Root ids are `root`.
- Bar widget and content names may overlap, but no file may see both.
