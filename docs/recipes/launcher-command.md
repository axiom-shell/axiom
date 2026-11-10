# Adding a launcher command

A launcher command is a `/name` typed into the app launcher: `/wifi on`, `/theme <name>`, `/eject`. Each one is an entry in `qml/services/ui/LauncherCommands.qml`. At the end you have an entry, its row in the usage table, and the work done by a service it calls.

**Copy from:** `root._switch("nightlight", …)` in `qml/services/ui/LauncherCommands.qml` (an action you can switch on or off), `root._action(…)` next to it (a plain action), the `theme` entry (options and a status), the `caffeine` entry (a duration or on/off, with a status), the `eject` entry (an argument, hidden when unavailable). The helpers are defined under "Builders for families of alike commands" in the same file: `_action`, `_switch`, `_page` (open an overlay page), `_device`, `_media`, `_prefix`.
**Background:** [features/launcher](../dev/features/launcher.md); the entry's fields are documented in the comment at the top of `LauncherCommands.qml`.

## Files
1. `qml/services/ui/LauncherCommands.qml`: an entry in `list`, under its group comment (`// --- Session ---`, `// --- Surfaces ---`, …).
2. `docs/usage.md`: the launcher command table, in the group's row.

New translation keys are added by the pre-commit hook.

## Steps
1. If the thing is a one-tap action (a toggle, a session action, a surface), it already is, or should be, a row of the action catalogue ([actions](../dev/core/actions.md)). Then the entry is one line, `root._switch(name, actionId, aliases, "Description")` for `[on | off]`, or `root._action(…)` otherwise, and the helper runs it through `ActionsManager.run`. To open an overlay page use `root._page(name, aliases, "<ViewType>", "Description")`.
2. Anything else is a hand-written entry, an object in `list`. It calls a service function and leaves the work to it. The `caffeine` entry is a good model: it takes a duration or on/off, shows its state in `status`, and falls back to the action for plain on/off. `eject` shows `available`, `options` and an argument.
3. The entry's fields:
   - `name`, `aliases`, `glyph` (a Material Symbols name), `usage`.
   - `needsArg`: Enter without an argument completes `/name ` instead of running it.
   - `confirm`: asks for a second Enter first, for what can't be undone.
   - `available()`: whether it is listed at all. `status()`: the state shown on its row.
   - `options(arg)`: completion rows `{ title, subtitle, glyph, image, value, matched }`.
   - `run(arg, value)`: `value` is the picked option's. Return `false` to keep the launcher open (where the change shows, so several can be tried), a string to search for instead, or nothing to close it.
4. `description` is a function, `() => I18n.tr("…")`, so it follows the language. Text that a helper passes on as a variable is declared in a comment as `I18n.tr("…")` so the translation check sees it (see `_action`).
5. Add the command to the right row of the table in `docs/usage.md`.

## Watch out for
- **`/config` can't edit everything.** It offers only the settings page's fields, minus the prefixes in `SettingsManager._blockedPrefixes` (`Bars.items`, `Overlay.items`, `Menus`), so bars, overlay pages and menus can't be changed through it. Don't add a command that gets around that.
- **The greeter.** The launcher also runs on the greeter, so a command that would write or run anything checks `!Paths.greeter` in `available` (`eject` and `event` do).
- **Pages** open through `ShellManager.openOverlayPage(type)`, which picks the target screen. `_page` does that for you.
- **A new provider** (a prefix such as `:` or `~`) is a bigger change than a command; every launcher row has the same shape ([features/launcher](../dev/features/launcher.md)).

## Check it
- `scripts/dev/verify.sh`
- To see it: `axiom ipc appLauncher search "/foo"`, take a screenshot with `grim -o <monitor> <file>`, then `axiom ipc appLauncher close`. The launcher takes keyboard focus, so anything you type meanwhile lands in it ([features/launcher](../dev/features/launcher.md) › Testing).

## Docs to update
- `docs/usage.md`, and [features/launcher](../dev/features/launcher.md) if it is a new kind of command.
