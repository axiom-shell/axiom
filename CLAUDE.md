# axiom

A Quickshell desktop for Hyprland, niri and sway: `qml/` (run by `qs`, no build step) and the Go `axiom` binary (`backend/`), which runs the shell and owns config.json. The live shell runs the install tree, or the dev tree in dev mode (`axiom dev status`); edits elsewhere reach only verify.sh and nested shells. Area rules: `.claude/rules/`. How things work: `docs/dev/` (index `docs/dev/README.md`).

## Working here

- After every change run `scripts/dev/verify.sh` until `verify ok` (`--all` = CI). It formats QML and prints the shell's log; a clean reload is `Reloading configuration...` + `Configuration Loaded`; `console.warn` only for real problems.
- Log `scripts/log.sh`, screenshots `scripts/dev/shot.sh`, a second shell only via `scripts/dev/nested.sh` (`docs/dev/testing.md`).
- qs watches by inode: edit QML in place, never temp file + rename; after `sed -i` or `git checkout`, force a reload.
- Read `docs/dev/core/qml-pitfalls.md` before writing QML and the area's doc before changing it; update it when behaviour changes. Which file does X: `grep -n '<word>' docs/dev/generated/files.md`. Recipes: `docs/recipes/`.
- A problem outside the task: tell the user, don't fix it unasked.

## Never

`.claude/hooks/guard.py` enforces the details; on a refusal ask the user, don't work around it. Scratch alternatives: `docs/dev/testing.md`.

- Lock the session (only the user can unlock) or simulate the cursor (reason from logs).
- Start, stop or restart qs or the live daemon, or change its dev mode: use a nested shell or scratch daemon (`XDG_RUNTIME_DIR`, `--socket`).
- Change the live compositor config mode, allow a takeover, enable an `x-takeover` setting live unasked, or write `~/.config/axiom/config.json` from Bash (skips the takeover check).
- Quit the live niri or change its outputs or config; install the greeter for real or restart greetd (ends the session); restart xdg-desktop-portal or write portal configs (ends shares).
- Change clock, time zone, hostname, password, account or default apps; touch real Bluetooth devices or the live input method (a keyboard could drop out): use fakes or a scratch bus.
- Push to main, force-push, `git clean -x`/`-X`.
- Edit generated files (`docs/dev/testing.md` › The checks).
- Translate, or run `check_i18n.py --fill`/`--prune` (the pre-commit hook does).
- Put secrets in config.json or argv (`SecretsManager`, stdin).

## Architecture rules

### Layering
`qml/components/methods/` (pure: no files, processes or `qs.*` imports) → data owners (`ConfigManager`, `ThemeManager`, `I18n`) → `qml/config/` readers → services → UI. UI runs no polling Process or repeating Timer and never reads `ConfigManager.config`. A helper's decision (`BarEnds`, `SurfaceContext`, …) is read from its output, never re-derived in a host: a new case is a helper rule plus a test row.

### Services
- One singleton `*Manager` per domain, never shadowing a Quickshell singleton.
- Quickshell.Io only in `scripts/quickshell-io-allowlist.json`'s four files; everything else uses `CommandManager`, `FileManager`, `StateManager`, `IpcTarget` or a daemon method.
- Polled data: `acquire(owner, request)` in `Component.onCompleted`, `release(owner)` in `onDestruction`.
- Config writes only through `ConfigManager` or, from UI, `SettingsManager`; editors edit a `ConfigDraft`.
- One-tap actions through `ActionsManager.run`; the compositor only through `CompositorManager`, gated on `CompositorManager.supports`, never on which compositor.
- Nothing writes under the tree (`Paths.treePath`; installs are read-only).

### Config
- The schema YAML (`qml/config/schema/`, a type's `schema.yaml`) is the source of truth. New setting = schema entry with a `default` + reader property. Readers have no `??` fallbacks (defaults fill at load).
- Reshaping config is a format-2 Go step (`docs/recipes/migration.md`).
- Prefer a schema annotation to a list in QML. `x-scope`: monitor, path or account → `machine`; runs something → `commands`. `x-takeover` settings change only through their card.
- Empty monitor = primary; expand `~` (`Paths.expandHome`); processes run without a shell.

### Theme, animation, text
- Colors: `Theme.base00`–`base0F` or semantic names; config names via `Theme.resolveColor`.
- A `duration:` is `Appearance.animFast`/`animNormal`/`animSlow`, or marked `// behaviour timing: <reason>`; loops gate `running` on `Appearance.animations`.
- `I18n.tr("{0} updates", count)`, never a built sentence; runtime keys listed in a comment. Dates via `I18n.formatDate`. Logs stay English.

### UI
- Reuse first (`docs/dev/core/shared-ui-pieces.md`); a second copy becomes a shared piece. Only plumbing reusables read services.
- Bars, pages, menus, docks, OSDs are config arrays keyed by stable ids.
- Pages show at once: panels are `StreamedLoader`s, nothing built hidden, unbounded lists are ListViews.
- Repeater models and `acquire()` requests come from config only, never live values (one pushed qs past 25 GB).
- Sizes from `Widget`, `Widget.px(n)`, `Appearance.fontSize` (bars from their config); `Appearance.borderRadius` outer edges only; `ClippingRectangle` for rounded clips; icons are `StyledIcon`.
- Surfaces on `General.screensFor(target)`, never `Quickshell.screens`; `ShellManager.isTarget` answers shortcuts and IPC; outside clicks close via `FocusGrab`.

### Formatting and layout
- A purpose comment above each QML root object; `// reads: Section.path` for config reads grep can't see, `// rpc: name` for `BackendManager.call` names. Never `qmlformat -i`.
- QML under `qml/`, imported as `qs.…`; runtime non-QML under `data/`; `scripts/` is dev-only. Folders: `docs/dev/README.md` › Layout.
- A new dependency: install.sh's table, `Packages.packages`, the AUR PKGBUILDs.

## Agents and skills

`.claude/agents/`: **architect** (opus) writes specs, judges findings; **implementer** (sonnet) builds a spec or recipe; **reviewer** (sonnet) reviews a slice through one lens; **checker** (haiku) runs checks. Beyond a small edit: architect specs if the shape is open, implementer builds, checker verifies. Recipe skills (`/bar-widget`, `/setting`, …) run on implementer; `/review-branch` fans out reviewers, architect confirms.
