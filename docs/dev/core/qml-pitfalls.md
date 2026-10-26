# QML pitfalls

> **Files:** `components/reusable/StyledTextEntry.qml`, `components/bar/BarWidgetHost.qml`, `components/hosts/popout/BarPopouts.qml`, `components/hosts/overlay/OverlaySlot.qml`, `components/hosts/overlay/OverlayPanel.qml`
> **Config:** none
> **Related:** [Shared UI pieces](shared-ui-pieces.md), [Editors pattern](editors-pattern.md), [Shadows](../popouts/shadows.md), [Testing](../testing.md)

Traps of QML, Qt's JS engine and Quickshell that have each cost a debugging session in axiom. Read it before writing QML; add one when a new trap bites.

### The JS engine
- No `Array.prototype.flatMap`: use `[].concat(...arr.map(...))`.
- No `Object.fromEntries`: use `reduce`.
- No `Intl`: dates go through `I18n.formatDate`.
- **Never an optional call on a computed member** (`handlers[name]?.(x)`): Qt 6.12's compiler segfaults on it while loading the file, so a hot reload kills the live shell. Take the member into a `const` and test it (`const fn = handlers[name]; if (fn) fn(x);`). An optional call on a plain name (`done?.(x)`) is fine. `check_structure.py` refuses the form.

### Bindings and properties
- `StyledTextEntry` writes every keystroke back to `text`, dropping any binding: push the value in (on selection/draft changes, unless focused) and act on its `textEdited` (typing only, never a value pushed in). A field that commits on focus loss commits only if `typed`, or text it was left showing lands on whatever it edits by then.
- An object literal as a property value needs parentheses: `payload: ({ … })`; `payload: { … }` is a code block.
- Assigning a bound property (`currentIndex = i`) breaks its binding: change the source it's bound to instead.
- A derived type must not redeclare a property its base declares (it shadows the base's, e.g. an alias).
- `visible: visibleChildren.length > 0` locks itself hidden (children read invisible with their parent); use `children.length` or a flag.
- A function-valued property (`labelOf: x => …`) works as a hook.
- A Quickshell `Socket` on a listening Unix socket connects synchronously: `connectionStateChanged` fires before `connected: true` (or `createObject` of a component declaring it) returns. Store the socket wherever its handlers look for it before connecting it (`BackendManager._connect`), or the first signal is lost.

### Types and qmllint
- Signal parameters or properties typed `Item` that callers read custom members of trip qmllint (`missing-property`): type them `var`.

### URL-loaded files
Bar widgets, content and views are loaded by URL.
- They see sibling types only because some loaded file imports their directory by name (`BarWidgetHost` → `qs.components.bar.widgets`, `BarPopouts`/`OverlaySlot` → `qs.components.content`, `OverlayPanel` → `qs.components.views`).
- A new directory imported only from URL-loaded files isn't scanned until qs restarts (`module "qs.…" is not installed`): ask the user to restart. New singletons are picked up by a hot reload (qs 0.3.1).
- An inline `component A` using another inline `component B` of the same file fails with "A is not a type": inline B's body.

### Effects
- A `MultiEffect` handed a visible item's own layer (`layer.enabled` source) pads that layer and redraws the item shrunk and offset; handed a `ShaderEffectSource` with `autoPaddingEnabled`, it stretches it. Shadows of visible surfaces go through `OutsideShadow` (explicit padding).
