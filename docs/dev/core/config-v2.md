# Config v2: the unified shape

> **Files:** `config/schema/`, `backend/internal/schema/yamlsrc/`, `backend/internal/migrate/legacy/`
> **Related:** [Schema and its annotations](schema-annotations.md), [Config manager](config-manager.md), [Saved configs and sharing](saved-configs-sharing.md), [The axiom binary](../backend/README.md)

**Status: accepted; being implemented** (the open questions at the end are settled as recommended). Each change below is one rule applied everywhere it fits. Format 1 is versions 1 to 75; v2 starts at `version: 76` with `format: 2`. The binary converts a format-1 file once: the frozen format-1 chain to v75, then the conversion described here. Old saved configs, exports, examples and community setups keep importing through the same path.

It covers two things: the **shape of config.json** (rules 1 to 10, then [Shared definitions](#shared-definitions) and [Sections](#sections)), and the **schema source** contributors write (rule 11, then [Schema source](#schema-source-what-the-builder-supplies)), where most of today's boilerplate is.

## Rules
1. **One definition per concept.** A concept used in two places is one `definitions/` entry, reused by `$ref` (with sibling overrides where one use differs).
2. **Related keys are an object, not a prefix.** `blurSize`, `blurPasses`, … become `blur: { size, passes, … }`. A family's on/off switch becomes its `enabled`. On bar widgets, `showPopout` + `popoutMenu` become `popout: { enabled, menu }`.
3. **Collections are `<Section>.items`.** Every list of user-made things is `items` in its section, beside that section's settings. Every item has a required, stable `id`, unique in its list, and so does every bar widget and module. Ids are what editors, path ops (`{id}` selectors), previews and import matching use; position never identifies anything.
4. **One way to inherit.** A value an item may take from its section is `null` by default, meaning "inherit". Every key is still filled, and readers resolve inherited values in one place (`item.style.x ?? section.style.x`). This replaces the `override*` booleans with their shadow copies.
5. **One unit per kind.**
   - Every duration is an integer number of **milliseconds**. `x-unit` becomes the unit it is shown and typed in (`s`, `min`, `h`, `d`), and the form and the CLI convert.
   - No key names its unit (`intervalMinutes` becomes `interval`, `durationMs` becomes `duration`).
6. **One case for enum values:** lowerCamel (`top`, `bottom`, `vertical`), not `Top` / `Vertical`.
7. **One screen-targeting shape** (`ScreenTarget`, below) for everything that picks monitors.
8. **No UI or fetched state in config.** What the user didn't choose (a calendar's server name, colour, read-only flag) moves to state files.
9. **Annotations grouped by subject.**
   - The 14 `x-hypr*` / `x-sway*` / `x-niri*` variants become one `x-compositor: { hyprland: {key, value, scale, if, always, skip, configOnly}, sway: {…}, niri: {…} }`.
   - The 5 `x-card*` become `x-card: { file, title, wide, folds, perField }`.
   - `x-showIf`, `x-enabledIf`, `x-enumShowIf` and `x-scopeIf` share one condition grammar, implemented once in Go and once in `SchemaLayout`, with shared fixtures.
   - A condition repeated across definitions is written once: the `$bar.*` show rules on widget colors (today copied into 23 widget files) live in the shared widget color definitions.
10. **The envelope:** `{ "$schema", "format": 2, "version": N, … }`. `version` is the only migration counter and keeps counting from 76; `format` names the file's grammar, so a reader refuses a format it doesn't know outright rather than guessing from a version number. Saved and exported files add `meta: { title, description, source }`, replacing `_example`.
11. **Types live in folders.** A bar widget, overlay module or view type is a folder `<root>/<Type>/` holding `<Type>.qml` (its root object), `schema.yaml` (its definition) and its private parts (sub-components, layouts; later, variant files).
    - Roots: `components/bar/widgets`, `components/content`, `components/views`. A root holds only type folders: shared bases (`BarIconWidget`, `AudioLevelWidget`, `BaseView`) move to a `base/` folder beside it.
    - The folder name is the type const, the one place a type's name is written. Loaders build `<root>/<Type>/<Type>.qml`.
    - Popout-only content (`WeatherForecast`) is a folder in `components/content` without a `schema.yaml`.
    - The private folders folded in: the bar editor's parts are in the BarEditor folder, the workspace strips in the Workspaces folder, the Submenu module's `MenuSubmenu` (loaded as `Submenu/MenuSubmenu`) in the Submenu folder. `Paths.widgetUrl` / `contentUrl` / `viewUrl` build the paths.
    - Done: the files are in their folders; the builder finds each `schema.yaml` through `index.yaml`'s `kinds` (the definition `<Type><suffix>`), and the definitions list is gone.
    - A feature's shared settings (`Weather.location`, used by the widget, the module and the popout) stay a section in `config/schema/sections/`: a type folder never declares a section.

## Shared definitions

| Definition | Shape | Replaces |
|---|---|---|
| `ScreenTarget` | `{ mode: "inherit" \| "primary" \| "focused" \| "all" \| "named", names: [] }`. `names` is `machine` scope (with `x-monitorRef`); `mode` is look. A use narrows `mode`'s enum with a sibling override. | General's `monitors` + `primaryMonitor` (kept as `General.primaryMonitor`); `Launcher/PowerMenu/Notifications/Overlay.monitors`; `Dock/OSD` `monitors` + `monitor`; `Bars[].monitor` and `EdgeMenus[].monitor` (`""` primary, `*` all); `Greeter.monitor`; `Desktop.*.monitor`; `Workspaces.strips[].monitor` |
| `Layout` | `{ grid: { columns, rows, fine }, moduleScale, moduleBorders, modules: [Module] }` | `DesktopLayout`, `ScreenLayout`'s grid half, `EdgeMenu`'s grid keys, the Custom page's modules |
| `ScreenLayout` | `Layout` + `backdrop: { source: "wallpaper" \| "color", blur, color, dim }`, `otherScreens`, `borders: { password, greeting }` | `ScreenLayout` (lock screen, greeter) |
| `Blur` | `{ enabled, size, passes, … }` | `WindowLook.blur*` |
| `Shadow` | `{ enabled, size, color, strength, … }` | `WindowLook.shadow*`, `BarStyle.shadow*`, a bar's `overrideShadow` + `shadow*` |
| `Timing` | `{ openDelay, closeDelay }` (ms) | `Popouts.openDelay/dismissDelay`, Dock / EdgeMenu `openDelay` / `closeDelay` |
| `Trigger` | `{ onHover, size, length }` | EdgeMenu `openOnHover` / `triggerSize` / `triggerLength`, Dock `triggerSize`, `Popouts.edgeTriggerSize` |

## Sections

### Collections
| Today | v2 |
|---|---|
| `Bars: [Bar]` (top level) + `BarStyle` (section) | `Bars: { style: BarStyle, items: [Bar] }`. A bar's `style` is a `BarStyle` whose keys are `null` (inherit) unless set. Gone: `overrideWidgetStyle`, `overrideAccents`, `overrideShadow`, `overrideFontSize`, `overrideRadius`. |
| `Bars[].widgets.{left,leftCenter,center,rightCenter,right}: [Widget]` | the same five lists; each widget gets an `id` |
| `EdgeMenus: [EdgeMenu]` (top level) | `EdgeMenus: { items: [EdgeMenu] }`. An edge menu's grid is a `Layout`; `open: { onHover, delay }`, `close: { onLeave, delay, onOutsideClick }`, `trigger: Trigger` |
| `Dock.docks` | `Dock.items` |
| `OSD.osds` (+ `scrollToChange`, `scrollStep`) | `OSD.items` (the two settings stay) |
| `Overlay.views` | `Overlay.items` (pages; each with an `id`) |
| `Desktop.all` / `primary` / `monitors[]` | `Desktop.items: [Layout + screen: ScreenTarget]`, matched most specific first (named, then primary, then all) |
| `Monitors.profiles`, `Keybinds.presets`, `Chat.providers` / `presets`, `Calendar.accounts`, `ClaudeUsage.accounts`, `Session.env` / `autostart`, Idle's `listeners`, `Hyprland.managed.curves` / `customAnimations` | `items`, or a named list beside the section's other settings when a section holds two (`Chat.providers`, `Chat.presets`). Every entry gets an `id`. |

### Compositor
| Today | v2 |
|---|---|
| `Compositor { mode, requiredSettings }`, `Hyprland.managed.*`, `Sway.*`, `Niri.*` | `Compositor { mode, requiredSettings, hyprland: {…}, sway: {…}, niri: {…} }`: the three backends symmetric, `managed` flattened |
| `WindowLook` (38 flat keys) | `WindowLook { borders: { enabled, activeColor, inactiveColor, size }, shape: { enabled, matchShell, rounding }, gaps: { enabled, inner, outer }, surfaceBlur: { enabled, throughWindows, backdrops, pauseFullscreen }, blur: Blur, shadow: Shadow, dim: { enabled, strength }, opacity: { enabled, active, inactive, fullscreen } }` |
| `Input` (19 flat keys, with `keyboard` / `mouse` / `touchpad` / `cursor` as group switches) | `Input { keyboard: { enabled, layout, variant, options, repeatRate, repeatDelay, numlock }, mouse: { enabled, accel, sensitivity, leftHanded }, touchpad: { enabled, naturalScroll, tapToClick, disableWhileTyping, scrollFactor }, cursor: { enabled, theme, size } }` |

### Look and behaviour
| Today | v2 |
|---|---|
| `Appearance.theme` + `themeSchedule` | `Appearance.theme: { name, schedule: { enabled, lightAt, darkAt } }` |
| `Appearance.wallpaper`, `wallpapers`, `wallpaperBackend`, `wallpaperDaemon`, `wallpaperFolder`, `wallpaperMode`, `wallpaperRotation`, `variantWallpapers` | `Appearance.wallpaper: { mode, file, perScreen: {}, folder, rotation: {…}, variants: { dark, light }, backend, daemon }` |
| Widget's `overrideRadius` + `radius` | `Widget.radius` (`null` inherits `Appearance.shape.radius`) |
| `Notifications.gap`, `gapTop`, …, `evenGaps` | `Notifications.gaps: { even, all, top, bottom, left, right }` |
| `Launcher.windows`, `calculator`, `commands`, `runCommands`, `webSearch`, `chat`, `clipboard`, `emoji` (+ `searchEngine`, `clipboardSource` (gone with cliphist, stage 2), `clipboardMaxEntries`) | `Launcher.providers: { windows, calculator, commands, run, web: { enabled, engine }, chat, clipboard: { enabled, maxEntries }, emoji }` |
| Idle's `dimTimeout`, `dimMode`, `dimLevel`, `dimBy`, `lockTimeout`, `screenOffTimeout`, `suspendTimeout` (s) | `Idle.dim: { timeout, mode, level, by }`, `Idle.lock.timeout`, `Idle.screenOff.timeout`, `Idle.suspend.timeout` (ms) |
| `Dock` magnify / running keys | `magnify: { enabled, size, range }`, `running: { show, scope, indicator }` |
| `Pomodoro.workMinutes`, … | `Pomodoro.work`, `shortBreak`, `longBreak` (ms) |
| `Weather.intervalMinutes`, `ClaudeUsage.intervalMinutes`, `Calendar.syncInterval`, `Appearance.wallpaperRotation.interval` (min), `Notifications.timeout`, `WindowBehaviour.cursorHideTimeout` (s), `Notifications.maxAgeDays` | each one key, in ms |
| `Calendar.accounts[].calendars[]` holding `name`, `serverColor`, `readOnly`, `components` (fetched) | config keeps `{ href, color, enabled }`; the rest goes in the calendar cache state |

### What stays
Sections that are already one concept with plain keys stay as they are, apart from the units, enum case and ids above: `Battery`, `Polkit`, `NightLight`, `Screenshots`, `Apps`, `PowerMenu`, `Todo`, `Stopwatch`, `Workspaces`, `WorkspaceOverlay`, `WindowSwitcher`, `SelfUpdate`, `CommunitySetups`, `ThemeIntegrations`, `Icons`, `Notes`, `Weather` (bar its interval), `Session`.

## Schema source: what the builder supplies
`axiom schema build` finds every `schema.yaml` under the three roots, so `index.yaml` lists no type definitions and `BarWidget`, `OverlayModule` and `OverlayView` have no hand-written `oneOf`. A `schema.yaml` writes only what is particular to its type; the builder adds each kind's common part, which is itself data (a base definition per kind in `config/schema/`, merged in), not Go code:

| Kind | Added by the builder | Written in `schema.yaml` |
|---|---|---|
| every kind | `type: object`, `additionalProperties: false`, `required`, `type: {const: <Type>}` with its label, `id` | `icon`, `group` (the library group), `settings` (flat: the builder nests them as `properties.properties`, so config.json's shape doesn't change) |
| bar widget | `visible`, `layout`, `popout: { enabled, menu }`, the color fields with their `$bar.*` show rules | `popout: own \| menu \| none` (which title and default `popout` gets), `colors: [<autoColor role>, …]` |
| overlay module | `place`, `x-hosts: [overlay, edgeMenu, desktop]` | only the extra hosts (`hosts: [lockscreen, greeter]`), `size` / `minSize` |
| overlay view | the page's common keys (`OverlayView`) | `needs` |

The builder also links a type to the section of the same name when there is one (`x-link: {setting: Weather}` today), unless the type says otherwise.

The Weather widget, today about 55 lines in `components/bar/widgets/Weather/schema.yaml`:
```yaml
# components/bar/widgets/Weather/schema.yaml
icon: partly_cloudy_day
group: Time & weather
popout: own
colors: [accent]
settings:
  showCondition:
    type: boolean
    title: Show condition
    default: false
    description: Show the condition (e.g. Rain) next to the temperature.
```

### Duplicated information removed
- `index.yaml`'s root `description`, a hand-kept copy of `annotations.yaml` that has already drifted from it (see [issues](../issues.md)): generated from `annotations.yaml`, or dropped.
- `index.yaml`'s `definitions` list and the `listedExactly` check that keeps it in step with the files.
- Per type: the header comment repeating the file name, the `description` repeating the type const, `x-hosts` repeating the default (47 of 48 modules list it, and AGENTS.md requires it), `x-link` to the section of the same name.
- In the recipes and skills (`bar-widget`, `overlay-module`, `overlay-view`, `bar-popout`): the copied popout and color blocks and their gotchas, which become the builder's job.

## Left room for (not in v2)
Nothing in v2's shape depends on these; rule 11's folders are where they would go.
- **Variants:** a `schema.yaml` may later list `variants: [{ name, icon, size, settings }]`, library presets of one type ("Weather · Forecast" adds a Weather module with those settings at that size). No new types and no migrations; switching variant is a settings change in the inspector. A variant that draws very differently keeps its QML in the type's folder, chosen by a setting (Clock's `style` is one already).
- **Size classes:** one `SlotContext` decision (e.g. `compact | short | full | wide`) from a pure methods helper with test rows, instead of each module's own breakpoints (AudioMixer's `sliderOnly` / `sideBySide`, similar checks in about 20 modules). `Panel` and `Card` would take one Component per class, generalising `compactContent`; big layouts go in the type's folder. Size stays geometry, never config, and never a separate type per size: a card's size changes live while it's dragged, and the same content is a popout with no grid size.
- **User types:** a folder dropped into `~/.config/axiom/<kind>/<Type>/` could later be merged into the schema by the binary at load.

## What it costs, and where
- **Readers keep their public names** (`Bar.savedBars`, `DockConfig.docks`, `Widget.px`, …). Only reader internals change, so the components above them don't.
- **What changes in QML:**
  - the editors that write shape directly (BarManager, EdgeMenuEditor, OverlayManager, DockManager, ScreenLayoutEditor, MonitorManager, KeybindManager, the settings cards);
  - the compositor config writers (the daemon's `render`, which reads the annotations);
  - the condition evaluator (`SchemaLayout`);
  - the form controls (duration units).
- **Enum case** (rule 6) is the widest change: `edge === "Top"` style comparisons across the bar, popout and edge code. Readers could normalize instead, but that keeps two spellings alive. **Recommended: change them**, file by file with the readers.
- **Type folders** (rule 11): the loaders (`BarContainer`, `OverlaySlot`, `ExpandedModule`, `BarPopouts`, `SubPopout`, `OverlayPages`), the discovery in `backend/internal/schema/yamlsrc/assemble.go`, the `qs.` imports of moved private parts and shared bases, and the scripts that find type files (`check_structure.py`, `gen_docs.py`, `check_docs.py`). Moving the files changes no config, so it can land as its own commit first.
- **Python consumers** of annotations change in the same commit: `check_i18n.py` (or the pre-commit prune drops translations), `check_structure.py`, `gen_docs.py`, `integration_hookup.py`, `guard.py`.

## Open questions
1. **Collection key:** `items` everywhere (`Overlay.items`), or a name per section (`Overlay.pages`, `Dock.docks`)? Recommended: `items`. One generic collection editor and one path rule are worth the less descriptive name.
2. **Durations:** integer ms with a display unit (recommended), or human strings (`"5m"`)? Strings read better in `config.json`, but every reader then needs a parser.
3. **`Widget` section name:** rename to `Interface` (it's the Interface scale, not bar widgets), or keep it to spare `Widget.px` churn? Recommended: rename the section and keep the reader name.
4. **Ids for widgets and modules:** `<type>` plus a counter (`clock`, `clock-2`), or random? Recommended: readable, made by the conversion and by editors.
5. **Each kind's common part:** a base definition per kind in YAML, merged by the builder (recommended: the shared part stays data anyone can read), or rules in Go?
6. **Order:** move the files into type folders as its own commit before the shape changes (recommended: no config change, easy to review), or together with them?
