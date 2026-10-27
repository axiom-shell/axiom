# Greeter: install, update, status

> **Files:** `services/session/GreeterManager.qml`, `config/GreeterConfig.qml`, `backend/internal/greeterinstall/`, `backend/internal/daemon/greeterinstall.go`, `scripts/greeter/greeter_install.sh`, `scripts/greeter/org.axiom.greeter.policy`, `components/views/Settings/GreeterStatusCard.qml`, `components/forms/GreeterSetup.qml`
> **Config:** `Greeter.enabled`, `Greeter.source`, `SelfUpdate.channel` (reader `GreeterConfig`)
> **Related:** [Greeter runtime](greeter-runtime.md), [Lockscreen](lockscreen.md), [Self-update](self-update.md), [Polkit](polkit.md), [Shell targeting](../core/shell-manager-targeting.md)

Axiom as greetd's login screen, laid out like the lock screen. This doc covers the user-side half: installing, updating and removing the root-owned copy, and the status the card shows. For what runs at the login screen (the bundle, the session script, greeter mode, GreetdManager, modules), see [greeter-runtime.md](greeter-runtime.md). (Rule: AGENTS.md › UI conventions › Greeter; never install or update the greeter for real, or restart greetd.)

### Overview
- Off by default.
- Set up from Settings → Screen & Power → Login screen (`views/Settings/GreeterStatusCard`) or from the onboarder's Integrations page. Both go through `forms/GreeterSetup`.
- The greeter runs as greetd's user, who can't read the user's home, so it runs from a copy and reads an export (the [bundle](greeter-runtime.md#the-bundle)).
- `GreeterManager` is created from `shell.qml`'s `_services`.

### Install / update / uninstall
- **Calls:** `GreeterManager.install` / `update` / `uninstall`, through the daemon's `greeter.apply` (`{ action, source, channel, staged }`, only from the shell; `backend/internal/daemon/greeterinstall.go`). Each needs one polkit prompt. The reply is the installer's `{ ok, changed, backup, error }`, plus `dismissed` when the prompt was dismissed.
- **The installer** is `axiom greeter-install install|update|uninstall <repo> <user> [<staged bundle> [<source> [<channel> [<binary>]]]]` (`backend/internal/greeterinstall`, the pure `greeterinstall/rules` deciding), printing one JSON object, `{ ok, changed, backup, error }`. `cli.Main` hands it over before anything else, so nothing of the user's (XDG folders, a log file, the daemon's socket) is opened as root. `scripts/greeter/greeter_install.sh` is only its shim: it stays at the path polkit and greetd's setup name and runs the binary installed beside it (`../../bin/axiom`), else `/usr/bin/axiom` (the package source's install folder has no `bin/`), never one found through `PATH` or `$AXIOM_BIN`.
- **How it is run** (the daemon runs pkexec, `greeterinstall.Elevate`):
  - Until the greeter is installed, only a binary root owns or one checked against its release (maintainer, 2026-10-27: "root owned checksum verified binary"; `greeterinstall.firstProgram`), `pkexec <binary> greeter-install <action> <repo> <user> …`: for `package`, the package's `/usr/bin/axiom` (refused unless root's and writable by no one else); for `git`, the newest release's prebuilt binary, downloaded by the daemon and checked against the release's `SHA256SUMS`, then handed to root on stdin: pkexec runs `/bin/sh` (`greeterinstall.verifyAndRun`), which writes it into a new folder only root can use, under `/var/lib/axiom-greeter` (not `/tmp`, which may be mounted noexec; refused when that folder is a link or not root's; removed afterwards), and checks it there against the official release's `SHA256SUMS` root fetches itself (`curl`) before running it: the user supplies the bytes, never the sum they're checked against, and nothing of theirs can swap the file after the check. The `main` channel, and a release with no binary for this machine, are refused before any prompt. That `curl` runs in pkexec's cleared environment, so proxy settings are ignored (maintainer, 2026-10-27: "ignore proxies"); for `local`, the binary the user's daemon runs (`Request.Binary`), unchecked.
  - Once installed: `pkexec /usr/share/axiom-greeter/scripts/greeter/greeter_install.sh …`, root's copy.
- **Root's copy afterwards:** the installed polkit action `org.axiom.greeter.manage` (`scripts/greeter/org.axiom.greeter.policy`) names that copy by `exec.path`.
  - Its prompt says what it's for.
  - The user's own file never runs as root again; `greeter.status` reports `helper`.
- **Compatibility:** an update is run by the copy it replaces, so the arguments and the reply are a contract between versions (`rules.Request`, `rules.Result`; maintainer, 2026-10-27: "Keep argv (Recommended)"): a new argument goes last. An install made before the port updates through its bash helper, which copies the new tree (the shim with it) and its binary; the next update runs the shim (`cli.TestOldInstallerUpdatesToTheShim`). The status's `binaries` says whether the installed helper installs the binary too (its marker line, which the shim keeps); while it doesn't, the daemon runs the first-install program instead, so a copy is never left without its binary.
- **Root-free:** the status, `greeter.status` (`{ source, channel }`), runs in the daemon as the user (`greeterinstall.Status`), as the script's `check` and `hash` did.
- **The user argument:** under pkexec, `<user>` must be `$PKEXEC_UID`'s.

#### What gets copied
- The code, minus tests, docs and `*.md`.
- **From:** `Greeter.source` (`GreeterConfig.source`), passed as the installer's `<source> <channel> <binary>` arguments. The channel is `SelfUpdate.channel`; `<binary>` is the axiom binary the user built last (below).
- **The binary** the greeter runs (`axiom greeter`, [greeter-runtime.md](greeter-runtime.md)) goes in the copy's `bin/axiom`, by source (below); a package's is its own, on `PATH`.
- **To:** `/usr/share/axiom-greeter`, owned by root.
  - `.greeter-source` says where the copy came from: `"git <channel> <url>"`, `"local"` or `"package <dir>"`.
  - `.greeter-hash` names the version.
- **Source `git`** (default):
  - It fetches as root into its own bare mirror, `/var/lib/axiom-greeter/upstream.git`.
  - It takes the channel's newest `v*` tag (peeled, in version order: `git ls-remote --sort=-v:refname`), or `main`/`master`.
  - It finds them with `git ls-remote` on the official repository, `rules.Repository` (`https://github.com/axiom-shell/axiom.git`; maintainer, 2026-10-27: "Pin mirror too": the git source always installs official code and binary, and a fork uses `local`). The clone's remote never counts.
  - A copy recorded from another url (a fork, before the pin) shows as `outdated` when its hash isn't the official one's, and its update takes the official code and records its url.
  - The hash is the commit.
  - **Its binary:** the tag's release's prebuilt `axiom-linux-<amd64|arm64>` from the official repository's release (`rules.Releases`, `https://github.com/axiom-shell/axiom/releases/download/<tag>/`; maintainer, 2026-10-27: "pin official repo"), checked against that release's `SHA256SUMS`: root runs it at the next update, so nothing else is taken, and the sums prove it's an official release's. A mismatch fails the install; so does a release without one (a tag the official repository hasn't released, a release with no binary: none has one yet) and the `main` channel, which has no release (maintainer, 2026-10-27: "Refuse the install (except for if you have the local clone install path selected, in which case it reuses your most recently built binary, and skips the checksum)"). The old copy stays.
- **Source `local`:**
  - It archives the clone's tracked files as they are in the working tree: whatever branch, uncommitted changes included.
  - It uses `git ls-files` + `tar`, run as the user (their uid, groups and `HOME`), so the clone's config and filters never run as root; root unpacks the archive in Go, confined to the new copy (`os.Root`), regular files only.
  - The hash is the files' content, the binary's Go source (`backend/`) included, so docs-only edits are not an update. `backend/` is left out of the archive.
  - **Its binary:** `<binary>`, the binary the user built last (the daemon's running image: a dev build while dev mode is on, else the installed one), read as the user (root follows none of their links), refused unless it's an ELF file. Unchecked: the same trust as copying the working tree.
- **Source `package`** (always, for a packaged axiom: `GreeterManager.wantedSource` ignores `Greeter.source`, which is hidden; [packaging.md](../packaging.md)):
  - The greeter runs `/usr/share/axiom` itself (always that path, never `<repo>`), and the package manager updates it.
  - The install folder gets only `scripts/greeter/` (what greetd and polkit name by path), `.greeter-source` and the snapshot. The session script reads `.greeter-source` to find the code.
  - It refuses without `.packaged`, or when the package's folder or its `scripts/greeter/` isn't root's: its `greeter_install.sh` becomes the helper polkit runs as root.
  - The hash is the package's version (the marker's text), so a package update shows as `outdated` until **Update** refreshes the scripts and the snapshot.
- **Refusals and safety:**
  - A copy without `greeter.qml`, the session script or the policy (a release from before the login screen) is refused.
  - `ext::` transports are off, and git never prompts.
  - A copy that can't be swapped in leaves the old one in place.
  - It refuses without `agreety` (`greetd-agreety`), the fallback login.
  - It refuses without sway or Hyprland's `start-hyprland` (in `/usr/bin` or `/usr/local/bin`), what `greeter-session.sh` runs the login screen in; the status reports which as `compositor`. The onboarder's Checks page lists it too (`DependencyManager.tools`' `sway`, with `start-hyprland` as its alternative).

#### Then it sets up
- **`/var/lib/axiom-greeter`:**
  - `config/` is the user's: the bundle.
  - `state/` is greetd's user's: the last user and their sessions (`GreetdManager`'s `greeter` state).
- **Fallback snapshot:** it snapshots the bundle as the copy's `fallback/`.
  - The source is `<staged bundle>`, `$XDG_RUNTIME_DIR/axiom/greeter-bundle`. Axiom writes it just before install and update, since a first install has no bundle yet.
  - It reads with `openat2(RESOLVE_NO_SYMLINKS)`: the folder is the user's, and root never follows a link there.
- **greetd:** it points greetd's `default_session` `command` at `scripts/greeter/greeter-session.sh`.
  - First it backs up `/etc/greetd/config.toml`: `.axiom-original` once, plus `.axiom-bak-<date>` per change.
  - The edit is line-wise and keeps the config's `user`.
- **Uninstall** puts the original config back and deletes `.axiom-original`, so a later install backs up the config as it is then.

#### Around the prompt
- While pkexec waits, the overlay and the onboarder step aside, unless axiom's own polkit agent is running ([SurfaceManager](../core/shell-manager-targeting.md#stepping-aside)).
- `finishCommands` are what the user runs to make greetd the display manager (`readlink display-manager.service`). The card shows them as `CodeLine`s.

### Status
`GreeterManager.check()` asks `greeter.status` at startup, on the card, and after each action. The states are:

| State | Meaning |
|---|---|
| `checking` | A check is running. |
| `checkFailed` | The first check failed. `lastError` says why; Check again retries. |
| `noGreetd` | greetd or agreety is missing. |
| `noCompositor` | Neither sway nor Hyprland (`start-hyprland`), which the login screen runs in, is installed (the status's `compositor` is `""`). Install refuses then. An installed copy keeps its status (so Remove stays), and `GreeterSetup` warns that it falls back to agreety. |
| `noClone` | axiom's tree is neither a git clone nor a package (no `.git`, no `.packaged`: a release's source unpacked by hand, another distribution's package), so git and local have nothing to take (the status's `clone` is false; it runs no git then). `GreeterSetup` says the login screen needs a clone or a package, Install isn't offered and `Greeter.source` is hidden (`"/$clone": true`). An installed copy keeps its status, with Remove and the note, but no Update. |
| `off` | The greeter is off. |
| `notInstalled` | `Greeter.enabled` is set, but there is no copy. |
| `outdated` | One of: the copy's hash isn't its source's current one; `installedSource` isn't `GreeterManager.wantedSource` (the setting changed); greetd's command changed. A git remote that can't be reached (`currentHash` "") does not count as behind. |
| `installed` | Installed and current. |

- **`Greeter.enabled`** (`x-settings: false`) is set by Install and cleared by Remove. While set, the Layouts page shows its Login screen row.
- **Update notification:** a new `outdated` hash is notified once.
  - The last notified hash is kept in `~/.local/state/axiom/ui/greeterUpdates.json` (`notifiedHash`).
  - The notification's `desktopEntry` is `axiom-greeter-update`; its handler opens Settings → Login screen.
- **IPC** `greeter`: `open`, `preview`.

### Testing
- Every path is under `$AXIOM_GREETER_ROOT` for tests (`greeterinstall.Options.Root`; `go test ./internal/greeterinstall`, the shim's own case in `tests/scripts/test_scripts.py` `GreeterShim`). Never run it against the real `/`.

### Changes from the script
The bash installer (`greeter_install.sh` with awk and jq, run as root) became `axiom greeter-install`; its `check` and `hash` became `greeter.status`. Intended differences:
- The status runs in the daemon, not as `bash … check` from QML, and fails as an RPC error rather than an `error` key.
- A tree with no `.git` runs no git for the status and reports `clone: false` (`noClone`).
- The local archive is unpacked by Go: links and other special files in it are skipped (axiom tracks none), and nothing lands outside the copy.
- The binary is checked for being ELF only: the copy makes it executable anyway.
- The first install runs a binary root owns or one checked against its release, never the clone's script (`pkexec bash`), and `local` takes the binary the user built last (the daemon's running image) rather than the installed one.
- The git source fetches only the official repository, never the clone's remote (the script took the remote, made https), and a git copy's binary is only ever an official release's checked one: the build from the mirror with `go` (for `main`, or a release without a binary) is gone, and those installs are refused.
- The snapshot reads the bundle with no link followed anywhere on its path (the script only checked the last one).
- Files root writes (the policy, the hash and source lines, greetd's config) go through a temporary file and a rename.
