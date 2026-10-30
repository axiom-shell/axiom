# AGENTS.md

The rules for working on axiom, for contributors and coding agents alike (`CLAUDE.md` imports this file).

## What this is

A [Quickshell](https://quickshell.org) desktop in QML for Hyprland 0.55+ (Lua config), niri 26.04+ and sway 1.12+, run by `qs` with no build step, under the `axiom` binary (Go: `backend/`).

This file holds only rules; **how everything works is in `docs/dev/`** (index: `docs/dev/README.md`): read a feature's doc before changing it, update it when you change how it works. Directories with their own `AGENTS.md` add local rules.

## Where to look

- **The next step / the roadmap:** `docs/dev/roadmap.md` › Taking the next step (skill `next-step`; unattended: skill `roadmap-autopilot`).
- **Something of a known kind** (a bar widget, module, page, setting, service, …): its recipe in `docs/recipes/` (also a skill).
- **Any area:** `docs/dev/README.md` › Where to look. Always: `docs/dev/core/qml-pitfalls.md` before writing QML, `docs/dev/core/shared-ui-pieces.md` before drawing anything, `docs/dev/issues.md` before working in an area; `grep -n '<word>' docs/dev/generated/files.md` finds the file that does X.

**Found a problem outside the task?** Don't fix it unasked and don't only mention it: add an entry to `docs/dev/issues.md` (format at its top), link it from the phase of `docs/dev/roadmap.md` that will fix it, and tell the user. Quote a log warning's message in backticks under **What** so `verify.sh` marks it `(known: …)`. Remove the entry in the change that fixes it. Never open a GitHub issue; the maintainer moves entries there.

## Running / reloading

- **After any change run `scripts/dev/verify.sh`** until it prints `verify ok`; read the docs it lists if behaviour changed. Screenshots (`scripts/dev/shot.sh`), logs (`scripts/log.sh`) and reload traps: `docs/dev/testing.md`.
- The shell runs under `axiom run`, which owns config.json: never start, stop or restart either; a second one runs only nested (`scripts/dev/nested.sh`) or on scratch folders. qs watches by inode: after `sed -i` or `git checkout`, force a reload.
- `console.warn` only for real problems: a clean reload logs just `Reloading configuration...` + `Configuration Loaded`.
- Rewrite watched JSON (`config/i18n/*.json`, config.json) atomically (temp file + rename).

## Never, while testing

Enforced by `.claude/hooks/guard.py` (PreToolUse hook plus `permissions.deny` in `.claude/settings.json`; tests: `tests/scripts/test_guard.py`). A refusal names the rule: don't work around it, ask the user. A new rule here gets one there.

- Lock the built-in locker (only the user can type the password): test `LockSurface` in a hidden window.
- Simulate cursor movement to verify UI: read logs and reason through bindings.
- Switch the real compositor config (`Compositor.mode`) into or out of `managed`, or out of `included` (test `axiom compositor claim|release` / `binds remove` on scratch dirs); allow a takeover (`CompositorConfigManager.allowTakeover`, the card's Allow); Keep a monitor layout; `apply` a self-update on the live repo; delete the real config.json (use `axiom ipc onboarding goTo <n>`) or write it from Bash (`cp`, `>`, `sed -i`, …: that skips the `x-takeover` check Edit and Write get; or `axiom config set`); enable `Idle` on the live config without asking (it replaces the user's hypridle).
- Make the live niri session quit, load another config or change outputs (`niri msg action quit` / `load-config-file` / `output`): only a nested one's `NIRI_SOCKET`.
- Apply a theme integration's hookup to the real configs: `hookup.apply` only to a scratch daemon.
- Install, update or remove the greeter for real, or restart greetd (it ends the session): `axiom greeter-install` only with a scratch `AXIOM_GREETER_ROOT`, the greeter only windowed on scratch folders (`docs/dev/features/greeter-runtime.md` › Testing).
- Run, quit, restart or re-exec the live `axiom` daemon (`axiom run|quit|restart`, `axiom daemon stop|restart|reexec`), switch its dev mode (`axiom dev on|off|rebuild`), lock through it (`axiom lock`, `axiom ipc lockscreen …`), or pass `--takeover` against the live config: use a scratch instance (`XDG_RUNTIME_DIR=<scratch>`, `--socket`, `--config-dir`). A test lock screen's fallback is never `loginctl lock-session`.
- Open a GitHub issue (`gh issue create`, or `gh api` posting one).
- Force-push, delete a remote branch, or push to `main`: everything reaches main through a PR.
- `git clean -x` / `-X`: it deletes the generated files and local state the ignore list keeps (`git clean -fd` is fine).

## Checks

`scripts/dev/verify.sh --all` runs every CI check (`docs/dev/testing.md` › The checks); none runs the shell, so still read the log. Left to you:
- Fix a new qmllint warning (`--update-baseline` only for Quickshell type-info gaps); every baseline only shrinks.
- A changed methods helper gets a `tests/tst_<Name>.qml` case, a migration step a Go test, a new check rule a breaking fixture.
- **Agents never translate**, however easy it looks, nor run `check_i18n.py --fill`/`--prune` (the pre-commit hook does).
- Generated files (listed in `docs/dev/testing.md` › The checks) are never edited by hand.
- A new dependency goes in install.sh's table, `Packages.packages` and the AUR PKGBUILDs.

## Formatting

- verify.sh formats changed QML in place. Never `qmlformat -i` (it replaces the inode).
- Each QML file has a short purpose comment above its root object.
- A config read grep can't see gets a `// reads: Section.path` comment; a daemon method name handed to `BackendManager.call`, `// rpc: name`.

## Layout

Each kind of file has its folder and naming (`docs/dev/README.md` › Layout; `check_structure` enforces it). `components/reusable/` holds generic `Styled*` widgets with no feature logic; only `StyledToolTip` and the plumbing `StreamedLoader`, `BackdropRequest`, `ScrollMemory`, `SurfaceGroup` read services. Imports use `qs.`, never relative paths.

## Layering

Dependencies point one way:
- **`components/methods/`**: pure (no files, processes, dispatches or `qs.*` imports).
- **Data owners** (`ConfigManager`, `ThemeManager`, `I18n`) load and watch files; `ConfigManager` reads no reader.
- **`config/` readers** read only the owners and each other.
- **Services** use readers and methods and own every side effect: processes, dispatches, file writes, polling.
- **UI** uses everything below, but runs no polling Process or repeating Timer and never reads `ConfigManager.config`.
- **A methods helper's decision** (`BarEnds`, `SurfaceContext`, `EdgeAttach`, …) is read from its output, never re-derived in a host: a new case is a rule in the helper plus a test row.

## Services

How they're built: `docs/dev/core/services-pattern.md`.
- One `pragma Singleton QtObject` per domain, named `*Manager`, never shadowing a Quickshell singleton (`NetworkingManager`).
- **Quickshell.Io's side effects are moving to the axiom daemon**: only the files in `scripts/quickshell-io-allowlist.json` use `Process`, `FileView`, `Socket` or `Quickshell.execDetached` (`check_structure`). New code runs commands through `CommandManager.run` / `runDetached`, reads files through `FileManager.read` (`XMLHttpRequest` only for HTTP), keeps small state through `StateManager`, takes IPC through `IpcTarget`, and asks the daemon for anything else (a file to watch or write, a socket).
- **Anything polled goes through `acquire(owner, request)` / `release(owner)`**: fetched once at the shortest interval asked, not at all with no consumer. Acquire in `Component.onCompleted`, release in `onDestruction`.
- **Config writes** only through `ConfigManager.setTheme` / `setWallpaper(s)` / `commit(object)`, or `SettingsManager.setValue` / `commitValue(s)` from UI; mutating `ConfigManager.config` never persists. **Editors** edit a `ConfigDraft` and show unsaved edits through `ConfigManager.setPreview` (`docs/dev/core/editors-pattern.md`).
- Secrets never go in config.json or argv (`SecretsManager`, through stdin). Clipboard history never touches disk.
- **The compositor is reached only through `CompositorManager`**, in neutral shapes; every workspace switch and window focus through its `goToWorkspace` / `stepWorkspace` / `nthWorkspace` / `focusWindow` (`check_structure`; `docs/dev/compositor/README.md`).
- **Gate on a capability, never a compositor**: `CompositorManager.supports.<key>`, `"/$supports.<key>": true` in an `x-showIf`, `x-needs` on a page type. Nothing writes a compositor's config unless `supports.configModes`.
- **Nothing is written under `Paths.axiomPath`** (installed read-only).

## Config

- **The schema is the single source of truth** (shape, defaults, the settings page): edit its YAML (`config/schema/`, a type's `schema.yaml`), never the built JSON. A new setting = schema entry with a `default` + a reader property. Reshaping existing config is a format-2 step (`docs/recipes/migration.md`); format 1's migrations are frozen.
- Every default is filled at load: **readers use no `??` fallbacks**.
- **Prefer a new schema annotation to a hand-kept list in QML** (`docs/dev/core/schema-annotations.md`). `x-scope`: a setting naming a monitor, path or account is `machine`, one that runs something `commands` (`docs/dev/core/saved-configs-sharing.md`). An `x-takeover` setting changes only through its own card, never by a load or import.
- An empty monitor means the primary monitor (except `General.primaryMonitor` itself). A path setting may hold `~`: expand it (`Paths.expandHome`) before use. Processes run without a shell.
- **Theme** colours by name (`Theme.resolveColor` for names from config). Theme integrations write only their own `axiom.*` file; only the hookup's Apply (a user's click) edits the user's config.
- **Animation**: a `duration:` is `Appearance.animFast` / `animNormal` / `animSlow` with `Appearance.easing`, or marked `// behaviour timing: <reason>` (`check_structure`); looping animations gate `running` on `Appearance.animations`.

## Translation

- English text inline: `I18n.tr("Text")`, placeholders for values (`I18n.tr("{0} updates", count)`), never template-string sentences; keys chosen at runtime are declared in a comment as `I18n.tr("…")`. Dates through `I18n.formatDate`, never `Qt.formatDateTime` (`check_structure`). Logs, validation errors and migration notes stay English (`docs/dev/core/i18n.md`).

## UI conventions

- **Reuse before building** (`docs/dev/core/shared-ui-pieces.md`); a second copy of a pattern becomes a shared piece.
- **Data-driven surfaces**: bars, pages, edge menus, docks, OSDs are config arrays, built by `Variants`/Repeaters keyed by stable ids; types load by name (file + schema `oneOf` entry).
- **Pages show at once and fill in** (`docs/dev/core/streamed-building.md`): panels and anything long are `StreamedLoader`s, nothing is built hidden, unbounded lists are ListViews.
- **Repeater models and `acquire()` requests come from config and tool availability only, never live values** (`check_structure`): one re-evaluated per sample once pushed qs past 25 GB.
- **Sizes** from `Widget`, `Widget.px(n)` and `Appearance.fontSize(By)` (`scripts/check_sizes.py`); `Appearance.borderRadius` only for outer edges, `Widget.radius` inside; rounded clipping is `ClippingRectangle`; icons are `StyledIcon`, never in a Text with a label.
- **Screen targeting**: surfaces on `General.screensFor(target)` or `General.outputs`, never `Quickshell.screens` (`check_structure`); only `ShellManager.isTarget(screen, target)` answers shortcuts, IPC and OSD events, and IPC handlers are `enabled` there only. An outside click closes through `FocusGrab`.
- **Subsystem invariants** (`components/content/`, `components/bar/`, `components/hosts/popout/`, `services/` `AGENTS.md`): modules exist only while shown; corners are `BarEnds`' alone; nothing draws over fullscreen; an open popout never moves. The greeter runs data, never code (side effects check `Paths.greeter`). Only `LockManager.lock()` locks; only PAM unlocks.
