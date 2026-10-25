# Self-update

> **Files:** `services/core/SelfUpdateManager.qml`, `scripts/self_update.sh`, `config/SelfUpdate.qml`, `components/views/Settings/SelfUpdateStatusCard.qml`
> **Config:** `SelfUpdate.*` (reader `SelfUpdate`)
> **Related:** [Notifications](notifications.md), [Launcher](launcher.md)

Axiom updating its own git clone. This is not package updates, which are UpdatesManager's job.

A packaged axiom (`Paths.packaged`, [packaging.md](../packaging.md)) is updated by its package manager: `check()` returns at once, nothing is scheduled, `available` stays false, and the `SelfUpdate` section (`"/$packaged": false`), the onboarder's rows and launcher `/update` are hidden.

### Channels
`SelfUpdate.channel` picks what to follow on the clone's remote:
- **`tags`:** releases (`v*` tags).
- **`main`:** every commit on the remote's main (else master). The notes are the new commits' subjects.

A channel change triggers a recheck.

### The script
`scripts/self_update.sh [--channel tags|main] check|apply <target>` does the git work and prints one JSON object:
- `channel`, `current`, `commit`
- `latest`: the tag, or main's short commit
- `state`: `uptodate` | `available` | `diverged`
- `ahead`, `behind`
- `blocked`: `dirty` | `diverged` | `branch` | `nogit`
- `notes`, `error`
- `rebuilt`, `buildError`: after an `apply`, the axiom binary (`$AXIOM_BIN`, set by `axiom run`) built again from the updated clone (`scripts/generate.sh`, then `go build` beside it and swapped in), so its embedded schema is the tree's. Only a binary this user can replace (install.sh's in `~/.local/bin`); a failed build leaves the old one and says why, the update itself staying in.

What it will and won't do:
- It only fast-forwards: `merge --ff-only`, or a detached `checkout` when the clone is detached.
- It never stashes, resets or forces.
- Switching back from `main` to `tags` is never a downgrade: being ahead of the newest tag counts as `uptodate`.

### Modes (`SelfUpdate.mode`)
- **`auto`:** applies, notifies, then calls `Quickshell.reload`. git replaces files by inode, which the file watcher misses, so the explicit reload is needed.
  - With the binary rebuilt, it runs `axiom daemon reexec`: the new image takes the daemon over, and when the update changed the schema it restarts the shell (locked first when it was), whose hello would otherwise be refused ([backend](../backend/README.md) › Re-exec). A failed build is notified.
- **`notify`:** sends a notification whose `desktopEntry` (`axiom-update`) is a `NotificationManager.registerHandler` key. Clicking it runs `openSettings()`, which opens Settings → Updates (the `SelfUpdateStatusCard`).
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

### Testing
- Test the script on scratch clones.
- Never `apply` on the live repo. (Rule: AGENTS.md › Never, while testing.)
