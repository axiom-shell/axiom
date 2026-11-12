# Adding a bar widget

A bar widget is a type users add to a bar from the bar editor's library: a clock, a battery, a toggle. At the end you have a QML file, a `schema.yaml` beside it that declares its settings and library entry, and (if it needs one) a popout on hover.

**Copy from:** `qml/components/bar/widgets/Bluetooth/Bluetooth.qml` (an icon and a label, a click that runs an action, middle click, a popout), `qml/components/bar/widgets/IdleInhibitor/IdleInhibitor.qml` (state from a service, a popout with `extraData`), `qml/components/bar/widgets/Weather/Weather.qml` (polled data), `qml/components/bar/widgets/Updates/Updates.qml` (a poll request built from settings, two mouse buttons), `qml/components/bar/widgets/LockKeys/LockKeys.qml` (one box per item). Their schemas are the `schema.yaml` beside each.
**Background:** [bar/composition](../dev/bar/composition.md), [bar/widget-style](../dev/bar/widget-style.md), [bar/display-styles](../dev/bar/display-styles.md), [config/BarWidgets](../dev/config/BarWidgets.md) (generated)

## Files
1. `qml/components/bar/widgets/<Type>/<Type>.qml`: the widget. The file name is the type name, and a purpose comment sits above the root object.
2. `qml/components/bar/widgets/<Type>/schema.yaml`: its schema. The build finds it and expands it over `qml/config/schema/definitions/kinds/WidgetBase.yaml` into `<Type>Widget` in `BarWidget`'s `oneOf`; nothing else lists it.
3. If it opens a popout of its own: `qml/components/content/<Name>/<Name>.qml` ([bar-popout](bar-popout.md)).
4. If it shows polled data: the service it acquires ([service](service.md)).

New translation keys (titles, descriptions, the library label) are added to the language files by the pre-commit hook.

## Steps
1. Write `schema.yaml` first. Start from `IdleInhibitor/schema.yaml` or `Bluetooth/schema.yaml`:
   - `label` is the library label and is also used on the board and in the inspector, so keep it one short name; other words it should be found by go in `keywords`.
   - `group` is one of the root's `x-libraryGroups` (`qml/config/schema/index.yaml`).
   - `settings` are the widget's own properties; any other top-level key becomes an `x-<key>` annotation (`group` is `x-libraryGroup`). `priority`, `elastic`, `link`: [schema-annotations › Types](../dev/core/schema-annotations.md#types-bar-widgets-overlay-modules-views-custom-widget-elements).
   - Parts of `WidgetBase` are switched on by name: `popout` (`own`, `menu` or `plain`), `colors: standard` (background and text color), `appearance` (`variant: value`, with the display styles it can draw), `boxes` (`variant: each`, see below). A part's key can be overridden.
   - Add every setting, your colour fields included, to the type's `order:` list (style → content → boxes → behaviour → actions → popout → colors, calm to loud; a colour shown only under a switch goes right under it). The build fails on a missing key.
2. Write the QML: a `BarWidget` that sets data and lets the base draw it. Settings are `properties.<key>`, always present because defaults are filled at load. Set `icon`, `text` (and `minimumText`) for a row, `items` and `segmentData` for several items, `headIcon`/`ownContent` for content of its own, plus `accentField` and `muted` for state colours. Copy `Weather` or `Updates`.
3. A click on something one-tap (a toggle, a session action) runs through `ActionsManager.run("<id>", { "fromScreen": true })`, not the service's own toggle. `Bluetooth.qml` and `IdleInhibitor.qml` show it; the ids are the rows of the keybind table ([actions](../dev/core/actions.md)).
4. Polled data: build the request from `properties` only, acquire it in `Component.onCompleted` and again when it changes, release it in `Component.onDestruction` (`Updates.qml`'s `updatesRequest`).
5. A popout of its own: a `PopoutAnchor` as in `Bluetooth.qml`, gated by `MenusConfig.opensOwnPopout(root.properties)` and, if the widget can hide, `!root.hidden`.
6. Several items (metrics, keys, accounts)? Add `boxes: {variant: each, boxes: {x-boxItems: …}}` to the schema, as `LockKeys/schema.yaml` does. The user can then draw one box per item; the host hands the widget its item as `box` ([widget-style › Boxes: one per item](../dev/bar/widget-style.md#boxes-one-per-item)).
7. Want it to split on a split-style bar? It needs an icon part and a label. A label that would otherwise make it too wide is an opt-in setting that defaults to off (Volume's `showDevice`, Notifications' `label`), so bars that don't split look as before. A `BarWidget` drawing its own content gets a head from `SplitLead` (Time, the tray). See [widget-style › Split](../dev/bar/widget-style.md#split).

## Watch out for
- **The popout gate.** The host opens a menu itself when `popout.menu` is set, so the anchor's `active` goes through `MenusConfig.opensOwnPopout`, never `properties.popout.enabled` alone.
- **Which widgets have a `popout` part.** Every type except Separator and Spacer. A widget with no popout of its own (Button) uses `variant: menu`; the tray uses `plain`.
- **Resizing.** Digits are equal width and measured as zeros, so a ticking clock never moves the bar. A value that gains or loses digits (a percent, a count) sets `minimumText` to its widest usual form with two digits (`"00%"` in `Battery.qml`; 100% may widen it).
- **Sizes come from the bar** (`barConfig.thickness`, `innerPadding`, `innerGap`, `fontSize`, `radius`), never `Widget.*`, so the widget scales with the bar. The base classes already do this.
- **Content taller than one line** (two lines, a graphic, cells) declares `contentAcross` from config, never measured, so a capsule's end keeps clear of it ([widget shapes and runs](../dev/bar/widget-shapes-runs.md#backgrounds-and-shapes)).
- **Colours.** Read `colors` and `paint` (`WidgetLook`: `paint.field(name, part)`, `paint.muted`); never set `iconColor` or `foregroundColor` (the base does) and never call `BarsConfig.widgetColors`.
  - A colour of the widget's own on its content goes through `contentColor(color, "icon"|"text")` (or `iconOwnColor` for the icon), which nudges it to read on what it sits on; another field's colour as drawn here (the gradient's) through `drawnColor(field)`.
  - One `x-autoColor: accent` per widget type (`tst_Config` checks); a usual idle state is `rest`, a second state `alt`. A colour the bar picks when empty is a `WidgetColor` with an `x-autoColor` role. Show a color field only in the looks it does something in, with `$bar.<trait>` conditions in `x-showIf`, never a list of widget styles ([which color fields show](../dev/bar/widget-style.md#which-color-fields-show)).
- **Never ask which style the bar has.** Draw in `colors` (`WidgetLook`) and read the look's traits; `check_structure` fails a read of `widgetStyle` or `look.style` outside `BarLook`.
- **Name clash.** The type name must not match a file in `qml/components/content/` (a `Battery` widget and `Battery` content): `check_structure` errors, because both would resolve in the same scope.
- **`hidden: true`** hides the widget and disables its clicks; use it for "hide when empty" settings.
- **Several mouse buttons.** `onClicked` receives the button when `acceptedButtons` lists more than one (`Bluetooth.qml`, `Updates.qml`).

## Check it
- `scripts/dev/verify.sh`
- `scripts/run_tests.sh Config`: every default is valid and the auto colors resolve.
- Add the widget to a bar in the bar editor and look: `scripts/dev/shot.sh page BarEditor`. Hovering can't be simulated, so for a popout read the anchor's `active` and the log.

## Check it in every style
Colours and split have gone wrong in styles nobody looked at. In a nested shell (`docs/dev/testing.md`), look at the widget in each of the seven widget styles, split joined and badge, merged and powerline, the gradient on, and each display style it lists. Set them with `axiom config set --socket <nested> --config-dir <scratch>/config/axiom Bars.items.<id>.widgets.<section>.<widget id>.properties…` (always both flags, or it writes the live config). Text and icons must read, a split widget must show its icon part, and a state colour must not vanish on its own fill.

## Docs to update
- [bar/widget-style](../dev/bar/widget-style.md), only if the widget introduces a new base class or color rule.
- `docs/features.md`, if it lists bar widgets.
