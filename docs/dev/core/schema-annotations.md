# Schema and its annotations

> **Files:** `config/schema/`, `config/json/config.schema.json`, `components/methods/SchemaLayout.qml`, `components/methods/SchemaValidation.qml`, `components/forms/SchemaField.qml`, `components/methods/HyprLua.qml`
> **Config:** every section
> **Related:** [Settings page](settings-page.md), [Saved configs and sharing](saved-configs-sharing.md), [Config manager](config-manager.md), [Config readers](config-readers.md), [Hyprland config modes](../hyprland/config-modes.md)

The schema is the single source of truth for config: shape, `default`s (there is no separate defaults file) and the generated settings page (`views/Settings/Settings.qml`). This doc is the complete list of `x-*` annotations: `scripts/check_docs.py` fails on one the schema uses that isn't named here, and building the schema (`axiom schema build`) refuses one missing from `config/schema/annotations.yaml`, the registry with a line on each.

The schema is written in YAML (`config/schema/`): `index.yaml` is the root and lists the sections and definitions in order; `sections/<Section>.yaml` and `definitions/{widgets,modules,views,common}/<Name>.yaml` hold one each. The YAML is read strictly (no anchors, aliases, merge keys or tags; quote `on`/`off`/`yes`/`no`, which YAML 1.1 reads as booleans; write `null` out), and every key of a schema node must be a draft-07 keyword the validators read or a registered annotation, so a typo fails the build with its file and line. (Rule: AGENTS.md › Config.)

### Basics
- Adding a setting = a schema entry with a `default` + a reader property.
- Changing the layout of existing config = a format-2 step in the binary (`backend/internal/migrate/`) + a test; the format-1 migrations (`backend/internal/migrate/legacy/legacy.js`) are frozen.
- The live file is `~/.config/axiom/config.json` (`$XDG_CONFIG_HOME`, UI-owned).
- A schema reaches QML as a map, whose keys come out sorted, so order always comes from `x-order`.
- The settings page, forms and editors read the annotations: add an annotation rather than a hand-kept list in QML.
- A `$ref` may carry keys beside it (`default`, `title`, …) that override the definition's (`SchemaValidation._resolve`). `Lockscreen.layout` and `Greeter.layout` share `definitions/ScreenLayout`, each with its own default modules.
- `oneOf`s (bar widgets, overlay views and modules) are discriminated by `type`.
- A `pattern` is RE2 (a subset of JS's syntax), read as JS reads it: the binary widens `\s`/`\S` to JS's Unicode whitespace (`schema.CompilePattern`), and refuses a `\S` inside a character class.
- `x-inherit: "<path>"`: the setting may be `null`, and is by default, meaning the value at that dotted path (`Interface.radius` follows `Appearance.shape.radius`). On a `$ref`, the build makes an inheriting copy of the definition (`<Definition>Inherited`, every leaf `null` and inheriting from `<path>.<key>`): a bar's `style` from `Bars.style`. Validation lets the `null` through; the form shows the inherited value with "Follows … until set" (`SettingsManager.inheritedValue`), and readers resolve it (`BarsConfig.lookOf`).
- Build-time keys, never in the built schema: `x-inline: true` on a definition copies it into each use; `x-properties` beside a `$ref` makes a copy of that definition with its properties adjusted (a schema replaces or adds one, `null` removes one: `ScreenLayout` of `Layout`).

### Placement
- `x-settings: false`: hides a key from the settings page (edited elsewhere, or UI-owned state).
- `x-category` (on a top-level section): names its sidebar category.
- `x-categories` (root, `[{ name, icon, card, cardTitle }]`): orders the categories and gives their icons (`SchemaLayout.categories`). A category left out comes last, with a generic icon.
  - `card` is a hand-built card of the category's own (`views/Settings/<card>Card.qml`), always wide, after its sections' cards; `cardTitle` titles it, on the card and in the sidebar. A category with one can have no sections. Example: Maintenance's `SavedConfigsCard`; see [Saved configs and sharing](saved-configs-sharing.md).
- `x-links` (on a section): pages its category's header links to: a view type (`Themes`, `BarEditor`), `Layouts`, or the layouts editor on a screen (`Layouts:lockscreen`, `Layouts:greeter`, `Layouts:desktop`). Labels, icons, availability and following go through `OverlayManager.pageLinkLabel` / `pageLinkIcon` / `pageLinkAvailable` / `followPageLink`.
- `x-link` (on a field, or a widget/module definition): where something it follows or names is set, drawn as a `SettingsLink` under the field in every form (`FieldLinks`), or in the bar widget / module inspector for a definition. `{ "setting": "<key path>" }` (a field, an object or a section: `SchemaLayout.locate` finds its card) or `{ "page": "<page link>" }` (as `x-links`), or a list of them. A link hides itself when its setting has no card or its page isn't shown. Examples: a bar's `style.shadow` → `Bars.style.shadow`, every `moduleScale` → `Widget.cardSize`, the Battery widget → `Battery`. `tst_SchemaLayout`'s `test_real_schema_links_resolve` checks every target.
- `x-order` (on an object): the keys shown first, in order. This applies to its form, or to its settings cards, whose order is their first field's. The build writes it from the properties' order on every object with more than one; one written in the YAML is kept.
- `x-group`: puts a field on a card of that name. One section or object can make several cards.
  - The bar and edge menu editors group a `Bar`'s / `EdgeMenu`'s own fields the same way (`SchemaLayout.objectGroups`, as `BarsConfig.fieldGroups` / `EdgeMenusConfig.fieldGroups`).
  - A nested object with an `x-group` joins that card (a group heading repeating the card's title is left out); `objectGroups` places a nested object's fields by their own or an ancestor's `x-group`.
- `x-scope` (`look` | `personal` | `commands` | `machine`, inherited, root `machine`): what a snapshot, example, import or export carries. See [Saved configs and sharing](saved-configs-sharing.md).
  - A new setting inside a look section that names a monitor, path or account needs `machine`; one that runs something (a command, a terminal) `commands`; a preference that means something on any PC `personal`.
- `x-scopeIf: { when, scope }` (on an array's item schema): an item that matches `when` (`x-showIf`'s form, over the item's keys) has `scope` as its own: an exec bind is `commands`, an app's OSD bar `personal`.
- `x-monitorRef` (`"off"` | `"drop"`, on a per-monitor part's `monitor`): a shared file names the monitor by its place, and a part for a place the user has no monitor for is turned off or left out (`share.Apply`).
- `x-libraryGroups` (root) lists in order the groups the bar editor's and layouts editor's libraries sort their types into (by category).
  - Each bar widget and overlay module definition joins one with `x-libraryGroup` (`methods/LibraryOrder`, `reusable/TypeLibrary`).
  - `check_structure.py` errors on an unknown group.

### Hand-built parts
- `x-card: { file, title, wide, folds, perField }` (section):
  - `file`: adds `views/Settings/<file>Card.qml` as the section's first card, titled `title` (on the card and in the sidebar; the card's QML sets none).
  - `wide: true`: it spans both columns (the calendar accounts, chat API keys, the Dock and OSD lists).
  - `folds: true`: it folds like the generated cards and joins Fold all, getting its group key `<Section>:<file>` as `foldKey`.
  - `perField: true` (with or without a `file`): each direct field becomes a card of its own, titled and described by the field, sorted by title, a switch's row labelled "Enabled" (`row.label`, `row.description` override the field's in `SchemaField`). The section's description gets a card first. Example: `ThemeIntegrations`, one card per app.
  - `check_structure.py` checks the file exists.
- `x-intro: "<Name>"`: puts `views/Settings/<Name>.qml` at the top of the section's own card, above its fields (NightLight's `NightLightStatus`).

### Behaviour
- `x-showIf`: hides a field unless a condition holds. `SchemaField` evaluates it (`SchemaLayout.showIfHolds`), so it works in every form; on a nested object it hides that object's cards.
  - Form: `{ sibling: value | [values] | { not: value } | { notEmpty: true } }`. Every key must hold.
  - `anyOf: [conditions]` holds when one of them does. Example: the OSD's `alongEdge`, shown only while its bars run along its edge.
  - A key starting with `/` is a dotted path from the config root (e.g. `"/Workspaces.layout"`), read through `SettingsManager.configValueAt`.
  - **Compositor.** Two `/` keys read the running compositor instead: `"/$supports.<capability>": true` (`CompositorManager.supports`) and `"/$compositor": "<kind>"`. See [The compositor](../compositor/README.md) › Hiding what a compositor can't do.
  - **Bar look.** In a bar widget's options, `"$bar.<key>"` (no `/`) reads the look of the bar it sits on: a `BarStyle` key as that bar uses it (`BarsConfig.lookContext`, passed as the form's `context` by the bar editor's inspector). The grouping reads `separate` for styles without boxes. Use it to hide a color the bar's style doesn't draw ([widget style](../bar/widget-style.md#which-color-fields-show)).
  - **Distribution.** `"/$distro": "<family>"` reads `DependencyManager.distro` (`Packages.distroFamily`: `arch`, `fedora`, or `""`), for a setting only one distribution has (the Updates options' AUR).
  - **Package.** `"/$packaged": false` reads `Paths.packaged`, for what a packaged axiom doesn't have (the `SelfUpdate` section, `Greeter.source`; [packaging.md](../packaging.md)).
  - On a whole section, `x-showIf` (with `/` keys only) takes the section out of its settings category when it fails (`SchemaLayout.categories`). The `Hyprland` section needs `configModes`.
- `x-enumShowIf` (`{ optionValue: condition }`): hides enum options whose condition doesn't hold. The current value stays listed.
- `x-enabledIf`: as `x-showIf`, but a field whose condition fails stays shown, greyed out, its value kept and not editable (`SchemaField.allowed`), with why above its description. Use it for what the compositor can't do (`"/$supports.windowBlur": true`), so the setting is still found and says what would: the note is `CompositorManager.unsupportedNote(capability)` (the backend's `unsupportedHint` adds what can, e.g. "SwayFX can."), or "<Compositor> only." for `/$compositor`. Only a row shown on its own says it: a row that a sibling shows (a part's fields, `x-showIf: { part: true }`) is greyed without repeating the note under its switch. `SchemaLayout.compositorAllows` counts it too, so the launcher's `/config` doesn't offer such a setting.
  - `x-disabledNote`: the note instead (English, translated); `false` for none, where the section's `x-intro` says why (the Workspaces section under niri).
- `x-beside: true`: puts a field beside the one before it on its settings card, each half wide (`SettingsGroupCard`'s two-column grid; Workspaces' rows beside columns). Give the pair the same `x-showIf`. A bar widget's options pair the same way in the widget inspector (`SchemaPropertiesForm`'s `pairs`), but only while both are shown.
- `x-wide: true` (field): the settings card the field lands on spans both columns (`SchemaLayout.groups`' `wide`). Put it on the field that needs the room, usually an array of objects (chat providers, Hyprland curves, session environment). See [Settings page](settings-page.md) › Columns.
- `x-applyOnSave`: keeps a setting in the draft until Save instead of applying it live (Hyprland's `mode`, which can take over files).
- `x-snapshot: true`: a machine setting a saved snapshot carries too (the wallpaper setup: wallpapers, folder, mode, rotation, light/dark wallpapers, theme schedule), since a snapshot restores on the PC it was saved on. Exports and examples still leave it out. See [Saved configs and sharing](saved-configs-sharing.md).
- `x-takeover: true`: a setting that takes something over on this PC (Hyprland mode, locker, idle, polkit, greeter). Loading or importing a config, or editing config.json from outside while axiom runs, never changes it; only its own card does. See [Saved configs and sharing](saved-configs-sharing.md).

### Controls
- `x-options`: a dynamic option list.
  - `"colors"`: a picker over `base00`–`base0F`, read with `Theme.resolveColor` (which also takes semantic names and hex).
  - `"screens"`: a monitor. Empty means the primary monitor, resolved by `General.screensNamed` (bars in `BarsConfig.expandBars`, docks, edge menus). Docks and OSDs pick all monitors through `monitors` instead.
  - Others: `"languages"`, `"edgeMenus"`, `"overlayPages"`, `"notes"`, `"timezones"`, `"calendars"`, `"chatProviders"`, `"chatPresets"`, `"cursorThemes"` (`SettingsManager.optionsFor`).
- `x-emptyLabel`: offers or renames the empty value under that label.
  - On a color: automatic (a bar's `widgetTextColor`).
  - A color without it lists its `default` first, labelled as the default, so an override can be undone.
  - On `"screens"`: renames empty where it means something else, as in `General.primaryMonitor` itself.
- `x-allScreens`: adds All monitors (`"*"`) to a `"screens"` picker.
- `x-enumLabels` (`{ value: label }`): labels shown instead of raw enum values in dropdowns.
- `x-suggestions` (e.g. `"audioApps"`): chips under a text field (`SettingsManager.suggestionsFor`).
- `x-multiline: true`: a growing text area.
- `x-control`:
  - `"slider"` | `"stepper"`: overrides the integer control choice (below).
  - `"readonly"`: shows a string with a copy button instead of a field (an edge menu's `id`).
  - `"folder"`: a string with a Browse button opening the desktop's folder picker ([File picker](file-picker.md); the wallpaper, notes, screenshot and recording folders, Claude usage's `configDir`, System stats' `diskPath`). It hands back `~/…`, so whatever reads the setting expands `~` (`Paths.expandHome`).
  - `"search"`: a long option list (e.g. `"timezones"`) is typed into to filter it (`SchemaField`; the Clock module's and World clocks' `timezone`).
- Integers render through `forms/SchemaNumberField`:
  - a slider with a value box for 7–200 steps, else a stepper, with ±10 buttons past 20 steps
  - steppers commit debounced, sliders on release
  - `x-unit` (`px`, `%`, `ms`, …) is shown after the value.
- `x-auto: { value, start }`: a switch in front of an integer whose `value` means automatic. Turning it on stores `start`, then the number shows (an edge menu's `padding`, `triggerLength`).

### Types (bar widgets, overlay modules, views)
- `x-icon`: a Material Symbols name on bar widget, overlay module and view definitions.
- On overlay modules:
  - `x-defaultSize` (`[w, h]` in grid units, four to a card): the size it's added at.
  - `x-minSize`: the least a drop into a gap shrinks it to; half the default when left out (`OverlayConfig.minSize`).
  - `x-hosts`: `overlay`, `edgeMenu`, `lockscreen`, `greeter`, `desktop`. `overlay`, `edgeMenu` and `desktop` when left out, so the lock screen and the greeter only take modules that list them. Every module on overlay pages goes on the desktop too (`check_structure`).
  - `x-keyboard: true`: the module takes typing. The desktop, which otherwise never takes the keyboard, takes it on a click while its layout shows one (`OverlayConfig.moduleInfo(type).keyboard`, `ScreenLayoutView.wantsKeyboard`). Needed for a typing module on the desktop: `check_structure` fails a desktop module with a text field (in its file or its content parts) and no `x-keyboard`. `false` says it stays read-only there on purpose (ClockCalendar).
  - `x-required`: part of every grid on its hosts; never removed, duplicated or in the library (the lock screen's `Password`).
  - `x-canvasDetail`: a module property the layouts editor shows on its tile (a list joined). `x-canvasFill`: a color property the tile is filled with (`OverlayConfig`).
- `x-tool: true` on the hand-built view types: the navigator's tool group.
- `x-needs: "<capability>"` on a view type: the page is left out (and its launcher command unlisted) unless `CompositorManager.supports` has it (Keybinds, Monitors).
- `x-autoColor` (`accent`, `alt`, `warning`, `critical`, `off`, `neutral`): a bar widget color picked by its bar when left empty (`BarsConfig.autoColorFields`, `methods/BarAutoColors`). See [Bar widget style](../bar/widget-style.md).

### Compositor config (`x-compositor`)
A setting a compositor's config takes says how, per compositor: `x-compositor: { hyprland: {…}, sway: {…}, niri: {…} }`. `CompositorLayer.compositorFields` collects a section's annotated fields (inside its objects too) with their spec. Each is written, under a gated part (the input), only while its `if` switch is on, else once changed from its default; a managed config's options every one (`annotatedFields`).
- Every compositor's spec takes:
  - `key`: Hyprland's option path (or a list of paths), sway's command with `{}` for the value (`"input type:keyboard repeat_rate {}"`), or niri's node path (`"input.keyboard.repeat-rate"`, its value the node's argument).
  - `scale`: a factor for a value stored scaled (0.01 for a percent, 0.001 for ms written as seconds).
  - `if`: a boolean beside it (a part's `enabled`): written, default or not, only when that is on.
- Hyprland (`methods/HyprLua`, one value of a nested `hl.config({...})` table):
  - `value`: `"int"` (a boolean as 0/1), `"number"` (an enum of numbers written as strings), `"emptyIsDefault"` (`"default"` → `""`), `"color"` (a theme color name as `rgba(hex + alpha)`, `alpha` `"ff"` unless given).
  - `always: true`: written even when it's the schema default. Other fields are only written once changed, so Hyprland's own default (and the user's files) stay in charge otherwise.
- sway (`methods/SwayConf`; [Sway backend](../compositor/sway-backend.md)):
  - `value`: `"enabled"` (a boolean as `enabled`/`disabled`), `"yesNo"` (`yes`/`no`), `"enableDisable"` (`enable`/`disable`), `"raw"` (as it is, unquoted). Without one, the value is quoted as one argument (`SwayConf.quote`).
  - `map`: `{ value: sway's word }` for an enum whose names differ from sway's; a value missing from it is left out.
  - `skip`: a value written as nothing (sway's own default stays), e.g. `"default"`.
  - `configOnly: true`: sway takes the command only from a config file (`xkb_numlock`): left out of what's sent at runtime.
- niri (`methods/NiriConf`; [niri backend](../compositor/niri-backend.md)):
  - `value`: `"flag"` (a boolean as the node alone when on, left out when off: niri has no `false` for a flag), `"offFlag"` (the node alone when off, for a setting niri turns off with a flag: `animations.off`, `gestures.hot-corners.off`) or `"float"` (written with a point, where niri wants a float).
  - `skip`: a value written as nothing (niri's own default stays), e.g. `"default"` or `0`.

- `x-greeter: true` on an `Input` option: the greeter's compositor takes it (`methods/GreeterBundle`). See [Greeter install](../features/greeter-install.md).
- Details: [Hyprland config modes](../hyprland/config-modes.md), [Window look](../compositor/window-look.md).

### Theme integrations
- `x-hookup` (on a `ThemeIntegrations` boolean): how the integration hooks into its app (targets, place, text).
- `x-hookupNote`: a note shown with it.
- `x-profiles`: profile locations to search (Firefox and its forks; `scripts/integration_hookup.py`, `theme_firefox.sh`).
- See [Theme integrations](../theming/theme-integrations.md).
