# Footprint ledger

> **Files:** `backend/internal/footprint/`, `backend/internal/hookup/hookup.go`, `backend/internal/compositor/edit/hookup.go`, `backend/internal/compositor/edit/hookup_undo.go`, `backend/internal/compositor/edit/hookup_backfill.go`, `backend/internal/theme/integrate.go`, `backend/internal/theme/effects.go`, `backend/internal/theme/undo.go`, `backend/internal/theme/backfill.go`, `backend/internal/theme/integrations/ini.go`, `backend/internal/cursortheme/cursortheme.go`, `backend/internal/inputmethod/undo.go`, `backend/internal/mimeapps/undo.go`, `backend/internal/daemon/footprint.go`, `backend/internal/cli/footprint.go`, `qml/services/system/FootprintManager.qml`, `qml/components/methods/Footprint.qml`, `qml/components/views/Settings/OutsideChangesCard.qml`
> **Related:** [Session teardown](session-teardown.md), [Theme integrations](../theming/theme-integrations.md), [Input method](inputmethod.md), [Default apps](../features/default-apps.md), [Settings page](../core/settings-page.md), [Schema annotations](../core/schema-annotations.md) (`x-footprint`), [Testing](../testing.md)

Every persistent change axiom makes outside its own folders is recorded before it happens, can be listed, and can be undone exactly. An undo takes out only axiom's own change: it never puts back a whole-file backup, and a value that changed since axiom wrote it is left (`changed`).

### The ledger
- `$XDG_STATE_HOME/axiom/footprint.json`: `{version, backfilled, rows}`; every read-modify-write holds a flock on `footprint.lock` beside it, so the daemon and `axiom footprint` agree. A ledger of another version is read-only: listing works, writing and undoing are `refused`. A file that isn't JSON is moved aside as `footprint.json.bad-<stamp>` (logged) and the ledger starts fresh; any other read error fails the write (`Begin` errors, the change is skipped with a warning).
- A **Row** (`footprint.Row`) has an `id` (`kind:target[:key]`, so a repeated write updates one row), a `kind`, an `owner` (the setting path that caused it, `""` for the compositor's include and autostart lines), a `target`, a `state`, `prior` (what was there, set on the first Begin only; `{"absent":true}` for nothing), `wrote` (the last value axiom wrote), and the flags `inferred` (the backfill found it) and `system` (the system's own choice: default apps, input method groups and ibus's engines; left by Undo all and the uninstall unless picked).
- **Write-ahead.** `Begin` (state `pending`, prior read) goes before the change, `Done` (state `applied`, wrote) after it. A row already applied costs no write. A ledger that can't be written is an error and the change isn't made. A pending row survives a crash; its undo checks what is really there.
- **Never recorded:** a path under axiom's own folders (config, state, data, cache with `axiom/`, the dev config too).

### Kinds
| Kind | Recorded by | Prior / wrote | Undo |
|---|---|---|---|
| `file` | theme integrations' files (`integrate.go`) | prior absent, or the old bytes kept once under `footprint/prior/<sha>`; wrote the sha256 for a file that is the user's once written (`IfMissing`) | delete, or write the old bytes back, whatever it holds now (axiom's own file) |
| `dir` | every folder an integration, hookup or the cursor companion makes (one row per level) | absent | removed when empty, deepest first; the cursor companion (marked `X-Axiom-Generated=true`) with what it holds |
| `hookup` | `edit.Hookups.Apply` | `hookup.EditRecord` (inserted lines with their index, commented lines, created section, wrap), created file, link target, copy sha256, the `.axiom-bak` path | `hookup.Undo`: only the inserted lines (the nearest to their index; one gone is fine), commented lines uncommented, an emptied created section and a created empty file removed, a wrapped link made a link again only when nothing else is in the file, a copy deleted only if it still has its sha. The backup stays and is listed |
| `gsetting` | GTK color-scheme and theme, cursor theme and size, ibus's keys | `gsettings get` output, or absent when the key has no value of the user's own (the keyfile backend's file, `dconf read`; else the value) | `set` back, or `reset` when absent; only while the value is what axiom wrote |
| `ini-groups` | kdeglobals' color groups (`MergeKDE`) | per key: `{group: {key: value|null}}` and the groups created | each key whose value is still as written goes back (a created key is removed, a created group once empty); another key of the same group never blocks it |
| `marked-block` | ncspot's colors between its markers | the markers | the lines from begin marker to end marker |
| `rebuild` | `bat cache --build` | the argv | runs once, after the files are out |
| `fcitx-config` | `SetConfig` of fcitx5's global and classicui configs | the options it changes, read with `GetConfig` | over D-Bus, per row; with no fcitx5 running: `needsRunning`, the row stays |
| `fcitx-group` | `SetInputMethodGroupInfo` (system) | the group's layout and items | as above |
| `mimeapps` | one row per `(path, group, mime)` of the user's `mimeapps.list` and the terminal list (system) | the line's value, or absent (with the group and file made) | the line back, only while it is what axiom wrote |

Undo order: `gsetting`, `fcitx-*`, `mimeapps`, `ini-groups`, `marked-block`, `hookup`, `file`, `dir`, `rebuild` (settings first: a cursor theme is restored before its companion folder is deleted). A row is removed on `done` or `gone`; an undoer that put back part of a row (kdeglobals) shrinks it to the rest. `rebuild` rows run after the ledger's lock is released. A row with nothing written yet (`Wrote` nil: the change may never have happened) is compared with its prior: equal is `gone`, anything else `changed` and left.

`Ledger.Peek` reads without the lock file and without moving a bad file aside (a missing file is an empty ledger, one that isn't JSON an error): for the commands that only look (the uninstall's plan). `RowsErr` is `Rows` with the reason when they are unknown.

### Backfill
Two halves, each once per ledger, each adding rows (all `inferred`) only where there is evidence and no row. The files and the cursor (`backfilledFiles`) are found by the daemon when it starts, before anything is served, so no write can take an old file for one that wasn't there; the hookups (`backfilled`) by `footprint.backfill`, called by `FootprintManager` (a service built at shell start) once the compositor's and the screen-sharing targets are known.
- **Hookups:** targets on one file are one row (their lines together). A target that is done, whose file has a `<comment> axiom: ` line commenting out what the target's text sets, a sibling `<file>.axiom-bak-*`, or a line equal to the target text. The inserted lines are the target's lines present now (and absent from the newest backup, with the blank line and new section header an edit adds); a backup that is a link marks a wrapped file.
- **Integration files:** each existing file of the integrations table (not the `IfMissing` main configs).
- **Cursor:** `axiom-cursor-*` folders, and a `cursor-theme` gsetting naming one (prior absent).
- **Not backfilled** (nothing tells them from the user's own): kdeglobals, fcitx5, ibus, default apps, `color-scheme`.

The uninstall runs the same backfill offline (`daemon.OfflineInferred`: the hookups of the built schema's `x-hookup`, each compositor writer's include and autostart lines (`manager.Offline`) and the screen-share picker's shapes, and the files and cursor folders, each set through `Ledger.Backfill` and `BackfillFiles` once) before it undoes everything ([Uninstall](uninstall.md)).

### RPCs, push and CLI
- `footprint.list {}` → `{rows: [row + status]}` (`present`, `changed`, `gone`); `footprint.undo {ids, force, includeSystem, dryRun}` (shell only) → `{results: [{id, outcome, detail}]}` with outcomes `done`, `gone`, `changed`, `needsRunning`, `refused`, `failed`; `footprint.backfill {targets: {key: {owner, targets, profiles}}}` (shell only); `footprint.notify {}` (a client that changed the ledger by itself); the push `footprint.changed` (topic `footprint`).
- `axiom footprint list [--json]` and `axiom footprint undo (<id>...|--owner <path>|--all) [--force] [--include-system] [--dry-run] [--json]` work on the file directly (no daemon needed; the uninstall reuses them) and tell a daemon that answers. `--all` skips system rows (unless `--include-system`) and inferred rows (unless `--force`).
- Owners: `ThemeIntegrations.<key>`, `ScreenSharing.enabled`, `Input.cursor.enabled`, `Input.keyboard.method.enabled` (the input method rows), `DefaultApps` (the card names it Default apps; no setting asks for them), `""` for the compositor's lines.

### Settings
Fields with `x-footprint` (and `x-hookup`) show "Stays after axiom stops" while the compositor mode is detached, and "Remove its changes" once off with rows it would undo left (`FootprintManager.undoOwner`: the setting's off value is saved, then its rows are undone, but the system's own choices and inferred rows); when system rows of the owner remain, the field asks "Also put back the system defaults axiom changed here?" (Keep is the default). Settings › General › "Changes outside axiom" lists every row by owner with Undo, Undo all, and chips for Inferred, Changed since, Gone and System ([Settings page](../core/settings-page.md)).

### Testing
Go tests per package use fake gsettings and a `dbustest` fcitx5 (nothing reaches the host). The real round trip runs only in `scripts/dev/container-test.sh` (`TestContainerFootprint*`): a seeded home, every integration and hookup applied, then `axiom footprint undo --all --include-system` leaves the home as it was but for the `.axiom-bak-*` files ([Testing](../testing.md) › Container tests).
