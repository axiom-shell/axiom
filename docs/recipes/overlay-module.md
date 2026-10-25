# Recipe: a new overlay module

> **Use when:** adding a card type for overlay pages (also usable in edge menus and on the desktop, and on the lock screen or greeter when it opts in).
> **Copy from:** `components/content/Battery/Battery.qml` (`Card`, `fullMinWidth`/`fullMinHeight`, `compactContent: CompactFigure`, `shape`), `components/content/ColorSwatch/ColorSwatch.qml` (driven by `properties`); schema `components/content/Battery/schema.yaml` (with `hosts`) or `components/content/Calculator/schema.yaml` (with `settings`).
> **Docs:** [overlay/writing-modules](../dev/overlay/writing-modules.md), [overlay/content-roots](../dev/overlay/content-roots.md), [overlay/grow-expand](../dev/overlay/grow-expand.md), rules in `components/content/AGENTS.md`; generated: [config/OverlayModules](../dev/config/OverlayModules.md).

## Files to touch
1. `components/content/<Type>/<Type>.qml`: the module. The file name is the type const.
2. `components/content/<Type>/schema.yaml`: the type's schema, beside it. The build finds it (index.yaml's `kinds`), expands it over `definitions/kinds/ModuleBase.yaml` into `<Type>OverlayModule` and adds it to `OverlayModule`'s `oneOf`: nothing else to list.
3. `config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys, empty, to every language and the template.
4. A service, if it needs data ([service](service.md)): modules only read and acquire.

## Skeleton
```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.<group>  // FooManager's folder: core, compositor, session, system, ui or apps
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// <What it shows>; compact, <the one figure>.
Card {
  id: root

  readonly property bool sideBySide: root.shape === "horizontal"

  // Below these it shows compactContent instead (px, from the font size)
  fullMinWidth: Appearance.fontSize * 8
  fullMinHeight: Appearance.fontSize * 6

  compactContent: CompactFigure {
    icon: "bolt"
    value: String(FooManager.value)
    label: I18n.tr("Foo")
  }

  Component.onCompleted: FooManager.acquire(root, ({ "interval": 2000 }))
  Component.onDestruction: FooManager.release(root)

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    StyledText {
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: root.properties.label
      font.bold: true
    }
  }
}
```
Schema (`schema.yaml` beside `Foo.qml`): only what's particular to the type. `label` is its library label, `settings` its `properties`; every other key becomes the annotation `x-<key>` (`group` is `x-libraryGroup`).
```yaml
label: Foo
icon: bolt
group: System
defaultSize: [4, 2]
settings:
  label: {type: string, title: Label, default: ''}
```

## Steps
1. Schema first. `defaultSize: [w, h]` in grid units (four to a card) if one card is the wrong starting size; `minSize` if it can't shrink that far.
2. Hosts: the base lists `overlay`, `edgeMenu` and `desktop` (**every module goes on the desktop**); a type's `hosts` adds to them, `lockscreen` and `greeter` only under their rules (below).
3. Typing: a module with a text field (in its file or a part it uses) sets `keyboard: true`, so the desktop hands it the keyboard on a click; `false` only to keep it read-only there on purpose (ClockCalendar). `check_structure` fails a text field with neither.
4. Write the module: `Card` for free-form, `Panel` for a column that can also be a bar popout. Read settings as `root.properties.<key>`.
5. Make it work at any size: `fullMinWidth`/`fullMinHeight` plus `compactContent`, and a layout that adapts to `shape` (`"horizontal"`, …) and `compact`.
6. Verify, then add it to a page and to a desktop layout to see it in both.

## Gotchas
- Modules exist only while their page is shown: acquire in `Component.onCompleted`, release in `onDestruction`, keep lasting state in a service.
- Repeater models and `acquire` requests come from config or counts, never live values (a model rebuilt per sample once pushed qs past 25 GB).
- `lockscreen` in `hosts` only for a module that launches, dispatches and writes nothing and shows nothing private. Greeter modules are inert unless `host.kind === "greeter" && !host.preview && Paths.greeter`.
- No inline `component` using another inline component of the same file (URL-loaded: "is not a type").
- Shared parts are in `components/content/parts/` (`ModuleHeader`, `CompactFigure`, `StatFigure`, `Sparkline`, `EmptyState`, `TileGrid`, …): check them and [core/shared-ui-pieces](../dev/core/shared-ui-pieces.md) before drawing your own.
- A module that wants more rows (`properties.grow`) or a detail view (`expand()`): [overlay/grow-expand](../dev/overlay/grow-expand.md).

## Verify
- `scripts/dev/verify.sh`
- `scripts/run_tests.sh Config`
- **On the live shell:** a running `axiom run` read the schema at its start; only dev mode (`axiom dev status`; the user switches it) rebuilds it on a YAML edit (`schema.changed`). Without it, the new type isn't in the running schema, and a config holding it doesn't save: test in `scripts/dev/nested.sh`, or ask the user to restart axiom on a rebuilt binary. Add one module at a time, watch qs's RSS, then `scripts/dev/shot.sh page <ViewType>`.

## Docs to update
- [overlay/utility-modules](../dev/overlay/utility-modules.md) if it's a tool-like module; the feature's doc otherwise.
- `docs/features.md` if it lists modules.
