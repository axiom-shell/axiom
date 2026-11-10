# Adding a bar popout

A bar popout is the panel that opens when you hover a bar widget: the weather forecast, the package list, the Bluetooth devices. It is a content file named after the popout, opened by a `PopoutAnchor` in the widget. At the end you have a `Panel` and the anchor that opens it.

**Copy from:** `qml/components/content/WeatherForecast/WeatherForecast.qml` (a `Panel` fed by a service), `qml/components/content/Caffeine/Caffeine.qml` (a panel filled from the anchor's `extraData`, and also usable as an overlay card), `qml/components/bar/widgets/IdleInhibitor/IdleInhibitor.qml` (the anchor with `extraData`), `qml/components/hosts/popout/PopoutAnchor.qml` (the anchor's API).
**Background:** [overlay/content-roots](../dev/overlay/content-roots.md), [popouts/hosts-and-switching](../dev/popouts/hosts-and-switching.md)

## Files
1. `qml/components/content/<Name>/<Name>.qml`: the panel, with a purpose comment above the root. `<Name>` is the `popoutName`.
2. The widget that opens it, with a `PopoutAnchor` ([bar-widget](bar-widget.md)).

A popout-only panel needs no schema entry. If the same file should also be an overlay module, add one as in [overlay-module](overlay-module.md).

## Steps
1. Write a `Panel` (`qml/components/content/base/Panel.qml`) and give it an `implicitWidth`. Build it from `body` and `margins` so it fits its content; `WeatherForecast.qml` sizes itself with `Widget.px(300)`, so use `Widget.px` rather than a bare number.
2. Data comes from a service the widget keeps acquired. The panel only reads it (`WeatherForecast` reads `WeatherManager`).
3. Values the widget wants to hand over go in the anchor's `extraData`. Declare a property of the same name on the panel for each key (`presets` in `Caffeine.qml`); the host copies each key onto it and skips readonly ones.
4. In the widget, add the anchor with a literal `popoutName: "<Name>"`:
   ```qml
   PopoutAnchor {
     hitArea: root.hitArea
     popoutName: "Caffeine"
     active: MenusConfig.opensOwnPopout(root.properties) && !root.hidden
   }
   ```
   The name is literal so `check_structure` can check that the file exists.

## Watch out for
- **Read `extraData` through your own properties**, never the wrapper's `currentData`.
- **Text fields and growth.** A text field inside needs `wantsKeyboardFocus: true`. A panel that grows needs `maxImplicitHeight` (and `maxImplicitWidth` if it widens), and should keep its controls still: it sizes to what it shows and sets `flips` so they stay beside the bar when it grows upwards ([Bar popout window sizing](../dev/popouts/hosts-and-switching.md#bar-popout-window-sizing)).
- **Submenus.** A popout opened from inside popout or menu content becomes that popout's submenu (one level deep). It is the same `PopoutAnchor`, with no extra code.
- **Computed names are unchecked.** `check_structure` only checks literal `popoutName` values.
- **Unused content is reported.** A content file used by no module and no popout fails the check.
- **Animation.** Durations are `Appearance.anim*`; content that changes in place cross-fades with `CrossFade`.

## Check it
- `scripts/dev/verify.sh`
- Hovering can't be simulated, so read the anchor's `active` and the log. A panel that is also a module can be seen on a page: `scripts/dev/shot.sh page <ViewType>`.

## Docs to update
- The feature's doc in `docs/dev/features/`, if the panel adds behaviour worth knowing.
