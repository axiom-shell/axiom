# Adding an overlay module

A module is a card you can place on an overlay page, in a menu and on the desktop, and on the lock screen or login screen when it opts in. Users add it from the library in the layouts editor. At the end you have a QML file and a small `schema.yaml` that makes it show up there, in any size.

**Copy from:** `qml/components/content/Battery/Battery.qml` (a `Card` with `fullMinWidth`/`fullMinHeight`, `compactContent: CompactFigure`, a layout that follows `shape`) and its `schema.yaml` (which adds lock screen and greeter `hosts`); `qml/components/content/Calculator/schema.yaml` (a module with `settings` and a text field, so `keyboard: true`); `qml/components/content/ColorSwatch/ColorSwatch.qml` (driven by `properties`); `qml/components/content/Disks/Disks.qml` (acquiring a polled service).
**Background:** [writing modules](../dev/overlay/writing-modules.md), [content roots](../dev/overlay/content-roots.md), [growing and expanding](../dev/overlay/grow-expand.md), [shared UI pieces](../dev/core/shared-ui-pieces.md), [schema annotations](../dev/core/schema-annotations.md); generated: [config/OverlayModules](../dev/config/OverlayModules.md)

## Files
1. `qml/components/content/<Type>/<Type>.qml`: the module. The file name is the type.
2. `qml/components/content/<Type>/schema.yaml`: only what is particular to the type. The build expands it over `qml/config/schema/definitions/kinds/ModuleBase.yaml`, which supplies `type`, `id`, `place`, the `properties` object and the default `x-hosts`, and adds `<Type>OverlayModule` to `OverlayModule`. Write no `$ref` or `oneOf` by hand.
3. A service, if it needs data ([service](service.md)). A module only reads a service and acquires it.

Translation files need nothing: the pre-commit hook adds new strings to every language.

## Steps
1. Write `schema.yaml`. `label` is the name in the library; `icon`, `group` (one of the `x-libraryGroups` in `qml/config/schema/index.yaml`) and the other keys become `x-<key>` annotations (`group` becomes `x-libraryGroup`); `settings` become the module's `properties`, each with a `default`. Add `defaultSize: [w, h]` (grid units, four to a card) if one card is the wrong starting size, and `minSize` if it can't shrink to half of that.
2. Decide the hosts. Overlay pages, menus and the desktop are the default and every module is on all three (`check_structure` fails a module that lists `overlay` but not `desktop`). Add `hosts: [lockscreen, greeter]` only under the rules in the next section.
3. If the module has a text field, in its file or in a part it uses, set `keyboard: true`, so the desktop gives it the keyboard on a click. Use `false` only to keep it read-only there on purpose (ClockCalendar). `check_structure` fails a text field with neither.
4. Write the module on `Card` (free-form) or `Panel` (a column that can also be a bar popout). Read its settings as `root.properties.<key>`.
5. Make it work at any size: set `fullMinWidth` and `fullMinHeight` in pixels (from `Appearance.fontSize` when they depend on text), give it a `compactContent` for below that, and let the layout follow `shape` and `compact`.
6. If it polls a service, call `acquire(root, …)` in `Component.onCompleted` and `release(root)` in `Component.onDestruction`.
7. Put it on a page and on the desktop in a nested shell and look at both.

## Watch out for
- Modules exist only while their page is shown, so lasting state goes in a service.
- Repeater models and `acquire` requests come from config or counts, never live values. A model rebuilt on every sample once pushed qs past 25 GB.
- A module named like a config section links its settings to that section (`x-link`) unless the schema says `link`.
- `lockscreen` in `hosts` is only for a module that shows nothing private. What it may do there is its `lockActions`, and `check_structure` fails any other service call in it or its parts except a read (or one marked `// lock-inert: <reason>`). Greeter modules do nothing unless `host.kind === "greeter" && !host.preview && Paths.greeter`.
- An inline `component` can't use another inline component of the same file; the file is loaded by URL and fails with "is not a type".
- Look in `qml/components/content/parts/` (`ModuleHeader`, `CompactFigure`, `StatFigure`, `Sparkline`, `EmptyState`, `TileGrid`, …) and in shared UI pieces before drawing your own.
- A list that can grow is a ListView, and a part shown in one mode only is a Loader, not `visible: false`.
- A module that wants more rows (`properties.grow`) or a detail view (`expand()`) follows [growing and expanding](../dev/overlay/grow-expand.md).

## Check it
- `scripts/dev/verify.sh`, and `scripts/run_tests.sh Config` for the schema defaults.
- The running shell loaded its schema at start. Only dev mode (`axiom dev status`, switched by the user) rebuilds it when a YAML file changes; otherwise the new type isn't known and a config holding it won't save. Test in `scripts/dev/nested.sh <compositor>` or ask the user to restart axiom on a rebuilt binary.
- Add one module at a time, watch qs's memory, then `scripts/dev/shot.sh page <ViewType>` and read `scripts/log.sh`. A module slower than a frame logs `Built overlay module <Type> in X ms` with `--debug`.

## Docs to update
- [utility modules](../dev/overlay/utility-modules.md) if it is a tool-like module, otherwise the doc of its feature.
- `docs/features.md`, which counts and lists the modules.
