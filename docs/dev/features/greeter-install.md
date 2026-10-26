# Greeter: install, update, status

> **Files:** `services/session/GreeterManager.qml`, `config/GreeterConfig.qml`, `scripts/greeter/greeter_install.sh`, `scripts/greeter/org.axiom.greeter.policy`, `components/views/Settings/GreeterStatusCard.qml`, `components/forms/GreeterSetup.qml`
> **Config:** `Greeter.enabled`, `Greeter.source`, `SelfUpdate.channel` (reader `GreeterConfig`)
> **Related:** [Greeter runtime](greeter-runtime.md), [Lockscreen](lockscreen.md), [Self-update](self-update.md), [Polkit](polkit.md), [Shell targeting](../core/shell-manager-targeting.md)

Axiom as greetd's login screen, laid out like the lock screen. This doc covers the user-side half: installing, updating and removing the root-owned copy, and the status the card shows. For what runs at the login screen (the bundle, the session script, greeter mode, GreetdManager, modules), see [greeter-runtime.md](greeter-runtime.md). (Rule: AGENTS.md › UI conventions › Greeter; never install or update the greeter for real, or restart greetd.)

### Overview
- Off by default.
- Set up from Settings → Screen & Power → Login screen (`views/Settings/GreeterStatusCard`) or from the onboarder's Integrations page. Both go through `forms/GreeterSetup`.
- The greeter runs as greetd's user, who can't read the user's home, so it runs from a copy and reads an export (the [bundle](greeter-runtime.md#the-bundle)).
- `GreeterManager` is created from `shell.qml`'s `_services`.

### Install / update / uninstall
- **Calls:** `GreeterManager.install` / `update` / `uninstall`. Each needs one polkit prompt.
- **How the script is run:**
  - Until the greeter is installed: `pkexec /usr/bin/bash scripts/greeter/greeter_install.sh <action> <repo> <user> [<staged bundle>]`.
  - Once installed: `pkexec /usr/share/axiom-greeter/scripts/greeter/greeter_install.sh …`, root's copy.
- **Root's copy afterwards:** the installed polkit action `org.axiom.greeter.manage` (`scripts/greeter/org.axiom.greeter.policy`) names that copy by `exec.path`.
  - Its prompt says what it's for.
  - The user's own file never runs as root again; `check` reports `helper`.
- **Script compatibility:** an update is run by the copy it replaces, so the script's arguments must stay compatible (a new one goes last). The check's `binaries` says whether the installed helper installs the binary too; while it doesn't, `GreeterManager` runs the clone's script instead (through `pkexec bash`), so a copy is never left without its binary.
- **Root-free actions:** `check` and `hash` run without root.
- **The user argument:** under pkexec, `<user>` must be `$PKEXEC_UID`'s.

#### What gets copied
- The code, minus tests, docs and `*.md`.
- **From:** `Greeter.source` (`GreeterConfig.source`), passed as the script's `<source> <channel> <binary>` arguments. The channel is `SelfUpdate.channel`; `<binary>` is the axiom binary the shell runs (`$AXIOM_BIN`).
- **The binary** the greeter runs (`axiom greeter`, [greeter-runtime.md](greeter-runtime.md)) goes in the copy's `bin/axiom`, by source (below); a package's is its own, on `PATH`.
- **To:** `/usr/share/axiom-greeter`, owned by root.
  - `.greeter-source` says where the copy came from: `"git <channel> <url>"`, `"local"` or `"package <dir>"`.
  - `.greeter-hash` names the version.
- **Source `git`** (default):
  - It fetches as root into its own bare mirror, `/var/lib/axiom-greeter/upstream.git`.
  - It takes the channel's newest `v*` tag (peeled, `sort -V`), or `main`/`master`.
  - It finds them with `git ls-remote` on the url recorded at the first git install. That url is the clone's branch remote, else `origin`, made https so root needs no keys.
  - The clone and its remote can't redirect it later.
  - The hash is the commit.
  - **Its binary:** for a tag, the release's prebuilt `axiom-linux-<amd64|arm64>` (`https://github.com/<owner>/<repo>/releases/download/<tag>/`), checked against that release's `SHA256SUMS`: a mismatch fails the install. Without one (not GitHub, `main`, or a release with no binary: none has one yet), it is built from the mirror's target with `go` (`go generate ./internal/assets`, `go build -trimpath`) as greetd's user, the account that runs it anyway, in a temporary folder of its own (`GOTOOLCHAIN=local`, `CGO_ENABLED=0`; the log in the greeter's `state/binary-build.log`). Neither: the install fails, and the old copy stays.
- **Source `local`:**
  - It archives the clone's tracked files as they are in the working tree: whatever branch, uncommitted changes included.
  - It uses `git ls-files` + `tar`, run as the user through `runuser`, so the clone's config and filters never run as root.
  - The hash is the files' content, the binary's Go source (`backend/`) included, so docs-only edits are not an update. `backend/` is left out of the archive.
  - **Its binary:** `<binary>`, read as the user (root follows none of their links), refused unless it's an executable ELF file. The same trust as copying the working tree.
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
  - It refuses without sway or Hyprland's `start-hyprland` (in `/usr/bin` or `/usr/local/bin`), what `greeter-session.sh` runs the login screen in; `check` reports which as `compositor`. The onboarder's Checks page lists it too (`DependencyManager.tools`' `sway`, with `start-hyprland` as its alternative).

#### Then it sets up
- **`/var/lib/axiom-greeter`:**
  - `config/` is the user's: the bundle.
  - `state/` is greetd's user's: the last user and their sessions (`GreetdManager`'s `greeter` state).
- **Fallback snapshot:** it snapshots the bundle as the copy's `fallback/`.
  - The source is `<staged bundle>`, `$XDG_RUNTIME_DIR/axiom/greeter-bundle`. Axiom writes it just before install and update, since a first install has no bundle yet.
  - It copies with `-P`: the folder is the user's, and root never follows a link there.
- **greetd:** it points greetd's `default_session` `command` at `scripts/greeter/greeter-session.sh`.
  - First it backs up `/etc/greetd/config.toml`: `.axiom-original` once, plus `.axiom-bak-<date>` per change.
  - The edit is line-wise and keeps the config's `user`.
- **Uninstall** puts the original config back and deletes `.axiom-original`, so a later install backs up the config as it is then.

#### Around the prompt
- While pkexec waits, the overlay and the onboarder step aside, unless axiom's own polkit agent is running ([SurfaceManager](../core/shell-manager-targeting.md#stepping-aside)).
- `finishCommands` are what the user runs to make greetd the display manager (`readlink display-manager.service`). The card shows them as `CodeLine`s.

### Status
`check` runs at startup, on the card, and after each action. The states are:

| State | Meaning |
|---|---|
| `checking` | A check is running. |
| `checkFailed` | The first check failed. `lastError` says why; Check again retries. |
| `noGreetd` | greetd or agreety is missing. |
| `noCompositor` | Neither sway nor Hyprland (`start-hyprland`), which the login screen runs in, is installed (the check's `compositor` is `""`). Install refuses then. An installed copy keeps its status (so Remove stays), and `GreeterSetup` warns that it falls back to agreety. |
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
- Every path in the install script is under `$AXIOM_GREETER_ROOT` for tests (`tests/scripts/test_scripts.py` `GreeterInstall`). Never run it against the real `/`.
