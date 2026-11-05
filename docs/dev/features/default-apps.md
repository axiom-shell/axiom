# Default apps

> **Files:** `backend/internal/mimeapps/`, `backend/internal/daemon/machine.go`, `backend/internal/cli/open.go`, `qml/services/system/DefaultAppsManager.qml`, `qml/components/views/Settings/DefaultAppsCard.qml`, `qml/components/content/parts/DefaultAppPickers.qml`, `qml/config/Apps.qml`, `qml/components/surfaces/onboarding/pages/AppsPage.qml`
> **Config:** `Apps.terminal`, `Apps.fileManager`, `Apps.browser` (commands in place of the defaults, empty by default); the defaults themselves are the user's mimeapps.list and xdg-terminals.list
> **Related:** [Launcher](launcher.md), [Onboarding](onboarding.md), [Testing](../testing.md) › Machine settings

Which app opens each kind of link and file, and which terminal starts, kept the freedesktop way so every app agrees with axiom. Tests: `backend/internal/mimeapps`'s Go tests (scratch XDG folders).

### Reading them (`mimeapps.Load`)
- Desktop entries from the data home's and data dirs' `applications/` (the first holding an id wins; `kde4/foo.desktop` is `kde4-foo.desktop`), skipping `Hidden`, non-Application types and a missing `TryExec`.
- The mimeapps.list files in the spec's order: config home, config dirs, then the data folders' `applications/`, each `<desktop>-mimeapps.list` (from `$XDG_CURRENT_DESKTOP`, lowercased) before the plain one; then `defaults.list`.
- A type's default (`Default`): the first installed entry a Default Applications line lists, unless a more important list's Removed Associations dropped it; else defaults.list's; else the first handler. Its handlers (`Handlers`): Added Associations in list order, then the entries declaring the type, by name.
- The terminal (`Terminal`): xdg-terminal-exec's `xdg-terminals.list` (config home, config dirs, the data folders' `xdg-terminal-exec/`, each desktop's own first), its first installed TerminalEmulator, else the first by name.

### Roles
- `mimeapps.Roles` holds each role's MIME types, the first the one whose default it shows (browser: `x-scheme-handler/http`, https, html; files: `inode/directory`; images, video, music, archives: their common types; the terminal has none). `DefaultAppsManager.roleList` names and orders them for the shell (labels translated there).
- A role's state (`apps.roles`): its default, `mixed` when another of its types opens elsewhere, and the apps handling any of its types, those handling the most first.
- Setting one (`apps.setDefault`, the shell's only): every type of the role the app handles (the first always) goes to `[Default Applications]`, the app put first in a line that's there and the line's other apps kept after it; the rest of the file (other groups, comments, order) stays. The terminal goes first in xdg-terminals.list. The file written is the user's most important one that exists (their `<desktop>-mimeapps.list` before `mimeapps.list`), so the change isn't shadowed. Other file types: any MIME type by name (`apps.handlers`, `apps.setDefault` with `mime`).

### Opening things (`apps.open`, `axiom open`)
- `Apps.Command(target, args, overrides)`: a role id opens its app given `args`; a URL its scheme's app (http and https the browser's, mailto mail's); a path its type's (a folder the file manager's; a file by shared-mime-info's `globs2`, the heaviest then longest pattern); nothing found, `xdg-open`.
- The Apps section's commands (`mimeapps.OverridesFrom`) stand in for the terminal, file manager and browser: their words, then the args (the terminal's command after `-e`).
- An entry's command is its Exec line with the field codes expanded (`%f %u` one, `%F %U` all, `%i`, `%c`, `%k`; the spec's quoting), the target appended when it has no file code; a `Terminal=true` entry runs in the terminal (its `X-TerminalArgExec`, else `-e`), as do flatpak's `@@u … @@` markers pass through to `flatpak run`.
- The daemon starts it as the shell's commands start (`command.Spawn`). `axiom open TARGET [ARG…]` asks the daemon, or works it out itself when none runs; `--print` prints the command and starts nothing. The keybinds run it (`Apps.terminalCommand` is `axiom open terminal`, …), so a new default needs no new compositor config; `Apps.inTerminal` runs a command in `axiom open terminal --`.
- Everything the shell opened with `xdg-open` before goes through `DefaultAppsManager.open`: notification links, screenshots, the wallpaper and compositor config folders, drives.

### The settings
- Settings › General › Default apps (`DefaultAppsCard`): `DefaultAppPickers` (a picker per role, app icons from `AppIconManager`), then Other file types. A pick is saved at once (not a config edit); a role whose Apps command is set says axiom runs that instead. App commands (the Apps section) follows, its three commands empty unless set.
- The onboarder's Apps page shows the browser, files, terminal and mail pickers.
