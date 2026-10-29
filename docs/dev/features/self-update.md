# Self-update

> **Files:** `services/core/SelfUpdateManager.qml`, `backend/internal/selfupdate/selfupdate.go`, `backend/internal/daemon/selfupdate.go`, `backend/internal/release/`, `config/SelfUpdate.qml`, `components/views/Settings/SelfUpdateStatusCard.qml`
> **Config:** `SelfUpdate.*` (reader `SelfUpdate`)
> **Related:** [Notifications](notifications.md), [Launcher](launcher.md), [Backend](../backend/README.md) › Re-exec

Axiom updating its own git clone. This is not package updates, which are UpdatesManager's job.

A packaged axiom (`Paths.packaged`, [packaging.md](../packaging.md)) is updated by its package manager: `check()` returns at once, nothing is scheduled, `available` stays false, and the `SelfUpdate` section (`"/$packaged": false`), the onboarder's rows and launcher `/update` are hidden.

A tree that isn't a git clone otherwise (no `.git`: installed some other way) is updated by whatever installed it: `selfupdate.status` says `blocked: "nogit"` without running git, `managed` is true, nothing is checked or scheduled, launcher `/update` is hidden, and the card stays, saying its updates come from the package manager (no Check now, no Update).

### Channels
`SelfUpdate.channel` picks what to follow on the clone's remote:
- **`tags`:** releases (`v*` tags).
- **`main`:** the remote's main (else master). With an official build of main ([edge](../packaging.md), a check reads its `COMMIT`), its target is the commit that build was made from, even when main has moved on since, so the binary downloaded for it is that commit's; the check records it as `refs/axiom/edge` in the clone, so a status, an apply and a restarted daemon aim at it without fetching (a commit the clone can't fetch isn't recorded). With none, main's head. The notes are the new commits' subjects.

A channel change triggers a recheck.

### The daemon's methods
`backend/internal/selfupdate` does the git work on the tree the daemon runs from (`daemon/selfupdate.go`), one call at a time; each method takes `{ channel, target? }` and answers one report:
- `selfupdate.status`: the clone from the refs it has, without fetching (at every shell load, for the installed version and `managed`).
- `selfupdate.check`: fetches (`v*` tags; on main the branch too, else master; a minute at most, never prompting for a password or host key), then describes. A failed fetch still describes the clone, with git's reason as `error`.
- `selfupdate.apply`: only from the shell. `target` must be the `latest` a check reported, still available and not blocked; it runs to the end once started.

The report:
- `channel`, `current`, `commit`
- `latest`: the tag, or main's short commit
- `state`: `uptodate` | `available` | `diverged`
- `ahead`, `behind`
- `blocked`: `dirty` | `diverged` | `branch` | `nogit`
- `notes`, `error`
- `rebuilt`, `binarySource`, `buildError`: after an `apply`, whether the installed axiom binary (the one the daemon came from) was replaced to match the updated clone, so its embedded schema is the tree's, and from where (maintainer, 2026-10-27: "Download, build fallback (Recommended)"):
  - `release` / `edge`: the official build of the commit now checked out, downloaded and checked against its `SHA256SUMS` (`release/fetch`): the tag's release on `tags`; on `main`, main's newest build, only when its `COMMIT` is the clone's head. Written beside the binary, checked to run (`version`) and swapped in.
  - `built`: else (no build for this machine or commit, offline, a sum that doesn't match, which is logged), built from the tree: `go generate ./internal/assets`, then `go build -trimpath` beside it, checked to run and swapped in (dev mode's `buildAxiom`). Without `go`, `buildError` says so.
  - Only a binary this user can replace (install.sh's in `~/.local/bin`); a failed build leaves the old one and says why (the compiler's first line), the update itself staying in.

What it will and won't do:
- It only fast-forwards: `merge --ff-only`, or a detached `checkout` when the clone is detached.
- It never stashes, resets or forces.
- Switching back from `main` to `tags` is never a downgrade: being ahead of the newest tag counts as `uptodate`.

### Modes (`SelfUpdate.mode`)
- **`auto`:** applies, notifies, then calls `Quickshell.reload`. git replaces files by inode, which the file watcher misses, so the explicit reload is needed.
  - With the binary replaced, the daemon re-execs into it once its reply is out: the new image takes the daemon over, and when the update changed the schema it restarts the shell (locked first when it was), whose hello would otherwise be refused ([backend](../backend/README.md) › Re-exec). A failed build is notified.
- **`notify`:** sends a notification whose `desktopEntry` (`axiom-update`) is a `NotificationManager.registerHandler` key. Clicking it runs `openSettings()`, which opens Settings → Updates (the `SelfUpdateStatusCard`). A successful update takes the earlier notifications of that entry away before it notifies the new version.
- **`off`:** never checks.

### When it checks
- Once per qs launch. A `PersistentProperties` flag stops hot reloads from rechecking.
- Then daily.
- `~/.local/state/axiom/ui/selfupdate.json` keeps:
  - `lastChecked`;
  - `notifiedTag`, so each release is notified once;
  - the last result.

### Entry points
- IPC `selfUpdate`: `check`, `update`, `open`.
- Launcher `/update`.
- Created from `shell.qml`'s `_services`.

### Changes from the script
- A tree with no `.git` is `managed` (the decision above): the card says its updates come from the package manager instead of "Can't update: it isn't a git clone", and nothing checks it. Its report has no `error`.
- `selfupdate.status` is new: the card shows the installed version and whether it's a clone at once, not after the first check.
- The daemon rebuilds and re-execs itself after an update; the shell no longer runs `axiom daemon reexec`. The build is `go generate` and `go build` alone: the tree's generated `config/json/config.schema.json` (the tools' copy; the daemon builds the shell's from the YAML) isn't rebuilt.
- git runs in the C locale (its messages parse the same in every language), and a tag's SSH signature is cut from the notes as a PGP one was.
- An unknown channel or an apply without a target is a `bad_request` error rather than a report.

### Testing
- `go test ./internal/selfupdate` runs on scratch clones (upstream and clone in a temp dir); `TestReplaceInstalled` (daemon) on a served release and a fake go.
- Never `selfupdate.apply` (or IPC `selfUpdate update`) on the live daemon: it updates the live repo. (Rule: AGENTS.md › Never, while testing; the guard refuses it.)
