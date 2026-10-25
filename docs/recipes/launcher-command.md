# Recipe: a new launcher command

> **Use when:** adding a `/command` to the launcher.
> **Copy from:** the `nightlight` entry in `services/ui/LauncherCommands.qml` (on/off with options and status); helpers in the same file: `_page` (open an overlay page), `_session`, `_device`, `_media`, `_prefix`, `_onOffOptions`/`_onOff`.
> **Docs:** [features/launcher](../dev/features/launcher.md); the entry fields are documented in the comment at the top of `services/ui/LauncherCommands.qml`.

## Files to touch
1. `services/ui/LauncherCommands.qml`: an entry in `list`, in its group (`// --- Session ---`, `// --- Surfaces ---`, …).
2. `docs/usage.md`: the launcher command table (its group's row).
3. `config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys, empty, to every language and the template.

## Skeleton
```qml
{
  name: "foo",
  aliases: ["bar"],
  glyph: "bolt",
  usage: "[on | off]",
  description: () => I18n.tr("Toggle foo"),
  available: () => FooManager.available,
  status: () => FooManager.active ? I18n.tr("On") : I18n.tr("Off"),
  options: () => root._onOffOptions(),
  run: (arg, value) => {
    const on = root._onOff(value ?? arg);
    FooManager.setActive(on === null ? !FooManager.active : on);
    return false;
  }
},
```
Opening a page: `root._page("foo", ["aliases"], "<ViewType>", "Open the foo page")`, and add `I18n.tr("Open the foo page")` to the declaration comment inside `_page`.

## Entry fields
- `name`, `aliases`, `glyph` (Material Symbols name), `usage`.
- `needsArg`: Enter without an argument completes `/name ` instead.
- `confirm`: asks for a second Enter (destructive session actions).
- `available()`: whether it's listed; `status()`: state shown on its row.
- `options(arg)`: completion rows `[{ title, subtitle, glyph, image, value, matched }]`.
- `run(arg, value)`: `value` is the picked option's. Return `false` to keep the launcher open (where the change shows), a string to search for instead, or nothing to close.

## Steps
1. Add the entry; the work happens in a service (the command only calls it).
2. `description` is a function (`() => I18n.tr(…)`) so it follows the language. Text built by a helper is declared in a comment as `I18n.tr("…")` so `check_i18n.py` sees it.
3. Add it to the `docs/usage.md` table, then verify.

## Gotchas
- `/config` can never edit `Bars` or `Overlay.items`; don't add commands that bypass that.
- Commands reachable in greeter mode must check `Paths.greeter` in `available` when they'd write or run anything (the `/event` entry checks it).
- Page commands go through `ShellManager.openOverlayPage(type)`, which picks the target screen.
- Every launcher row has the same shape ([features/launcher](../dev/features/launcher.md)); a new *provider* (prefix) is a bigger change than a command.

## Verify
- `scripts/dev/verify.sh`
- To see it: `axiom ipc appLauncher search "/foo"`, take a screenshot (`grim -o <monitor> <file>`), then `axiom ipc appLauncher close`. The launcher steals keyboard focus, so the user's typing leaks in ([features/launcher](../dev/features/launcher.md) › Testing).

## Docs to update
- `docs/usage.md` launcher table; [features/launcher](../dev/features/launcher.md) if it adds a new kind of command.
