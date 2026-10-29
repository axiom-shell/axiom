# Custom widgets

> **Files:** `config/CustomWidgetsConfig.qml`, `services/apps/CustomWidgetsManager.qml`, `components/methods/CustomWidgetData.qml`, `config/schema/sections/CustomWidgets.yaml`, `config/schema/definitions/custom/`
> **Config:** `CustomWidgets.items` (reader `CustomWidgetsConfig`)
> **Related:** [Services pattern](../core/services-pattern.md), [Protocol](../backend/protocol.md) (`exec.watch`), [the plan](../plans/custom-json-widgets.md)

A custom widget is a script drawn as a bar widget, that widget's popout and a module (overlay, desktop, edge menu and, when allowed, the lock screen), all from one definition in `CustomWidgets.items`, so the script runs once for all of them. Its output is read as Waybar reads a `custom/*` module's, so Waybar scripts run unchanged.

### Definitions
Each item (`definitions/custom/CustomWidget.yaml`) holds:
- the script: `command` (run by `sh -c`), `mode` (`poll` every `interval`, `stream` one sample a line, `once`), `output` (`waybar`, `json`, `text`), `execIf` (Waybar's exec-if) and `refreshName`;
- `actions`: Waybar's on-click, right and middle click, scroll up and down;
- `fields`: where each field comes from. Empty reads the key of the same name, so a script printing Waybar's keys (or axiom's extra ones) needs none; a path (`data.temp`) or a format (`{data.temp}°`) reads anything else;
- Waybar's `format`, `formatIcons`, `maxLength`, `escape`, plus `states` (class → theme colour), `hideEmpty`, `tooltip`;
- `bar` (the bar widget's style) and `module` (its design size, its elements, whether the lock screen offers it).

The fields: Waybar's `text`, `alt`, `tooltip`, `class`, `percentage`, and axiom's `icon` (Material Symbols), `value` / `min` / `max` / `unit`, `subtext`, `state`, `badge`, `urgent`, `image`, `items` (rows of `{text, icon, value, subtext}`) and `hidden`.

### Reading an output
`CustomWidgetData` is the pure half:
- `parse`: a JSON object as is; Waybar's text output as lines text, tooltip, class (a streamed line is only text).
- `resolve`: the bound fields, the format filled (`{}` / `{0}` the text, `{icon}` the format-icons pick, any field or path), `escape` before filling, Pango markup turned into Qt rich text (`pango`), the state colour (`stateColor`: the `state` field, else the first class `states` or the defaults map), `ratio` (the value between min and max; `percentage` alone is a value on 0–100), `hidden` (empty text, as Waybar).
- `flatten` lists a sample's paths for the editor's dropdowns.
- `lattice`, `rect`, `scaleElements`: the module's lattice, 4 sub-cells a grid unit (16 a card), laid out proportionally over whatever size the module gets.

### Running
`CustomWidgetsManager.acquire(owner, id)` watches the definition's command through `CommandManager` (format `json` unless the output is plain text) under its own owner per id; the merge by command string means a widget on two bars and a module still runs one script. Each push whose `CommandManager.runs[command].at` changed is resolved into `fields[id]`; `outputs[id]` keeps the raw text, value, exit code and error for the editor, and `history[id]` the last 60 values of the widget's value and of each Sparkline element's binding. With an `execIf`, the script is watched only once that command succeeds (checked when first shown and on refresh).

`act(id, action)` and `runCommand(id, command, value)` run actions detached (`{value}` filled in, shell-quoted unless a number), then refresh the script 300 ms later. Nothing runs in the greeter or while the built-in lock screen is up. `axiom ipc customWidgets refresh <name>` (refresh name, id or name) stands in for Waybar's `signal`: a script calling `pkill -RTMIN+N waybar` should call that instead.

A stream is coalesced to 4 pushes a second by axiom (`backend/internal/command/stream.go`), so frame-rate scripts (cava) look choppy.
