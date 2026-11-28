# axiom

A Quickshell desktop for Hyprland, niri and sway: `qml/` (run by `qs`, no build step) and the Go `axiom` binary (`backend/`), which runs the shell and owns config.json. The live shell runs the install tree, or the dev tree in dev mode (`axiom dev status`); edits elsewhere reach only verify.sh and nested shells. Area rules: `.claude/rules/`. How things work: `docs/dev/` (index `docs/dev/README.md`).

## Working here

- **Alignment first** (above speed and scope): reuse an existing function or piece, never a near copy; one name, one unit and one pattern per concept; a new file follows the precedent of its kind. `/orchestrate` holds every change to it through a ledger, from plan to PR; `/align` fixes drift already there.
- After every change run `scripts/dev/verify.sh` until `verify ok` (`--all` = CI, prints `all checks passed`; run it once, at the end). It formats QML and prints the shell's log; a clean reload is `Reloading configuration...` + `Configuration Loaded`; `console.warn` only for real problems.
- Log `scripts/log.sh`, screenshots `scripts/dev/shot.sh`, a second shell only via `scripts/dev/nested.sh`, and only when absolutely necessary; a check no test or log can show becomes a `LIVE:` line in the PR (`docs/dev/testing.md`).
- qs watches by inode: edit QML in place, never temp file + rename; after `sed -i` or `git checkout`, force a reload.
- Read `docs/dev/core/qml-pitfalls.md` before writing QML and the area's doc before changing it. Which file does X: `grep -n '<word>' docs/dev/generated/files.md`. Recipes: `docs/recipes/`.
- A problem outside the task: tell the user, don't fix it unasked.

## Never

`.claude/hooks/guard.py` enforces the details; on a refusal ask the user, don't work around it. Scratch alternatives: `docs/dev/testing.md`.

- Lock the session (only the user can unlock) or simulate the cursor (reason from logs).
- Start, stop or restart qs or the live daemon, or change its dev mode: use a nested shell or a scratch daemon (start it with a scratch `XDG_RUNTIME_DIR`, reach it with `--socket`).
- Change the live compositor config mode, allow a takeover, enable an `x-takeover` setting live unasked, or write `~/.config/axiom/config.json` by hand (Bash, Edit and Write skip the takeover check; use `axiom config set`).
- Quit the live compositor (niri, Hyprland, sway), or change niri's outputs or config; install the greeter for real or restart greetd (ends the session); restart xdg-desktop-portal or write portal configs (ends shares).
- Change clock, time zone, hostname, password, account or default apps; touch real Bluetooth devices or the live input method (a keyboard could drop out): use fakes or a scratch bus.
- Push to main (a bare `git push` on main too), force-push (`--force-with-lease` to a branch is fine), `git clean -x`/`-X`, `git stash` (shared by every worktree).
- Merge a PR: the maintainer merges.
- Edit generated files (`docs/dev/testing.md` › The checks).
- Translate, or run `check_i18n.py --fill`/`--prune` (the pre-commit hook does).
- Put secrets in config.json or argv (`SecretsManager`, stdin).

## Architecture rules

### Layering
`qml/components/methods/` (pure: no files, processes, timers, clocks, randomness, logging, deferral or Quickshell; imports only `QtQuick`, `qs.components.methods` and the engine or domain folders its manifest entry `uses`; the root holds generic helpers two or more domains use, `<engine>/` an engine, `<domain>/` a domain's helpers) → data owners (`ConfigManager`, `ThemeManager`, `I18n`) → `qml/config/` readers → services → UI. UI runs no polling Process or repeating Timer and never reads `ConfigManager.config`. An engine's decision (`scripts/engines.json`) is read from its facade's output, a helper's from its own, never re-derived in a host: a new case is a rules row plus a contract row for an engine (`docs/dev/core/engines.md`), else a helper rule plus a test row.

### Services
- One singleton `*Manager` per domain, never shadowing a Quickshell singleton.
- Quickshell APIs only for Wayland (windows, screens, layers, focus, the session lock, capture, blur) and running the QML, in the files `scripts/quickshell-exceptions.json` lists, each with its reason (four types anywhere). System data, compositor IPC, files and processes are the daemon's: a new `Quickshell.Services.*`, `Quickshell.Networking`, `DesktopEntries`, Hyprland or i3 state, or `Quickshell.Io` use fails (the remaining ones are `structure-baseline.json` entries and only shrink); everything else uses `CommandManager`, `FileManager`, `StateManager`, `IpcTarget`, a daemon method or the domain's service.
- Polled data: `acquire(owner, request)` in `Component.onCompleted`, `release(owner)` in `onDestruction`.
- Config writes only through `ConfigManager` or, from UI, `SettingsManager`; editors edit a `ConfigDraft`.
- One-tap actions through `ActionsManager.run`; the compositor only through `CompositorManager`, gated on `CompositorManager.supports`, never on which compositor. A layer-shell window states its place through the layer service (its `LayerSlot` and `LayerStack` row) and never sets its own layer; only the service's per-compositor parts (the backends' layer facts, the daemon's compositor writers) differ by compositor (`docs/dev/compositor/layer-arrangement.md`).
- Nothing writes under the tree (`Paths.treePath`; installs are read-only).

### Config
- The schema YAML (`qml/config/schema/`, a type's `schema.yaml`) is the source of truth. New setting = schema entry with a `default` + reader property. Readers have no `??` fallbacks (defaults fill at load).
- Reshaping config is a format-2 Go step (`docs/recipes/migration.md`).
- Prefer a schema annotation to a list in QML. `x-scope`: monitor, path or account → `machine`; runs something → `commands`. `x-takeover` settings change only through their card.
- Empty monitor = primary; expand `~` (`Paths.expandHome`); processes run without a shell.

### Theme, animation, text
- Colours, text and icon sizes: `Style` roles and the style pieces (`docs/dev/core/style.md`); `check_style.py` enforces.
- A `duration:` is `Appearance.animFast`/`animNormal`/`animSlow` with `Appearance.easing`, unless a behaviour needs a fixed time (a blink, a pause); loops gate `running` on `Appearance.animations`.
- `I18n.tr("{0} updates", count)`, never a built sentence; runtime keys listed in a comment. Dates via `I18n.formatDate`. Logs stay English.

### UI
- Reuse first (`docs/dev/core/shared-ui-pieces.md`); a second copy becomes a shared piece. Only plumbing reusables read services.
- Bars, pages, menus, docks, OSDs are config arrays keyed by stable ids.
- Pages show at once: panels are `StreamedLoader`s, nothing built hidden, unbounded lists are ListViews.
- Repeater models and `acquire()` requests come from config only, never live values (one pushed qs past 25 GB).
- Sizes from `Widget`, `Widget.px(n)`; text and icon sizes and radii from `Style` roles (`docs/dev/core/style.md`) (bars from their config); `Style.radiusOuter` outer edges only; `ClippingRectangle` for rounded clips; icons are `StyledIcon`.
- Surfaces on `General.screensFor(target)`, never `Quickshell.screens`; `ShellManager.isTarget` answers shortcuts and IPC; outside clicks close via `FocusGrab`.

### Formatting and layout
- A purpose comment above each QML root object; `// reads: Section.path` for config reads grep can't see, `// rpc: name` for `BackendManager.call` names. Never `qmlformat -i`.
- QML under `qml/`, imported as `qs.…`; runtime non-QML under `data/`; `scripts/` is dev-only. Folders: `docs/dev/README.md` › Layout.
- A new dependency: install.sh's table, `Packages.packages`, the AUR PKGBUILDs.

## Agents and skills

Every change starts with `/orchestrate <request>`. It sizes the change into a tier (T0 Fix, T1 Improvement, T2 Feature, T3 Cross-system; every tier has a ledger), plans, builds in gated groups in a worktree, reviews, and stops with a report for the PR. It keeps its state in the plans folder (`.plans/<slug>/`, gitignored). `.claude/agents/`: **architect** (opus) specs, checks plans and judges findings; **implementer** (sonnet) builds; **reviewer** (sonnet) reviews; **checker** (haiku) runs checks. Every hand-off's layout is in `.claude/templates/`. Recipe skills (`/bar-widget`, `/setting`, `/engine-change`, …), `/keep-order` (plan, gate, audit), `/review-branch`, `/align` and `/verify` run inside it.
