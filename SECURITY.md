# Security

axiom runs your lock screen, and can run your login screen and your polkit agent too, so a security problem in it can let someone past them. Please report security problems privately. Don't use a public issue.

## Reporting

[Report a vulnerability](https://github.com/axiom-shell/axiom/security/advisories/new) through GitHub's private reporting. Only the maintainers can see it. Include:
- what an attacker can do, and what they need first (at the keyboard of a locked machine, a local user, a crafted file, …)
- the steps to reproduce it
- the output of `axiom bug-info` (see [CONTRIBUTING.md](CONTRIBUTING.md#reporting-and-requesting))

We aim to reply within a week. Once a fix is out we publish an advisory, crediting you unless you'd rather not be named.

## What counts

Anything that gets past or weakens a boundary axiom is responsible for:
- **Lock screen:** unlocking without the password, or seeing or using the session behind it (notifications, the clipboard, windows, IPC that does something while locked).
- **Login screen:** logging in without a password, reaching another user's files, or running something as greetd's user beyond the greeter.
- **Polkit agent:** granting an action that wasn't authenticated, or showing a prompt that misleads about what's being authorized.
- **Secrets:** chat API keys or calendar passwords ending up anywhere other than the keyring (config.json, logs, a process's arguments), or pinned clips written somewhere they shouldn't be.
- **Running commands:** a theme, config, imported setup, wallpaper or file name that gets a command run, or a file written outside axiom's own folders.
- **The `axiom` binary and its socket:** another user (or a program that isn't the shell axiom runs) changing the config, reaching the shell's IPC, or reporting the lock through it; a file axiom writes (the config, the compositor's config, the runtime files) ending up somewhere else or readable by others.
- **Self-update, the installer and releases:** anything that installs code other than the release it says it does, including a release binary that doesn't match its `SHA256SUMS`.

Report problems in Quickshell, Qt, PAM, greetd or the compositor to those projects. If axiom uses one of them in a way that makes the problem worse, report that here too.

## Supported versions

Fixes go into the latest release. Self-update (**Settings → Maintenance → axiom updates**) brings a clone up to date, the `axiom` binary included. A distribution package gets the fix once its packager updates it.
