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

### 7. check_structure's Quickshell.Io check doesn't see IpcHandler  `scripts/check_structure.py:65`
**Fix:** add `IpcHandler` to `IO_KINDS`.

### 8. The permission deny list names a config path that's gone  `.claude/settings.json`
`rm config/user/config.json` (folder gone); `git clean -x` refused but named nowhere else.
**Fix:** drop the stale lines; name or drop `git clean -x`.

## Contract
Holds: every AGENTS.md › Never rule has a guard rule and a `test_guard.py` case for its plain form (lock, cursor, takeover via Edit/Write and `--takeover`, compositor claim/release and binds remove on live dirs, niri quit/load-config/output, hookup/selfupdate/greeter apply, the greeter only windowed on scratch, greetd, daemon lifecycle and dev mode, gh issue, force-push and main). IpcTarget registers only with axiom, so `qs ipc` can't reach the lock screen (SAFE_QS is safe). The allowlist is a true ratchet (unused entries fail). CI's checks/qt/go/scripts jobs together run every check check_all.sh runs (plus JSON validity, which check_all lacks: the known "three places" entry, now with that evidence). The go job's path filter is wider than verify.sh's go trigger, as its comment says. Every methods helper but IconResolver has a test (known). No singleton outside the pure helpers and compositor backends is over 800 lines, though nothing checks it (Phase 11's ratchets bullet). AGENTS.md is 24 KB against Phase 9's 12 KB target (known).

## Coverage
Read deeply: scripts/dev/verify.sh, scripts/check_all.sh, scripts/check_go.sh, scripts/generate.sh, scripts/run_tests.sh, .githooks/pre-commit, .github/workflows/checks.yml, .claude/hooks/guard.py, tests/scripts/test_guard.py (Bash/Axiom cases), .claude/settings.json, check_qmllint.py main, check_structure.py's allowlist check, check_i18n.py main, the skills' SKILL.md files · Outlined: check_docs.py, check_sizes.py, gen_docs.py, test_scripts.py, tests/RepoFiles.qml, the Go tests' skips · Skipped: the recipes and AGENTS.md text (the agent-rules batch of step 0 reads them against past failures), ci_summary.py, fixtures.py, popout_matrix.py, bench/mem/shot/nested scripts (dev tools, not gates), release.yml and edge.yml (packaging).

## History
- 2026-10-29 full: 8 findings; recorded in issues.md
