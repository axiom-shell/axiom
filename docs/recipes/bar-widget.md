# Adding a bar widget

A bar widget is a type users add to a bar from the bar editor's library. You write a `schema.yaml` and a QML file that declares data on `BarWidget`; the base draws it, colours it and handles the pointer.

**Copy from** (`qml/components/bar/widgets/<Name>/`): `Weather` (polled data, a popout), `Updates` (a request, both buttons, a state field), `Bluetooth` (a one-tap action), `LockKeys` (`items`, `segmentData`, boxes). Each has its `schema.yaml` beside it.
**Background:** [bar/composition](../dev/bar/composition.md), [bar/widget-style](../dev/bar/widget-style.md) (the template, the guard, exceptions), [bar/display-styles](../dev/bar/display-styles.md), [schema annotations](../dev/core/schema-annotations.md) (`order:`), [config/BarWidgets](../dev/config/BarWidgets.md) (generated)

## Files
1. `qml/components/bar/widgets/<Type>/<Type>.qml` (a purpose comment above the root) and `schema.yaml` beside it, which the build expands over `definitions/kinds/WidgetBase.yaml`; nothing else lists the type.
2. A popout of its own: `qml/components/content/<Name>/<Name>.qml` ([bar-popout](bar-popout.md)); polled data: the service it acquires ([service](service.md)).

## Steps
1. **`schema.yaml`:** `label`, `icon`, `group` (one of `x-libraryGroups`); the parts it needs (`popout`, `colors: standard`, `appearance`, `boxes`); a colour field per state, `$ref: '#/definitions/WidgetColor'` with `title: <State> color`, a one-line `description` and an `x-autoColor` role (`accent` once per type; `alt`, `warning`, `critical`, `off`, `neutral`, `rise`, `fall`), plus `x-autoGradient: true` on an active state that isn't the accent; every key in `order:` in the settings' order (style, content, boxes, behaviour, actions, popout, colors, calm to loud, a switch's colour right under it; the build fails on a missing key; titles follow the settings around it, see `DevMode/schema.yaml`).
2. **`<Type>.qml`** on `BarWidget`, data only (settings are `properties.<key>`):

   | Kind | Properties |
   |---|---|
   | row | `icon`/`iconSource`, `text`, `minimumText`, `hidden` |
   | value | `ratio`, `history`, `subtext`, `labelShown` |
   | state | `accentField`, `muted`, `pulsing` |
   | marks | `badge`, `mark`, `iconField`, `busy` |
   | items | `items`, `segmentData`, read back as `shownItems` |
   | own content | `headIcon`/`headText`/`headItem`, `ownContent` drawn with `paint` |
   | interaction | `clickable`/`onClicked(button)`, `acceptedButtons`, `scrollable` |

   A widget names colour fields and never resolves a colour. Clicks run through `ActionsManager.run`; polled data acquires and releases a request built from `properties` only (`Component.onCompleted` / `onDestruction`).
3. **`scripts/dev/verify.sh`:** the `bar_widget_template` guard and `tst_Config` catch colour and field mistakes. Add an exception (`scripts/bar-widget-exceptions.json`, with a reason) only when the widget really isn't icon plus label: [widget-style › The widget template](../dev/bar/widget-style.md#the-widget-template).
4. One nested screenshot of the widget on a bar (`docs/dev/testing.md`).

## Watch out for
1. **The popout gate:** an anchor's `active` goes through `MenusConfig.opensOwnPopout(root.properties)`, never `properties.popout.enabled` alone.
2. **Resizing:** a value that gains or loses digits sets `minimumText` to its widest usual form (`"00%"`).
3. **Own content taller than a line** declares `ownAcross` from config, never measured.
4. **`items` and Repeater models come from config only** (`shownItems`), never live values.

## Docs to update
`docs/features.md`, if it lists bar widgets.
