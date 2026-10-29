# Custom JSON widgets

> **Issue:** [Phase 10: custom JSON widgets](../roadmap.md#phase-10-custom-json-widgets)
> **Status:** decided: B, a fine grid of elements (2026-10-29)

### Problem
Most sway and niri users come from Waybar, and a Waybar setup lives in its `custom/*` modules: scripts printing `{"text", "alt", "tooltip", "class", "percentage"}` once per run or one line per sample. axiom draws none of them today. `CommandOutput` (a module) and Button's `labelCommand` show a command's text, nothing more. One definition should draw a script as a bar widget, that widget's popout, and an overlay, desktop, edge-menu or lockscreen module, with the script run once for all of them (`CommandManager` already merges consumers by command string; stage 3b streams and parses JSON in Go). Test scripts: `~/waybar-test-scripts` on the maintainer's machine (mediaplayer.py, wttr, waybar-updates, pomodoro, wireguard, cava, swaync, dunst, failed units, plus `percentage.sh` and `extended.sh` for the fields Waybar doesn't have).

### Options
#### A. One style per definition (the roadmap's first outline)
A definition picks one style from a fixed set (Label, Figure, Ring, Bar, Graph, List, Text block) and binds its slots. Small, every style draws at any size; but a module is a single figure, so a media player (art, title, buttons) or a status card (ring beside two lines) can't be built.

#### B. A fine grid of elements
The bar widget picks one style (no layout); the module is a fixed set of elements placed on a bounded lattice of 16 sub-cells per card (4 per overlay unit), edited like an overlay page. Places are fractions of the module, so it scales with whatever size a page gives it, and a module dropped on a page starts at its design size. Still not a layout language: no nesting, no expressions, only the element kinds below. Costs an editor canvas, which reuses `GridEditor` (bounded area, plans, undo) and the Layouts canvas pieces.

#### C. Free layout (anchors, nesting)
Most expressive; a layout language to document, migrate and keep drawable at every size. Out of scope.

### Recommendation
B (maintainer's choice). Decided with it:
- **Proportional layout**: an element's rect is its place over the lattice times the module's inner size. Several layouts per definition by size is a later stretch.
- **Interaction**: a Bar with a change command is a slider, a Toggle runs on/off commands, a Button runs one; each fills `{value}`, holds the new value until the next sample and refreshes the script. On the lockscreen every action is off.
- **CommandOutput folds in** through a migration (each card becomes a definition with a Text element); Button keeps `labelCommand`.

**The definition** (`CustomWidgets.items[]`, stable ids): `name`, `icon`; `source` (`command`, a script path or command line, `x-scope: commands`; `mode` poll / stream / once; `interval`; `format` waybar / json / text; `execIf`; `refreshName`); `actions` (Waybar's `on-click`, `-right`, `-middle`, `on-scroll-up` / `-down`); the fields (each the output's key of the same name, decided 2026-10-29: no per-field mapping): Waybar's five plus `icon`, `value` / `min` / `max` / `unit`, `subtext`, `state`, `badge`, `urgent`, `image`, `items`, `hidden`; the text `format` (`{}`, `{text}`, `{icon}`, `{percentage}`, `{alt}`, any `{path}`), `formatIcons` (an array by percentage, an object by `alt` with `default`), `states` (class → theme colour), `maxLength`, `escape`, `hideEmpty`; `bar` (style and its options); `module` (`size` in overlay units, `elements[]` of `{id, kind, place, bind, options}`, `lockscreen`).

**Bar styles:** Label (icon and text, Waybar's look and the default), Icon (state colour, badge), Ring, Fill bar, Pill fill (the widget's background fills to the value), Segments, Sparkline, Ticker (long text scrolls), Stacked (value over caption). All draw on a vertical bar, show `tooltip`, colour by state, pulse when urgent, hide when empty, and open the module as their popout.

**Module elements:** Text, Icon (with badge), Ring, Gauge, Bar (slider when interactive), Segments, Sparkline, List (a ListView over the service's model), Image, Button, Toggle, Status chip, Separator, Text block.

**Concerns:** Pango markup in text and tooltips needs converting to Qt's rich text (and `escape` honoured); Waybar icons are mostly Nerd Font glyphs, drawn with the text font, so a glyph needs a font that has it; `pkill -RTMIN+N waybar` does nothing here, so the editor shows `axiom ipc customWidgets refresh <name>` instead; stream.go coalesces to 4 pushes a second, so cava looks choppy (documented, not fixed); commands are `x-scope: commands`, so a shared definition arrives without its command and says so.

### Items
1. **Data:** `CommandManager` keeps `exitCode` / `error` / `at`; the pure helper `CustomWidgetData` with its test: parse (waybar json and three-line text, `class` as string or array), flatten a sample to its paths, resolve bindings, fill templates, pick icons, map states, convert Pango, `maxLength`, `hidden`, scale element places.
2. **Definitions:** the `CustomWidgets` section (schema, reader, migration step), the `customWidgets` `x-options` source, and `CustomWidgetsManager` (acquire per id, resolved fields, numeric history, actions, `execIf`, the `customWidgets` IPC target).
3. **The module:** the element pieces (a `custom` folder under the content parts), the proportional renderer, the `CustomWidget` module type (also the popout; `hosts: [lockscreen]`, offered there only when the definition allows it), one module library entry per definition (A–Z by name, a Custom group).
4. **The bar widget:** the `Custom` widget type and its styles, one bar library entry per definition, `BarManager.addWidget` taking properties.
5. **Editor, part 1:** the `CustomWidgets` tool page (default page, migration step, launcher command, docs), its editor manager, the definitions list, the Source card (file picker, script preview, Run, raw output, the sample's JSON tree, field bindings) and the Bar tab (previews on a horizontal and a vertical bar, style and options, icon map, states, actions).
6. **Editor, part 2:** the Module tab: the fine-grid canvas on `GridEditor`, the element library and inspector, previews at the design size, square, wide, large and as the popout.
7. **Waybar import and presets:** paste a `custom/*` block (JSONC, parsed in Go) to get a definition; presets for well-known scripts; every test script set up from the page alone.
8. **Fold CommandOutput** (migration), the feature doc (custom-widgets.md under features), and the feature's system in `.claude/skills/review-system/systems.md`.
