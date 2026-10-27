# Bar widgets (`components/bar/widgets/`)

A file here is a bar widget type: `<Type>.qml` is loaded by `BarContainer` from `"widgets/" + type + ".qml"`. Docs: `docs/dev/bar/composition.md`, `widget-style.md`, `widget-shapes-runs.md`.

**Recipe:** `docs/recipes/bar-widget.md` (and `docs/recipes/bar-popout.md` for its popout); verify with `scripts/dev/verify.sh`.

- **A new widget = this file + a `<Type>Widget` definition in `config/json/config.schema.json` + its `$ref` in `definitions.BarWidget.oneOf`.** Copy `IdleInhibitor.qml` (service toggle), `Weather.qml` (polled data + popout) or `Updates.qml` (request, both buttons, `extraData`), and the `IdleInhibitorWidget` schema entry.
- Icon + label widgets extend `BarIconWidget` (`icon`, `text`, `showText`, `accentColor`, `clickable`, `onClicked`); others extend `BarWidget`. Both get `barConfig`, `panel`, `screen`, `properties`.
- The widget's settings are `properties.<key>` (schema `properties.properties`); bar-level values are `barConfig.<key>` (some are derived by `BarsConfig.enrichBarConfig`, not schema keys).
- **Sized by the bar**: cross size `barConfig.widgetSize`; padding, spacing, font size and radius from `barConfig`, never `Widget.*`.
- **A ticking label** (countdown, elapsed time) sets `steadyDigits: true`: the widget is sized by the label's digit count, not each second's digits, so the bar doesn't resize every tick.
- Colors: config names through `Theme.resolveColor(properties.X)`; color fields use `x-options: "colors"` and, when the bar should pick one, `x-autoColor` (checked in `tst_Config`). Each color field is shown only in the bar looks it does something in, through `$bar.<key>` conditions (`docs/dev/bar/widget-style.md` › Which color fields show).
- The type's schema is `<Type>/schema.yaml` beside its QML, expanded over `WidgetBase` (`docs/recipes/bar-widget.md`): it needs a `label` (its library label), an `icon` and a `group` from the root's `x-libraryGroups`. Every widget but Separator has a `popout` part (`popout.enabled` / `popout.menu`, an edge menu id); `menu` for one with no popout of its own (Button's opens only a menu).
- A popout opens through `PopoutAnchor { hitArea: root.hitArea; popoutName: "<Name>"; active: EdgeMenusConfig.opensOwnPopout(root.properties) && … }`; the content is `components/content/<Name>/<Name>.qml`.
- Polled data: `readonly property var <x>Request: ({ … })` built from `properties` only; `acquire` in `Component.onCompleted` and on its change, `release` in `onDestruction`.
- A widget must never see a same-named content type (e.g. widget `Battery` and content `Battery`): `check_structure.py` catches it.
- After: `scripts/dev/verify.sh` (it runs `tst_Config` when the schema changed); the pre-commit hook adds the new strings to the language files.
