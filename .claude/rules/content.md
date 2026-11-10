---
paths:
  - "qml/components/content/**"
---

# Content (`qml/components/content/`)

Every loadable panel, by name: overlay modules (`<Type>/<Type>.qml` + `schema.yaml`; also used by menus, the desktop, the lock screen and the greeter) and bar popouts (by `popoutName`). `base/` holds the roots, `parts/` shared parts. Docs: `docs/dev/overlay/content-roots.md`, `writing-modules.md`, `grow-expand.md`. Recipes: `/overlay-module`, `/bar-popout`.

- **Root is `Card`** (free-form) **or `Panel`** (a column; usable as a bar popout and a card, `embedded` in a card). Both expose `properties`, `slotRect`, `cols`/`rows`, `shape`, `compact`, `pad`, `host`.
- **The schema** is expanded over `definitions/kinds/ModuleBase.yaml`, which supplies `place`, `properties` and the default hosts (overlay, menu, desktop): write no `$ref` or `oneOf`. It needs `label`, `icon`, `group`; `defaultSize: [w, h]` (grid units, four to a card) if the default is wrong; `keyboard: true` for a text field (`false` only to stay read-only on the desktop).
- **Lock screen and greeter are opt-in hosts** (`hosts: [lockscreen, greeter]`). `lockscreen` only for a module that shows nothing private; it acts only as its `lockActions` say (`check_structure` fails any other service call but a read, or one marked `// lock-inert: <reason>`). A greeter module is inert unless `host.kind === "greeter" && !host.preview && Paths.greeter`.
- **Modules take any size**: set `fullMinWidth`/`fullMinHeight` (px inside the padding; from `Appearance.fontSize` if text-bound), show `compactContent` (e.g. `CompactFigure`) below them, and adapt to `shape`/`compact`.
- **A popout-only panel** has no schema: a `Panel` with `implicitWidth`, opened by a widget's `PopoutAnchor`. Keys of the anchor's `extraData` are copied onto declared properties, so declare them. `wantsKeyboardFocus` for text fields, `maxImplicitHeight` if it grows. Copy `WeatherForecast`. Inside popout or menu content, a `PopoutAnchor` opens a submenu (one level deep).
- **Modules exist only while their page is shown** (current page and neighbours, overlay open): acquire on completion, release on destruction, keep lasting state in a service.
- **Build only what shows**: a list that can grow is a ListView (`parts/DeviceList.qml`), an expansion is built only while expanded, a one-mode part is a Loader gated on its mode, not `visible: false`. A slow module logs `Built overlay module <Type> in X ms` (`--debug`).
- **Adding one to the live config** to test: confirm the schema reloaded first (a config validated against a stale schema falls back to defaults), add one at a time and watch qs's RSS.
