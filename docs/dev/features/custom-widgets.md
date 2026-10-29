# Custom widgets

> **Files:** `config/CustomWidgetsConfig.qml`, `services/apps/CustomWidgetsManager.qml`, `services/apps/CustomWidgetsEditor.qml`, `components/views/CustomWidgets/`, `components/methods/CustomWidgetData.qml`, `components/content/CustomWidget/CustomWidget.qml`, `components/content/parts/custom/`, `components/bar/widgets/CustomWidget/CustomWidget.qml`, `config/schema/sections/CustomWidgets.yaml`, `config/schema/definitions/custom/`
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

### The module
`components/content/CustomWidget/CustomWidget.qml` is a `Panel`: in a card (`properties.definition`) it fills its slot; as the bar widget's popout (`definitionId` from the anchor's `extraData`) it's the definition's design size at the screen's card size (`OverlayConfig.cardUnitOn`, `GridPlacement.span`), declared up front as `maxImplicitWidth/Height`, since an open popout never resizes. It acquires its definition while shown; actions are off on the lock screen (`host.kind`) and in previews (`host.preview`).

`CustomLayout` (`components/content/parts/custom/`) draws the elements: a Repeater by count over `module.elements` (or `CustomWidgetData.defaultElements` when there are none), each a `CustomElement` (a Loader by kind) at `CustomWidgetData.rect` of its place, a `Widget.px(6)` gap between neighbours. Each kind is a `CustomElementBase` with the element's config, the fields, the history and helpers for its bindings (`value`, `text`, `ratio`, `colorOf`, `act`):
- Text (fitted to its box when plain; rich text at a size from the box), Text block (scrolls; the tooltip by default), Figure (`StatFigure`), Icon (Material name or the format-icons glyph, a `CountBadge`), Ring and Gauge (`PercentageCircle`, `sweep` 360 or 240), Bar (`CustomMeter`: a slider when it has a change command, holding the dragged value until the next sample), Segments, Sparkline (the service's history), List (a ListModel updated in place, a ListView), Image (`ClippingRectangle`), Button, Toggle (holds its new state until the next sample), Status (a `StatusChip` or a dot), Separator.

The module library offers each definition by itself (`OverlayConfig.customModuleTypes`, group Custom, A–Z by name), keyed `CustomWidget:<id>`; `GridEditor._newModule` turns the key into `{type: "CustomWidget", properties: {definition}}` (`CustomWidgetsConfig.splitKey`), and the definition's design size is where it starts. The lock screen's library lists only definitions with `module.lockscreen`.

### The bar widget
`components/bar/widgets/CustomWidget/CustomWidget.qml` is a `BarIconWidget` drawing the definition's `bar.style`: `label` (icon and the format filled, as plain text: Waybar's look), `icon` (the icon alone), `ring`, `fill`, `segments`, `sparkline` (a graphic in `IconTextWidget`'s `lead` slot, `leadLength` long, before the icon), `pill` (the widget's box filled to the value), `ticker` (long text scrolls in `bar.width`) and `stacked` (the text over the subtext); a vertical bar draws ticker and stacked as labels. The state colour is its `accentColor` (and its text's, with `bar.colorText`); `urgent` pulses it; `hidden` hides it. Clicks and scrolls run the definition's actions; hovering opens the CustomWidget popout (`extraData: {definitionId}`) while `bar.popout` and the widget's own popout are on.

The bar editor's library is `BarsConfig.libraryWidgetTypes`: the types without CustomWidget, then one entry per definition (`CustomWidgetsConfig.libraryEntries`, keyed `CustomWidget:<id>`), which `BarManager.addWidget` splits back into the type and its definition; a placed one's chip goes by the same key, so it's named after its definition.

### The page
The Custom widgets tool page (`components/views/CustomWidgets/`, `/widgets` in the launcher) edits `CustomWidgets` through `CustomWidgetsManager.editor` (`CustomWidgetsEditor`: a `ConfigDraft`, `selectedIndex` / `selectDefinition`, `elements` (a `GridEditor` over the selected module's elements), `tab`; registered in `EditsManager`). Edits show live on the bars and pages through `ConfigManager.setPreview("CustomWidgets", …)`, and the selected definition stays acquired while the page is shown (`pageShown`), so its sample is there to bind from.
- **Left** (`DefinitionsPanel`): the definitions (add, duplicate, remove), the selected one's script fields (`SchemaPropertiesForm` over the definition's schema, limited with `Utils.pick`), Pick a script (`FilePickerManager`), the refresh command, and the script's first lines when the command starts with a path.
- **Data** (`DataTab`): the run state and Run now, the raw output, every path in the sample (`CustomWidgetData.flatten`, by count) with "Show as…" to bind it to a field, and each field's binding (a path picked or typed, or a format) with what it reads now.
- **Bar** (`BarTab`): the real bar widget on the first bar's look, across and down a side, then the bar style, the text (format, longest text, escape, hide when empty, tooltip; the format icons and state colours typed as JSON) and the actions.
- **Module** (`ModuleTab`): the design size (`setDesignSize`, 1–8 grid units each way, scaling the elements with `CustomWidgetData.scaleElements`), whether the lock screen offers it, undo and redo; `ElementCanvas`, the module at its design size scaled to fit, its elements drawn live over the lattice (a Canvas), each framed to select, drag (`planMove`) or resize from its corner (`planResize`), the plan shown while dragging and made on release; `ElementInspector`, the element library (`CustomWidgetData.elementKinds`; a click adds one where there's room) or the selected element's bindings per slot, its look (its kind's options as a schema form) and its commands; and the module at other sizes (the popout, square, wide, large, strip).

`editor.elements` is a `GridEditor` bounded to the lattice (`area`), with a `factory` that makes elements instead of overlay modules (`GridEditor.factory`: `make(type, place)`, `size(type)`). A definition with no elements draws `CustomWidgetData.defaultElements`; Start from the default layout copies those into it.

### Import and presets
- **Import from Waybar…** (the list's panel) takes a pasted `"custom/…": { … }` block, a bare `{ "exec": … }` or a whole Waybar config (`CustomWidgetData.fromWaybar`, after `stripJsonc` drops comments and trailing commas): `exec` → `command`; `interval` in seconds → poll, `"once"` → once, none → stream (Waybar reads such a script line by line); `exec-if`, `format`, `format-icons`, `max-length`, `escape`, `tooltip`, the click and scroll actions; `signal` → a `refreshName`. Each custom module becomes a definition.
- **From a preset…**: `CustomWidgetData.presets`, well-known scripts and commands (SwayNC, dunst, Waybar's mediaplayer.py, updates, wttr.in, failed services, WireGuard, NVIDIA load). Their icon maps hold Material Symbols names, drawn as icons through the `icon` field bound to `{icon}` (the format-icons pick). Waybar's own icons are usually Nerd Font glyphs, drawn in the text font: they need a Nerd Font installed (fontconfig falls back to one), which axiom doesn't install.
- A script that refreshes Waybar by signal (`pkill -RTMIN+N waybar`) gets a note on the page naming the `axiom ipc customWidgets refresh` call to use instead.
