# The greeter installer assumes git

> **Issue:** [The greeter installer assumes git](../issues.md#the-greeter-installer-assumes-git)
> **Status:** proposed

### Problem
Two things, designed together because both land in the same file: backend stage 4's last bullet ("`greeter/greeter_install.sh` last: it runs as root", [backend/roadmap.md](../backend/roadmap.md)) and the issue's git assumption.

**The script.** `scripts/greeter/greeter_install.sh` (583 lines of bash, awk and jq) is the last stage 4 script. It runs as root through pkexec ([greeter-install.md](../features/greeter-install.md)), so its shape has constraints the other ports didn't:
- **Root runs it by path.** The installed polkit action `org.axiom.greeter.manage` (`scripts/greeter/org.axiom.greeter.policy`) names `/usr/share/axiom-greeter/scripts/greeter/greeter_install.sh` by `exec.path`; `GreeterManager._helper` names the same path. The first install runs the clone's file (`pkexec /usr/bin/bash <clone>/scripts/greeter/greeter_install.sh`), every later one root's copy.
- **An update is run by the copy it replaces.** Every existing install has the bash helper as root's copy, so the first update after the port runs the old script, with the argv `install|update <repo> <user> <staged> <source> <channel> <binary>` and reading `{ok, changed, backup, error}` back. That argv and reply are a contract the port has to keep (or version, as the `binaries` marker line already does).
- **Its no-root half** (`check`, `hash`) runs as the user through `CommandManager.run(["bash", script, "check", …])` at startup, on the card and after each action; the hash reads every shipped file (`local`) or runs `git ls-remote` (`git`).
- jq is a runtime dependency only for it now (`install.sh` `REQUIRED`, `Packages.qml`; `DependencyManager`'s row still says "theme integrations", which went to Go in #138).

**The git assumption.** Part of the issue is already fixed, by the `package` source:
- `GreeterManager._source` is `Paths.packaged ? "package" : GreeterConfig.source`, so a packaged axiom never takes the git or local path; the script's `package` branch installs only `scripts/greeter/` and the snapshot and the greeter runs `/usr/share/axiom` itself ([packaging.md](../packaging.md) › A packaged shell: "always the `package` source … `Greeter.source` is hidden").
- Both AUR packages write `.packaged` and ship no `.git` (`packaging/aur/axiom-shell-git/PKGBUILD` removes it), and `GreeterSetup` says "The login screen runs the copy of axiom your package manager installed, so it updates with the system". Tested by `GreeterInstall.test_package_source`.

What's left is a tree with **no `.git` and no `.packaged`**: a release's "Source code" tarball unpacked by hand, or another distribution's package that doesn't write the marker. There the card still offers Git and Local and Install, and:
- `check`'s `url` is `""` and `currentHash` is `""` (git) or the hash of nothing (local: `git ls-files` fails, `sha256sum` of empty input), so the status never turns `outdated`;
- Install fails at root's prompt with `not a git clone: <repo>` (git) or `copying <repo> failed` (local).
Self-update settled the same case for itself (maintainer, 2026-10-27, "Show a note": "No .git: the card stays and says updates come from the package manager (no check, no apply)"; [self-update.md](../features/self-update.md) › Changes from the script).

### Options
#### A. `axiom greeter-install` as root, a three-line shim at the policy's path
- The root side is a Go subcommand, `axiom greeter-install install|update|uninstall <repo> <user> [<staged> [<source> [<channel> [<binary>]]]]`, the script's argv and reply unchanged. A pure package decides (the remote's newest `v*` tag or `main`, ssh→https, the greetd TOML line edit, `SHA256SUMS` matching, the `.greeter-source` line, the refusals), an edge package does it (root's bare mirror through `git`, the release download with Go's HTTP, the `go build` as greetd's user and `git ls-files` as the user through `runuser`, tar in Go, the staged swap, backups), all under `AXIOM_GREETER_ROOT` for tests.
- `scripts/greeter/greeter_install.sh` stays as a shim, so the policy, `_helper` and greetd's paths never change: `exec "$here/../../bin/axiom" greeter-install "$@"`, else `/usr/bin/axiom` (the package source, whose install folder has no `bin/`). Never `PATH` or `$AXIOM_BIN` (pkexec clears the environment).
- **Migration is free:** the old bash helper's update copies the new tree (shim included) and its binary, then reinstalls the policy from it; the next update runs the shim. No marker needed while the argv stays.
- `check` / `hash` become a daemon method, `greeter.status` (no root, as `selfupdate.status`), and the daemon runs the pkexec too (`greeter.apply { action, source, channel, staged }`, only from the shell), choosing root's helper or the first-install program as `GreeterManager._runElevated` does now.
- **Cost:** the largest (estimate ~950 lines of Go, ~−150 of QML, tests apart); the subcommand runs as root, so `cli.Main` must reach it before touching anything of the user's (no log file, XDG dirs or daemon socket), with a test. The first install runs the user's `$AXIOM_BIN` as root, the same trust as `pkexec bash <clone's script>` today.
- jq leaves the dependencies; the shell-side `bash` call and its JSON parsing go.

#### B. Go for the no-root half only; bash stays for root
- `greeter.status` replaces `check` / `hash` as in A; the script keeps install, update and uninstall.
- **Cost:** about a third of A. **Risk:** none of migration (root's side doesn't change). **Leaves out:** the point of stage 4: bash, awk and jq keep running as root, two languages implement the same source rules (the url, the hash) and must agree, and jq stays a dependency. "go is the forever home" argues against it.

#### C. As A, but polkit names the binary itself
- No shim: the policy's `exec.path` becomes `/usr/share/axiom-greeter/bin/axiom`.
- The old helper still migrates it (it installs the new copy's policy).
- **Cost:** the package source has no `bin/` (its binary is `/usr/bin/axiom`), so it'd either copy the package's binary into the install folder (then a package upgrade doesn't reach the greeter until Update) or name `/usr/bin/axiom`, whose every pkexec would then show the login screen's prompt. `greeter-session.sh` and the shim's two-line fallback logic are kept anyway. Saves three lines of shell for a worse package case.

#### The no-`.git` tree (any option)
- **i. Show a note** (self-update's decision): with no `.git` and no `.packaged`, the card hides Git and Local and says the login screen needs a clone or a package; `greeter.status` reports it (`clone: false`), Install isn't offered.
- **ii. Git from the official repository:** the `git` source falls back to axiom's own url (`https://github.com/axiom-shell/axiom`) when there's no clone to read a remote from, so a tarball install gets release tags and their prebuilt binaries. Local stays hidden. Small in Go (the url is a constant beside the release url logic), but it installs code from a source the user didn't pick.

### Recommendation
**A with i.** It finishes stage 4 for real (nothing of bash, awk or jq as root; one implementation of each source rule, tested in Go), and the shim makes the riskiest part, existing installs updating through the old helper, need no new code: it's the path every update already takes. The no-`.git` tree follows self-update's note, the decision already made for the same tree; ii can follow later if tarball users ask.

Size: A is about 950 changed lines (tests and docs apart), past the ~800 gate. Splitting it (B first, the root side second) leaves two implementations of the source rules for one PR's time; one PR like CalDAV keeps the contract and its tests in one review. Recommended: **waive the gate, one PR** (or two, in the order below, if not waived).

### Items
1. **The installer in Go** (one PR, or 1a + 1b): 1a `greeter.status` / `greeter.apply` (a new pure + edge package pair and a daemon part), `GreeterManager` on them, the no-`.git` note (`clone` in the report, `GreeterSetup` hides Git and Local); 1b `axiom greeter-install` (root, reached before anything of the user's is opened), `greeter_install.sh` reduced to the shim, `GreeterInstall` tests moved to Go (the shim's own case stays in `test_scripts.py`), a Go test that runs the old script's update from git history onto a scratch root and then the new shim, jq dropped (`install.sh`, `Packages.qml`, `DependencyManager`, check_packages), docs ([greeter-install.md](../features/greeter-install.md) › Changes from the script, backend/roadmap.md's bullet `Done`).

### Questions for the maintainer
1. Who runs as root: A (Go subcommand behind a shim at today's path), B (bash stays for root) or C (polkit names the binary)?
2. The no-`.git`, no-`.packaged` tree: i (a note, Git and Local hidden) or ii (git from the official repository)?
3. Waive the ~800-line gate for one PR, or split status (1a) and the root side (1b)?
4. Keep the script's argv and reply as the root contract (A's free migration), or version it now (a `--json` reply, named flags) at the cost of a marker check like `binaries` for old helpers?
5. The first install runs the user's `$AXIOM_BIN` as root (as today's runs the user's script). Keep that, or require a root-owned binary (the package's, else a release download verified by `SHA256SUMS` before anything runs as root)?
