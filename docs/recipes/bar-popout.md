# Recipe: a bar popout (content panel)

> **Use when:** a bar widget should open a panel on hover (forecast, package list, device list), or an existing panel should open from a new widget.
> **Copy from:** `components/content/WeatherForecast/WeatherForecast.qml` (a `Panel` fed by a service), `components/bar/widgets/Updates/Updates.qml` (anchor with `extraData`), `components/hosts/popout/PopoutAnchor.qml` (the anchor's API).
> **Docs:** [overlay/content-roots](../dev/overlay/content-roots.md), [popouts/hosts-and-switching](../dev/popouts/hosts-and-switching.md), rules in `components/content/AGENTS.md`.

## Files to touch
1. `components/content/<Name>/<Name>.qml`: the panel. `<Name>` is the `popoutName`.
2. The widget that opens it: a `PopoutAnchor` ([bar-widget](bar-widget.md)).
3. No schema entry for a popout-only panel. If the same file should also be an overlay module, add one as in [overlay-module](overlay-module.md).

## Skeleton
```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.<group>  // FooManager's folder: core, compositor, session, system, ui or apps
import qs.components.reusable
import qs.components.content.base

// <What it lists>: the <Widget> widget's popout, from FooManager.
Panel {
  id: root

  // Filled from the anchor's extraData (keys copied onto declared properties)
  property var items: []

  spacing: Widget.padding
  implicitWidth: Math.max(300, body.implicitWidth + margins * 2)

  StyledText {
    text: I18n.tr("{0} items", root.items.length)
    font.bold: true
    textColor: Theme.accent
  }
}
```
In the widget:
```qml
PopoutAnchor {
  hitArea: root.hitArea
  popoutName: "FooList"
  active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
  extraData: ({
      "items": root.items
    })
}
```

## Steps
1. Write the `Panel` with an `implicitWidth`; build it from `body`/`margins` so it fits its content.
2. Declare a property for every `extraData` key: `BarPopouts` copies each key onto a property of the same name (skipping readonly ones).
3. Add the `PopoutAnchor` with a literal `popoutName: "<Name>"` (so `check_structure.py` can check the file exists).
4. Verify.

## Gotchas
- Declare `extraData` keys as properties; never read the wrapper's `currentData`.
- A text field inside needs `wantsKeyboardFocus: true`; a panel that grows needs `maxImplicitHeight` (and `maxImplicitWidth` if it widens).
- A popout opened inside popout or edge menu content becomes that popout's submenu (`SubPopout`, one level deep): same `PopoutAnchor`, no extra code.
- Data is the service's: the widget keeps it acquired; the panel only reads (`WeatherForecast` reads `WeatherManager.source`).
- `check_structure.py` only checks literal `popoutName: "…"` values; a computed name isn't checked.
- A content file used by nothing (no module, no popout) is reported.
- Animations use `Appearance.anim*`; content changing in place cross-fades with `CrossFade`.

## Verify
- `scripts/dev/verify.sh`
- Hovering can't be simulated: reason through the anchor's `active` and the logs. A Panel that is also a module can be seen on a page: `scripts/dev/shot.sh page <ViewType>`.

## Docs to update
- The feature's doc in `docs/dev/features/` if it adds behaviour worth knowing.
