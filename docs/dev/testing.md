# Testing and debugging the running shell

> **Files:** `scripts/dev/verify.sh`, `scripts/dev/shot.sh`, `scripts/dev/bench_overlay.sh`, `scripts/dev/mem.sh`, `scripts/log.sh`, `backend/internal/buginfo/buginfo.go`, `backend/internal/cli/buginfo.go`, `scripts/check_all.sh`, `scripts/run_tests.sh`
> **Config:** none
> **Related:** [Developer docs](README.md), [AGENTS.md](../../AGENTS.md) (Running / reloading, Never while testing, Checks)

How to look at, exercise and debug the live shell without breaking the user's session, plus where every feature's own testing notes live. What you must never do while testing is in AGENTS.md › "Never, while testing".

### The loop
- `scripts/dev/verify.sh` after every change: formats the changed QML in place (keeping the inode), runs `check_structure`, `check_sizes`, `check_docs` and `check_packages` on every change, lints changed QML, checks changed JSON files parse, runs the affected unit tests (a changed `methods/<Name>` runs `tst_<Name>`, a schema change runs `Config`, a changed script its `tests/scripts/test_scripts.py` classes, mapped in verify.sh), shellchecks changed scripts (and `.githooks/`), counts a deleted file (a rename's old path too) and a changed check script as changes to what they cover, builds the generated files first (`scripts/generate.sh`: the schema from `config/schema/` and the reference docs in `docs/dev/config/` and `docs/dev/generated/`), through the Go checks (`scripts/check_go.sh --fix`, which add the shared fixtures) when `backend/`, a file it embeds, the schema or what the fixtures are recorded from changed, checks and replays the shared fixtures, and prints the shell's log since the reload (waiting for one only when it formatted a file: a save's reload came before it started). `--all` runs `check_all.sh`.
- Each check script has a `tests/scripts/test_scripts.py` class asserting it fails on what it catches, so a pattern that stops matching fails: `CheckStructure`, `CheckI18n`, `CheckPackages` and `CheckDocs` break a copy of the tree (`fixture_root`) once per rule and assert each message; `CheckQmllint` (its baseline's `against()`), `CheckSizes` and `ConfigUsage` test their functions on small inputs. A new rule gets its case there.
- `scripts/dev/bench_overlay.sh [-w SECONDS] [-n CYCLES] [-p PID] [--mem] [PAGE…]` times the overlay: how long opening and each page switch blocked, and how long each page and its modules took to build (see [pages-and-grid.md › Loading](overlay/pages-and-grid.md)).
- `scripts/dev/mem.sh PID` reads a qs's memory (RSS, Private_Dirty, AnonHugePages, the JS heap, render threads), and `bench_overlay.sh -p PID --mem -n CYCLES` reads it after each overlay cycle of a nested shell: [memory.md](core/memory.md).
- `scripts/dev/shot.sh` takes a screenshot of a surface and closes it again, printing the PNG's path: `page <ViewType>`, `launcher [text]`, `ipc <target> <open> [close]`, `screen`; `-m MONITOR` (default the focused one), `-w SECONDS`.

### The checks
All run in CI; `scripts/dev/verify.sh --all` (= `scripts/check_all.sh`) runs every one. None runs the shell, so still read the log. (The rules they hold: AGENTS.md › Checks.)
- `scripts/check_structure.py`: folders, imports, layering gates, the Quickshell.Io allowlist, and the AGENTS.md rules a pattern can hold (live Repeater models, `duration:` literals, `Qt.formatDateTime`, `Quickshell.screens`). Run it after adding, renaming or moving QML files. It fails a singleton over 800 lines (bar `components/methods/` and the compositor backends): split it.
- `scripts/run_tests.sh [Name…]` runs `tests/tst_<Name>.qml` (schema defaults are `tst_Config`); a migration step's tests are Go (`scripts/check_go.sh`).
- `scripts/check_qmllint.py` fails on warnings not in `scripts/qmllint-baseline.json`, and on baselined ones gone. `--update-baseline` only for Quickshell type-info gaps or baselined warnings gone.
- `scripts/check_i18n.py`: the pre-commit hook (`git config core.hooksPath .githooks`; verify.sh warns if it isn't set up) adds new keys empty (shown in English) to every `config/i18n/<code>.json` and drops unused ones ([i18n](core/i18n.md)). Edit i18n files only in the checker's format (2-space JSON; `--format` fixes it).
- `scripts/check_docs.py` fails on a hand-written doc citing a path or `Singleton.member` that's gone (fix the doc with the code), and on an `x-*` annotation missing from [schema-annotations](core/schema-annotations.md).
- `scripts/check_go.sh`: the Go checks for `backend/` (`--fix` regenerates and formats); rules in `backend/AGENTS.md`.
- `scripts/check_packages.py`: a new dependency goes in install.sh's table, `Packages.packages` and the AUR PKGBUILDs ([packaging](packaging.md)).
- `scripts/check_sizes.py`: literal pixel sizes outside the bars ([shared-ui-pieces](core/shared-ui-pieces.md) › Sizes).
- **Built, never committed** (`.gitignore`; `scripts/generate.sh` builds them when stale, and verify.sh, check_all.sh, check_go.sh and CI run it first; a fresh clone runs it once): `config/json/config.schema.json` (from `config/schema/`), the binary's embedded copies `backend/internal/assets/data/`, the reference docs `docs/dev/config/` and `docs/dev/generated/` (`scripts/gen_docs.py`, which also fails when the shell calls a daemon method the daemon doesn't define, and on a setting nobody reads or a reader member nobody uses that `scripts/config-usage-baseline.json` doesn't list: that list only shrinks), and with `--fixtures` the shared fixtures `tests/fixtures/shared/` (recorded from the JS helpers; needs qmltestrunner and the whole git history).
- Generated but committed, never edited by hand: `config/themes/template/theme.json` (`scripts/gen_theme_template.py`; the pre-commit hook rebuilds it) and `config/i18n/template/language.json`.
- `scripts/check_doc_drift.py` (warnings) lists docs whose `Files:` changed in 5+ commits since the doc did: reread one against the code before relying on it, and touch it to reset the count.
- Formatting: verify.sh formats changed QML in place with Qt 6's qmlformat (`.qmlformat.ini`), keeping the inode; the `qmlformat` on PATH is Qt 5's and fails silently. A `// reads: Section.path, …` comment's `*` matches any part; `// rpc:` comments: [protocol](backend/protocol.md) › Changing the protocol.

### Reloads and logs
- The shell runs under `axiom run` and hot-reloads QML files it has loaded. Never start, stop or restart it (or the daemon) yourself; ask the user to restart. A second axiom runs only nested: `scripts/dev/nested.sh <sway|niri|hyprland>`.
- A scratch environment in zsh: `E="XDG_RUNTIME_DIR=/x XDG_CONFIG_HOME=/y"; env $E …` passes one argument, so the command falls back to the live folders (two test writes once landed in the real config.json this way). Put the assignments inline, use `env ${=E}`, or source a file in `bash -c`, and check `axiom config path` resolves to the scratch folder before any write.
- `~/.config/axiom/config.json` belongs to the settings UI but may be edited to test (with Edit or Write, never from Bash: AGENTS.md › Never). An invalid file never replaces the running config (`savesBlocked` refuses saves until it's fixed).
- `console.log` is for tracing (`scripts/log.sh --debug` shows it), `console.warn` only for real problems.
- Outside dev mode the daemon reads the schema once, at its start: after a schema change, the live shell keeps the old schema until the user restarts axiom, on a binary rebuilt with the new one (`scripts/generate.sh`, then `go -C backend build -o ~/.local/bin/axiom ./cmd/axiom` or wherever theirs lives). Test a schema change in `scripts/dev/nested.sh`, or with `axiom config validate`.
- **Dev mode** (`axiom dev status`; only the user switches it: `axiom dev on|off|rebuild` is refused against the live daemon): while it's on, a YAML edit rebuilds the live schema, and saving a Go file under `backend/` builds axiom and re-execs the live daemon by itself (the shell keeps running): that's expected, not something to avoid. A failed build shows in `axiom dev status` and the daemon log (`axiom daemon logs`).
- `scripts/log.sh` shows warnings and errors since the last reload. `--debug` adds `console.log`, `--all` covers earlier reloads, `-f` follows, `-g PATTERN` filters. A clean reload is just `Reloading configuration...` + `Configuration Loaded`.
- `axiom bug-info` (`--json` for one object) prints the block the bug report form asks for: axiom's version (the tree's `.packaged` marker, else a clone's `git describe` and branch), the binary's and whether it runs, Quickshell's, the running compositor's version (asked over its socket, `compositor/ipc`'s `Version`) and how many monitors are on, the distribution, and the config's format, version and `Compositor.mode` with whether it loads (`ok`, `blocked`). The binary, the tree and the config come from the running daemon (`daemon.hello`, `config.get`), else (none runs, or one that won't answer: an older binary after an update) from this binary, the installed tree and the file (`backend/internal/buginfo`, `cli/buginfo.go`). No names or paths. It's not a check.
- **qs watches files by inode.** `sed -i`, `/usr/lib/qt6/bin/qmlformat -i`, `git checkout <file>` and `git stash push/pop` all replace the inode. Later edits to that file may then not reload, and the shell silently keeps old code.
  - To force a reload, make a real in-place content change to a file that's still watched (append `// x` with Python's `open(p, 'w')`, then remove it). Rewriting identical content doesn't count.
  - Count `Reloading` lines in `scripts/log.sh --all` before and after to confirm.
  - Nothing reloads while the built-in lock screen is up (`Quickshell.watchFiles` is off, [lockscreen](features/lockscreen.md) › No reload under the lock): edits made meanwhile load at the first save after unlocking.
  - Revert temporary edits in place, not with `git checkout`.
- A failed reload leaves the old generation running. Force a clean reload before editing config.json.
- To wait for a reload: `timeout 8 bash -c 'until scripts/log.sh | grep -q "Configuration Loaded"; do :; done'`.
- Raw logs: `qs log -c axiom -f` (or `-t 50`); each instance also writes `/run/user/$UID/quickshell/by-id/<instance>/log.log` (plain text; `pgrep -af "qs -c axiom"` finds the instance). stdout and journalctl show nothing.
- If config.json was lost (it falls back to defaults), restore it from a snapshot in `~/.config/axiom/saved/`.
- **Renaming or deleting a singleton** can leave a reload failing with `Type <Old> unavailable … File not found`: one fired between the edits and kept the old file in its module listing. Force one more reload (above); it rescans and loads. Add the old name to `RETIRED` in `scripts/check_docs.py` so docs still citing it fail.

### Seeing a page or surface
- Overlay pages: `scripts/dev/shot.sh page <ViewType>` does all of this. By hand: `axiom ipc overlay page <ViewType>`, then `grim -o <monitor>` (or `grim -g "X,Y WxH"`), crop with `magick`, read the PNG, then `axiom ipc overlay close`.
- The overlay only instantiates the current page and its neighbours, so a page's QML errors only reach `scripts/log.sh` once it's been opened like this.
- A temporary `IpcTarget` (for a settings category, calling `SettingsManager.openCategory(name)`; a lockscreen preview; a screenshot hook) goes in `shell.qml`, called with `axiom ipc`. Revert it in place afterwards.
- Never simulate cursor movement to verify UI. Reason from logs and bindings; if it really needs interactive checking, ask the user to look.
- Per-feature recipes:
  - Launcher: [launcher.md › Testing](features/launcher.md) (`appLauncher search`, focus stealing).
  - Lock screen: [lockscreen.md › Testing](features/lockscreen.md) (`LockManager.editor.startPreview()`, draft-only demo layouts).
  - Greeter: [greeter-runtime.md › Testing](features/greeter-runtime.md) (windowed greeter) and [greeter-install.md › Testing](features/greeter-install.md) (scratch root).
  - Onboarding: [onboarding.md › Testing](features/onboarding.md) (`axiom ipc onboarding goTo <n>`).
  - Another compositor: [sway-backend.md › Running it](compositor/sway-backend.md) (`scripts/dev/nested.sh <sway|niri|hyprland>`: a nested compositor with a second axiom on scratch folders and its own D-Bus; kill only the nested compositor you started). Nested niri: [niri-backend.md › Running it](compositor/niri-backend.md). Keep its window visible: hidden (another workspace), niri's winit backend stops, and the axiom in it, and any `axiom ipc` call into it, hangs until it's shown again.

### Popout and layering checks
- **Fullscreen must cover bars and the border.** This is a recurring regression. After changing layer rules (`render.LayerRulesLua`), `WlrLayershell.layer` or `aboveWindows`, test a fullscreen window on a normal and on a special workspace.
  - Hyprland hides Top layers over fullscreen by fading them (`m_aboveFullscreen`), not by draw order. A Top layer that *maps* while a fullscreen window is up draws over it, so never map a Top window in response to fullscreen. Keep it mapped and hide its contents.
  - Known Hyprland 0.56.2 bug: on scrolling-layout (strip) monitors, a fullscreen window on a special workspace goes under the bars.

### Config and schema
- Rename or reshape a config key with the schema change first (or both in one edit), then its format-2 step (`docs/recipes/migration.md`).
- Adding a module to the live config: [writing-modules.md › Testing](overlay/writing-modules.md). Confirm the schema reloaded (the latest `Loading config schema` line in the instance's `log.log` is newer than the schema file's mtime), back up config.json to a scratch dir and restore it afterwards, add one module at a time, and watch qs's RSS.

### JS and QML experiments
- Engine gaps (`flatMap`, `Object.fromEntries`, `Intl`) and the inline-component trap are in [qml-pitfalls](core/qml-pitfalls.md). `toLocaleString(..., { timeZone })` is ignored too: see [clock-timezones](features/clock-timezones.md).
- For quick JS checks, run a scratch `tst_x.qml` with `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input <dir>`. The dev scripts find Qt 6's tools through `scripts/lib/qt_paths.sh` (`$QT_BIN`, else `qmake6 -query`, else `/usr/lib/qt6/bin`; Fedora's are in `/usr/lib64/qt6/bin`). The plain `qml` tool prints nothing.

### CI
- `.github/workflows/checks.yml` runs on pull requests (a PR's run checks the merge commit that lands; merges are serial), weekly on main for the `go` job alone (govulncheck, for advisories published since the last Go PR), and by hand (`gh workflow run checks.yml --ref <branch>`) for a full run. Each of its four jobs runs its part of `scripts/check_all.sh` (`--ci <job>`), the one list of checks. A new push cancels the PR's older run, and the `go` job skips itself when the PR touches nothing the binary is built or tested from (its first step lists the paths). CI confirms; `scripts/dev/verify.sh --all` before the first push is what finds failures.
- The `checks` job's summary page (`scripts/ci_summary.py`) shows each quick check's result and its findings as tables, linked to the file and line: structure, the shell against the daemon's methods (`gen_docs.py`), docs against the code, translations (empty entries only warn). On a pull request it adds the docs describing the files it changes (`check_doc_drift.py --changed`), then the doc drift table. It reports only; the steps fail.
- To see it locally: `scripts/ci_summary.py --changed-from main`.
- Doc drift only warns, on purpose: it counts commits, not changed behaviour, and failing on it would teach touching docs to reset the count.

### CI locally
- To dry-run the CI `qt` job in a clean container:
  1. Copy the tracked and new files (`git ls-files -co --exclude-standard -z | tar …`) into a scratch dir and `git init` + commit there.
  2. Mount it read-only into `docker run --rm -e CI=true archlinux:latest`.
  3. Run the workflow's pacman line, then copy to a writable dir and run the steps.
- This catches dependencies only the dev machine has (e.g. `Qt5Compat.GraphicalEffects`).

### Mutation runs
- A sampled mutation run (2026-10-30, roadmap Phase 11 step 0 batch 8; numbers in `.claude/reviews/guardrails.md` › Mutation run) used a throwaway mutator kept outside the repo (about 200 lines of Go on `go/ast`, `go/parser`, `go/format`, no dependencies, plus a shell driver). To rebuild it: for each function of a file (optionally filtered by a name regexp) it lists every site of these mutations, applies one at a time to a copy, and runs `go test -overlay <json> -count=1 -timeout 90s ./internal/<pkg>` (the overlay swaps the mutated copy in, so the tree is never touched), six at a time: `==`↔`!=`, `<`→`<=`, `<=`→`<`, `>`→`>=`, `>=`→`>`, `&&`↔`||`, an `if` condition negated, a `!` dropped from an `&&`/`||` operand, `true`↔`false`, a returned error (`err`, an `*Err*` name, or `fmt.Errorf`/`errors.New`/`axerr.New`/`axerr.Wrap*`) replaced by `nil`, and a call statement removed. A passing run is a survivor; a build or vet failure counts as killed. Survivors that only drop a log line are equivalent.
- A mutant can undo a test's stub (`greeterinstall.New`'s default `pkexec` reached the real one and waited on its prompt): put refusing stand-ins for `pkexec`, `sudo`, `su`, `doas` and `run0` first on `PATH` for the run, and the root-only branches go through `unshare -rm`, never real root.

### Feature testing sections
- Hyprland: [config-modes](hyprland/config-modes.md), [managed-takeover](hyprland/managed-takeover.md), [monitors](hyprland/monitors.md)
- Theming: [theme-integrations](theming/theme-integrations.md) (hookups: Go tests in a scratch home, never `hookup.apply` on the live daemon)
- Services: [self-update](features/self-update.md) (Go tests on scratch clones, never `selfupdate.apply` on the live daemon), [polkit](features/polkit.md), [calendar](features/calendar.md), [idle](features/idle.md)
- Surfaces: [launcher](features/launcher.md), [lockscreen](features/lockscreen.md), [greeter-install](features/greeter-install.md), [greeter-runtime](features/greeter-runtime.md), [onboarding](features/onboarding.md)
- Layout: [surface-context](popouts/surface-context.md), [writing-modules](overlay/writing-modules.md)
