# Recipe: a new bar widget

> **Use when:** adding a widget type users can put on a bar (it shows up in the bar editor's library).
> **Copy from:** `components/bar/widgets/IdleInhibitor/IdleInhibitor.qml` (service toggle, no popout), `components/bar/widgets/Weather/Weather.qml` (polled data + its own popout), `components/bar/widgets/Updates/Updates.qml` (an `acquire` request from settings, both buttons, `extraData`); schema `components/bar/widgets/IdleInhibitor/schema.yaml`.
> **Docs:** [bar/composition](../dev/bar/composition.md), [bar/widget-style](../dev/bar/widget-style.md), rules in `components/bar/widgets/AGENTS.md`; generated: [config/BarWidgets](../dev/config/BarWidgets.md).

## Files to touch
1. `components/bar/widgets/<Type>/<Type>.qml`: the widget. The file name is the type const.
2. `components/bar/widgets/<Type>/schema.yaml`: the type's schema, beside it. The build finds it (index.yaml's `kinds`), expands it over `definitions/kinds/WidgetBase.yaml` into `<Type>Widget` and adds it to `BarWidget`'s `oneOf`: nothing else to list.
3. `config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys, empty, to every language and the template (the title, descriptions and the type's `description`, which is its library label, are keys).
4. If it opens a popout of its own: `components/content/<Name>/<Name>.qml` ([bar-popout](bar-popout.md)).
5. If it needs data that's polled: the service's `acquire`/`release` ([service](service.md)).

## Skeleton
```qml
pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.<group>  // FooManager's folder: core, compositor, session, system, ui or apps
import qs.components.hosts.popout

// <One sentence: what it shows and what clicking does.>
BarIconWidget {
  id: root

  icon: FooManager.active ? "toggle_on" : "toggle_off"
  text: I18n.tr(FooManager.active ? "On" : "Off")
  showText: properties.showLabel
  accentColor: Theme.resolveColor(FooManager.active ? properties.activeColor : properties.inactiveColor)

  clickable: true
  onClicked: FooManager.toggle()

  // Only with a popout of its own (content/FooDetails.qml)
  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "FooDetails"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
  }
}
```
Schema (`schema.yaml` beside `Foo.qml`): only what's particular to the type. `label` is its library label (the `type` const's description), `settings` its `properties`; every other key becomes the annotation `x-<key>` (`group` is `x-libraryGroup`).
```yaml
label: Foo
icon: toggle_on
group: System
popout: own        # or menu (no popout of its own: it opens an edge menu), plain
colors: standard   # backgroundColor + foregroundColor, if it draws a box
settings:
  showLabel: {type: boolean, title: Show label, default: false}
  activeColor: {$ref: '#/definitions/WidgetColor', title: Active color}
  inactiveColor: {$ref: '#/definitions/WidgetColor', title: Inactive color, x-autoColor: 'off'}
```
- `popout` and `colors` pick parts of `WidgetBase`'s `x-parts`: `popout: own` adds `popout: { enabled, menu }` with "Its own popout"; `menu` the same as "Menu popout", off by default; `plain` only `enabled`. A part's key can be overridden (`popout: {variant: own, enabled: {default: false}}`).
- `WidgetColor` is the Auto color field (`default: ''`, `x-emptyLabel: Auto`, `x-autoColor: accent`, shown unless the bar's style is plain); override its title and role.
- A section of the type's own name (`Battery`) is linked from the inspector automatically (`x-link`), unless the type says `link`.

## Steps
1. Write `schema.yaml` first. Pick `group` from the root's `x-libraryGroups` (`Desktop`, `Time & weather`, `Media & audio`, `Network & devices`, `System`, `Tools`, `Look & layout`, `Session`).
2. Write `components/bar/widgets/<Type>/<Type>.qml` with its purpose comment above the root.
3. Read every setting as `properties.<key>` (always present: defaults are filled at load).
4. Polled data: a request built from `properties` only (copy `Updates.qml`'s `updatesRequest`), acquired in `Component.onCompleted` and on its change, released in `onDestruction`.
5. Verify.

## Gotchas
- `BarWidgetHost` handles `popout.menu` itself (an edge menu instead of the popout): the widget's own `PopoutAnchor` is gated by `EdgeMenusConfig.opensOwnPopout(root.properties)`, never by `properties.popout.enabled` alone.
- Every widget but Button, Separator and the tray has a `popout` part, even without a popout of its own (`menu`: they open an edge menu).
- A label that ticks (a countdown, an elapsed time, any number changing every second) sets `steadyDigits: true` on its `BarIconWidget`: tabular digits, sized by its digit count, so the bar doesn't resize every tick (only when it gains or drops a digit). Copy `Pomodoro.qml`.
- Sizes come from the bar (`barConfig.widgetSize`, `barConfig` padding/spacing/font/radius), never `Widget.*`. `BarIconWidget` already does this; a widget drawing more must too.
- A color field the bar should pick when empty is a `WidgetColor` (`default: ''`, `x-emptyLabel: Auto`) with an `x-autoColor` role (`accent`, `alt`, `warning`, `critical`, `off`, `neutral`). `tst_Config` checks these.
- Color fields show only in the bar looks they do something in (`$bar.<key>` conditions; the rules are in [bar/widget-style](../dev/bar/widget-style.md#which-color-fields-show)): the state colors that feed `accentColor` hide under Plain text, and `foregroundColor` shows only when filled, not merged, with the bar's text color Auto. A widget without an icon shows its color only boxed and not merged, or underlined (`TimeWidget`).
- The type const must not match a `components/content/` file another file sees alongside it (e.g. a `Battery` widget and `Battery` content): `check_structure.py` errors.
- `hidden: true` hides the widget and disables its clicks; use it for "hide when empty" settings.
- `onClicked` gets the button when `acceptedButtons` lists more than one (`Updates.qml`).

## Verify
- `scripts/dev/verify.sh`
- `scripts/run_tests.sh Config` (every default is valid; auto colors)
- Add it to a bar in the bar editor and look: `scripts/dev/shot.sh page BarEditor`.

## Docs to update
- [bar/widget-style](../dev/bar/widget-style.md) only if it introduces a new base or color rule.
- `docs/features.md` bar widget list, if it lists widgets.
