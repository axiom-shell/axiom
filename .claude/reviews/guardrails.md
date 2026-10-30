# guardrails
reviewed: 12a20a0 2026-10-29  (full)

The checks hold the rules they were written for, but they have holes at their edges: verify.sh ignores deleted files and a check's own change, the guard is dodged by ordinary compound commands and by any Bash write onto config.json, CI runs the Go tests as root (six refusal-path tests skip), and three checks (check_go.sh without `--ci`, check_i18n.py, the qmllint baseline) can't fail on what they claim to catch. All recorded in issues.md (row 18); nothing fixed in this review.

## Open findings
### 1. verify.sh skips the checks a deletion or a check's own change needs  `scripts/dev/verify.sh:44`
`changed` drops paths that don't exist, so a deletion triggers no Go checks or check_docs, and a deletion-only change prints `nothing changed since HEAD`. check_docs runs only for `.md`/`.qml` changes (not schema YAML, not check_docs.py itself); qmllint and sizes only for QML; the CheckDocs script tests aren't mapped; `.githooks/pre-commit` isn't shellchecked.
**Fix:** keep deleted paths for the triggers; map each `scripts/check_*` file to its own check.

### 2. The guard misses compound commands, wrapper options and writes onto config.json  `.claude/hooks/guard.py:47`
Allowed: `(qs kill)`, `{ qs kill; }`, `$(qs kill)`, `if true; then qs kill; fi`, `sudo -u me axiom lock`, `nice axiom lock`, `flock f axiom lock`, `systemd-run --user axiom quit`, `gh -R a/b issue create`, and `cp`/`mv`/`>`/`tee`/`sed -i` onto the live config.json (no x-takeover check, unlike Edit/Write), `rm -r ~/.config`, `find … -delete`.
**Fix:** split on grouping and keywords, skip wrapper option values, match `issue create` anywhere, refuse Bash writes to LIVE_CONFIG; a test each.

### 3. CI's Go tests run as root  `.github/workflows/checks.yml` (go job)
Six tests skip on `os.Geteuid() == 0`, the unreadable/unwritable-file refusal paths.
**Fix:** run `check_go.sh --ci` as an unprivileged user in the container.

### 4. check_go.sh passes stale generated code except under --ci  `scripts/check_go.sh:52`
check_all.sh (no `--ci`) passes what CI fails.
**Fix:** fail on stale generated code whenever `--fix` isn't given.

### 5. CI can't fail on stale translation files  `scripts/check_i18n.py:248`
Untranslated keys (normal) and real errors (stale template, format, absent or unused keys) share exit 1, so CI runs it with `continue-on-error`.
**Fix:** exit 1 only for the real errors; drop `continue-on-error`.

### 6. The qmllint baseline doesn't shrink  `scripts/check_qmllint.py:133`
Gone warnings only print a note; the baseline keeps their count.
**Fix:** fail (or rewrite the baseline) when counts drop.

### 7. (withdrawn) check_structure's Quickshell.Io check doesn't see IpcHandler
Wrong: `check_structure.py` refuses any `IpcHandler {` outright (the IpcTarget rule), which is stronger than an allowlist kind. Entry dropped 2026-10-29 in the inventory.

### 8. The permission deny list names a config path that's gone  `.claude/settings.json`
`rm config/user/config.json` (folder gone); `git clean -x` refused but named nowhere else.
**Fix:** drop the stale lines; name or drop `git clean -x`.

## Inventory
2026-10-29, at 25e0d3f. CI history: of the last 200 Checks runs (back to 2026-10-24) 183 were green, 8 failed and 9 cancelled; every failure since 2026-10-26 was a Go timing or resource flake on a PR that didn't cause it (before that, script tests, qmlformat, qmllint and unit tests caught real breaks in the big pre-roadmap PRs). Costs are from the last green run. "Fails" counts the failing step across all 27 failed runs (back to 2026-09-26).

| Guardrail | Catches | Fails | Cost | Gets past it |
|---|---|---|---|---|
| CI `checks` job (structure, sizes, docs, packages, JSON, i18n) | layout, layering, px sizes, stale doc citations, package drift, bad JSON | 1 (docs) | 81 s (generate 36 s) | i18n `continue-on-error`; JSON step not local |
| CI `qt` job (qmlformat, qmllint, unit tests) | formatting, new lint warnings, methods helpers' behaviour | 12 (5 fmt, 2 lint, 3 unit, 2 script tests before they had a job) | 98 s (generate 43 s) | baseline never shrinks |
| CI `go` job (`check_go.sh --ci`, fixtures index) | Go build, vet, staticcheck, tidy, tests with -race, vulns | 10; the 8 since 10-26 all flakes | 204 s (checks 172 s) | runs as root (6 skips); skipped on non-Go PRs, no schedule |
| CI `scripts` job (shellcheck, script tests, guard tests) | shell bugs, script behaviour, guard rules | 7 | 57 s (generate 28 s; tests <1 s) | only 8 test classes |
| `scripts/generate.sh` | stale schema, embedded assets, generated docs, shell/daemon rpc mismatch | (in each job) | 28–43 s per job, four times, nearly all compiling the binary; since batch 10 only the `checks` and `go` jobs compile it (`--no-docs` builds the schema with `syncassets`: 5 s and 2 s cold locally for the `qt` and `scripts` jobs' generate, against ~12 s) | nothing shared between jobs (no artifacts); since batch 10's follow-up the `checks` and `go` jobs keep Go's build and module caches across runs (`actions/cache`, the one action the repository allows; tests still `-count=1`) |
| `scripts/check_structure.py` | ~25 rules: type folders, imports, Io allowlist, IpcHandler, compositor and Hyprland gates, singleton typos, `??` in readers, pragmas | 0 standalone | 3 s | no tests of its own; several AGENTS.md rules unchecked (animation literals, `Qt.formatDateTime`, `Quickshell.screens`, polling Timers in UI, Repeater models from live values) |
| `scripts/check_sizes.py` | literal px outside the bars | 0 | 1 s | one-line expressions only (1 multi-line binding today) |
| `scripts/check_docs.py` | dead links, paths, `Singleton.member`, issue links, annotation list | 1 | <1 s | Go symbols in `(Name)` not checked; triggers miss YAML |
| `scripts/check_packages.py` | install.sh / Packages / PKGBUILD drift | 0 | <1 s | untested |
| `scripts/check_i18n.py` | stale template, format, absent/unused keys | never (warning) | <1 s | can't fail in CI |
| `scripts/check_qmllint.py` + baseline | new qmllint warnings | 2 | 12 s | baseline doesn't shrink; untested |
| `scripts/check_qmlformat.sh` | unformatted QML | 5 | 5 s | — |
| `scripts/check_go.sh` | see go job | — | ~3 min | stale generated code passes without `--ci` |
| `scripts/run_tests.sh` + 62 `tests/tst_*.qml` | methods helpers, schema defaults, shared fixtures | 3 | 4 s | IconResolver untested; a misnamed test function silently doesn't run |
| Go tests (74 of 88 packages) | daemon, store, compositor writers, migrations, greeter installer | 10 (8 flakes) | most of 172 s | 18 files with their own waits; 14 packages untested (mostly tools, test doubles, wayland protocol bindings); no mutation run |
| `scripts/gen_docs.py` | rpc mismatch (fails); config/API/IPC/layers maps | 0 | in generate | misses `ConfigManager.live`: 372 of 676 settings shown unread, unused-member report blind; report never fails |
| `scripts/gen_theme_template.py` | stale theme template (`--check` in Themes tests) | 0 | <1 s | — |
| `scripts/check_doc_drift.py` | docs behind their files (warning, verify.sh and CI summary) | never (by design) | <1 s | justified: a nudge, not a gate |
| `scripts/dev/verify.sh` | the changed-file subset of everything, plus the live log | — | 10–60 s; measured 2026-10-30 (warm caches), before → after batch 10: a one-line QML edit 15 → 11 s, a schema edit 42 → 27 s, a Go edit 32 → 27 s (generate.sh ran twice, the log waited 3 s for a reload already past) | deletions and a check's own change trigger nothing; prints no `verify ok` on a clean branch |
| `scripts/check_all.sh` | every CI check, locally | — | ~5 min | lacks the JSON step; `check_go.sh` without `--ci` |
| `.githooks/pre-commit` | i18n keys, theme template | — | seconds | opt-in (`core.hooksPath`); `--no-verify` skips it and CI doesn't catch it (i18n) |
| `.claude/hooks/guard.py` + `tests/scripts/test_guard.py` (31 cases) | AGENTS.md › Never, plain forms | — | per command | compound commands, wrapper options, Bash writes onto config.json |
| `.claude/settings.json` deny list | the plain forms again | — | — | one stale path |

## Mutation run
2026-10-30, at 763264a (Phase 11 step 0 batch 8; how it was run: `docs/dev/testing.md` › Mutation runs). Each package's own tests against one mutant at a time; "killed" counts failing tests, timeouts (a dropped unlock deadlocks) and vet failures. Before → after this batch's tests:

| Package (files, sample) | Mutants | Killed before → after | Survived before → after | Left |
|---|---|---|---|---|
| `lockscreen` (lockscreen.go, all) | 64 | 51 → 54 | 13 → 10 | 10 equivalent (log lines) |
| `store` (store.go: the takeover, write, load and reload functions) | 138 of 270 | 102 → 112 | 36 → 26 | 14 equivalent (logs, a redundant TakeoversFile write, `at` on a non-object); 12 filed |
| `share` (KeepTakeovers, annotated) | 23 | 19 → 20 | 4 → 3 | 3 equivalent (schema depth bound) |
| `greeterinstall` (elevate.go, greeterinstall.go, install.go, all) | 421 | 344 → 377 | 75 → 44 | 6 equivalent; 38 filed (I/O error returns, cleanup, root-only branches) |
| `migrate/steps` (all) | 119 | 113 → 117 | 6 → 2 | 2 equivalent (ties: v79.go:32, v81.go:117 `>`→`>=` on a 40-character name) |
| `migrate/convert` (every 4th) | 108 of 431 | 87 → at least 103 | 21 → at most 5 | equivalent: the ties `<`→`<=` at :116 and :721 and `>=`→`>` at :136, and :635 and :955 (a deleted key re-set by `insertAt` keeps its place either way); every other mutant on the 21 lines killed by hand |

Two `greeterinstall` mutants (New's default `pkexec`) reached the real pkexec in the first pass and timed out on its prompt; the rerun puts refusing stand-ins for pkexec, sudo, su, doas and run0 first on PATH, and counts them killed. A fake-root pass (`unshare -rm`) over the 45 `greeterinstall` survivors killed one more (install.go:132); nothing needed real root. Filed: issues.md › Mutants that survive in migrate, › Mutants that survive in the store's and the installer's failure paths (fix batches 12 and 13). Fixed here: an uninstall in the same second as the install overwrote the backup it restores (found writing a test; `TestUninstallInTheInstallsSecond`). Batch 12 (the migrate survivors): `TestConvertShapes`, `TestConvertNotesItsChanges` and `TestV81FoldsCommandOutput` rows, each listed line's mutants applied by hand through `go test -overlay`; which of a line's mutants the sample took isn't recorded, so the after-counts take the equivalent ones.

## Contract
Holds: every AGENTS.md › Never rule has a guard rule and a `test_guard.py` case for its plain form (lock, cursor, takeover via Edit/Write and `--takeover`, compositor claim/release and binds remove on live dirs, niri quit/load-config/output, hookup/selfupdate/greeter apply, the greeter only windowed on scratch, greetd, daemon lifecycle and dev mode, gh issue, force-push and main). IpcTarget registers only with axiom, so `qs ipc` can't reach the lock screen (SAFE_QS is safe). The allowlist is a true ratchet (unused entries fail). CI's checks/qt/go/scripts jobs together run every check check_all.sh runs (plus JSON validity, which check_all lacks: the known "three places" entry, now with that evidence). The go job's path filter is wider than verify.sh's go trigger, as its comment says. Every methods helper but IconResolver has a test (known). No singleton outside the pure helpers and compositor backends is over 800 lines, though nothing checks it (Phase 11's ratchets bullet). AGENTS.md is 24 KB against Phase 9's 12 KB target (known).

## Coverage
Read deeply: scripts/dev/verify.sh, scripts/check_all.sh, scripts/check_go.sh, scripts/generate.sh, scripts/run_tests.sh, .githooks/pre-commit, .github/workflows/checks.yml, .claude/hooks/guard.py, tests/scripts/test_guard.py (Bash/Axiom cases), .claude/settings.json, check_qmllint.py main, check_structure.py's allowlist check, check_i18n.py main, the skills' SKILL.md files · Outlined: check_docs.py, check_sizes.py, gen_docs.py, test_scripts.py, tests/RepoFiles.qml, the Go tests' skips · Skipped: the recipes and AGENTS.md text (the agent-rules batch of step 0 reads them against past failures), ci_summary.py, fixtures.py, popout_matrix.py, bench/mem/shot/nested scripts (dev tools, not gates), release.yml and edge.yml (packaging).

## History
- 2026-10-29 full: 8 findings; recorded in issues.md
- 2026-10-29 inventory: 3 new entries (gen_docs misses `ConfigManager.live`, Go test waits, untested check scripts); finding 7 withdrawn; step 0 split into batches (roadmap.md)
- 2026-10-30 speed (batch 10): generate.sh's schema without the binary, verify.sh's double generate and reload wait (Inventory › Cost)
- 2026-10-30 mutation run: 873 mutants over 6 packages; the security paths' survivors got tests, the rest equivalent or filed (Mutation run)
