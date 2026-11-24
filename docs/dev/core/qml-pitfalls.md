# QML pitfalls

> **Files:** `qml/components/reusable/StyledTextEntry.qml`, `qml/components/bar/BarWidgetHost.qml`, `qml/components/hosts/popout/BarPopouts.qml`, `qml/components/hosts/overlay/OverlaySlot.qml`, `qml/components/hosts/overlay/OverlayPanel.qml`
> **Config:** none
> **Related:** [Shared UI pieces](shared-ui-pieces.md), [Editors pattern](editors-pattern.md), [Shadows](../popouts/shadows.md), [Testing](../testing.md)

Traps of QML, Qt's JS engine and Quickshell that have each cost a debugging session in axiom. Read it before writing QML; add one when a new trap bites.

### The JS engine
- No `Array.prototype.flat` or `flatMap`: use `[].concat(...arr)` / `[].concat(...arr.map(...))`.
- No `Object.fromEntries`: use `reduce`. `check_structure.py` refuses all three.
- No `Intl`: dates go through `I18n.formatDate`.
- **Never an optional call on a computed member** (`handlers[name]?.(x)`): Qt 6.12's compiler segfaults on it while loading the file, so a hot reload kills the live shell. Take the member into a `const` and test it (`const fn = handlers[name]; if (fn) fn(x);`). An optional call on a plain name (`done?.(x)`) is fine. `check_structure.py` refuses the form.
- No logical assignment (`??=`, `||=`, `&&=`): a parse error that fails the whole module's import; write `x ?? (x = …)`.
- **`Unable to assign [undefined] to …` at a singleton's property on every reload** is Qt 6.12.0's own bug ([QTBUG-149607](https://bugreports.qt.io/browse/QTBUG-149607): with the old and new generations' engines both alive, a composite type's cast fails), not the binding: Arch's `qt6-declarative` 6.12.0-2 carries the fix. Don't work around it in QML.

### Bindings and properties
- `StyledTextEntry` writes every keystroke back to `text`, dropping any binding: push the value in (on selection/draft changes, unless focused) and act on its `textEdited` (typing only, never a value pushed in). `CommitEntry` (forms) is this rule written once: use it for a field editing a value kept elsewhere. A field that commits on focus loss commits only if `typed`, or text it was left showing lands on whatever it edits by then.
- An object literal as a property value needs parentheses: `payload: ({ … })`; `payload: { … }` is a code block.
- Assigning a bound property (`currentIndex = i`) breaks its binding: change the source it's bound to instead.
- A derived type must not redeclare a property its base declares (it shadows the base's, e.g. an alias).
- Never set `font.bold` on a StyledText (or anything derived from it): its role binds `font.weight`, which a base type applies after the instance's `font.bold` and so overwrites it. Set `font.weight` (an instance's own binding wins). `check_style.py` R13 fails it.
- Native text under a `scale` breaks (atlas bleed): declare `readonly property real contentZoom: scale` on the scaled item, so the text inside draws distance field while it is zoomed. `check_style.py` R18 fails a scale with no host.
- `Screen.devicePixelRatio` is the rounded-up integer under fractional scaling; use `item.Window.window.devicePixelRatio`.
- An elide needs a bound (`Layout.fillWidth` or a maximum width) in a `RowLayout`, else it never elides and pushes its siblings (`check_style.py` R15).
- `Text.WordWrap` never breaks a long token (a path, a URL); the roles use `Text.Wrap`. Set `overflow: "wrap"`, not `wrapMode`.
- `visible: visibleChildren.length > 0` locks itself hidden (children read invisible with their parent); use `children.length` or a flag.
- Under a hidden parent a child's `visible` changes emit nothing its Layout hears (`visibleChanged` follows the effective visibility), so the Layout keeps its old size: a parent shown only once that Layout has a size never shows (the OSD's icons' slot, now `enabled` and clipped instead). Never hide what holds a Layout by its size; read a child's own condition, not its `visible`, in a size (it reads false while hidden).
- A Repeater rebuilds its delegates before the host's own `on<Model>Changed` handler runs: state the delegates report to the host (a widest width, a count) and the handler then resets is lost, and nothing reports it again (the keybinds reference's key column once stayed 0 wide whenever its binds refreshed after the first build). Measure from the built delegates instead (`Repeater.itemAt` from `Qt.callLater`, on `itemAdded` / `itemRemoved` and each delegate's change: `KeybindSection._measureKeys`).
- A function-valued property (`labelOf: x => …`) works as a hook.
- An `on<Prop>Changed` handler runs during creation, before `onCompleted`, when a binding sets the property (a delegate's `widget: modelData`). A load done in both places runs twice, creating and destroying the first (BarWidgetHost, OverlaySlot). Guard the handler on a completed flag.
- A binding that builds new objects of equal content notifies every reader of it (ScreenEdgeManager.bars once reached every bar and widget on each pass). Keep the equal objects (a `KeptList`; the compare is `Utils.keepEqual`) or pass them through a string key and back (`_hiddenKey`).
- Bindings re-evaluate one at a time as a change spreads, so one reading two others that both follow the same source can briefly see one new and one stale (ScreenLayoutView's `placedModules` once paired new modules with the old `arrangement`'s places, and ModuleGrid warned every module overlapped). Derive the pair in one binding (`arrangement` carries the `modules` it arranged) and read only that.
- A Quickshell `Socket` on a listening Unix socket connects synchronously: `connectionStateChanged` fires before `connected: true` (or `createObject` of a component declaring it) returns. Store the socket wherever its handlers look for it before connecting it (`BackendManager._connect`), or the first signal is lost.
- A memoised function called from a binding must read every property its result depends on before the lookup (a hit that skips the reads drops the binding's dependencies); its cache is a JS object mutated in place, never a reassigned property (a binding loop when reassigned inside one). A colour read from a `color` property and handed to JS can be a reference to that property, which a cached result keeps and follows when the property changes (the memo then hands a later caller the new colour under the old key): copy it first (`Qt.rgba(c.r, c.g, c.b, c.a)`). A cache in a singleton's `var` property is arrays and plain objects: a `Map` or `WeakMap` there crashed Qt 6.12's GC (SIGSEGV in `Map.get` and in `MarkStack::drain`) within a few theme switches. `Style.shadowColor` and `BarColors.widgetColors` are the examples.

### Types and qmllint
- Signal parameters or properties typed `Item` that callers read custom members of trip qmllint (`missing-property`): type them `var`.
- qmllint doesn't see a singleton used only inside a template literal's `${…}`: its import is reported `unused-imports`. Concatenate instead (`"↓" + Utils.formatBytes(n)`).

### URL-loaded files
Bar widgets, content and views are loaded by URL.
- They see sibling types only because some loaded file imports their directory by name (`BarWidgetHost` → `qs.components.bar.widgets`, `BarPopouts`/`OverlaySlot` → `qs.components.content`, `OverlayPanel` → `qs.components.views`).
- A new directory imported only from URL-loaded files isn't scanned until qs restarts (`module "qs.…" is not installed`): ask the user to restart. New singletons are picked up by a hot reload (qs 0.3.1).
- An inline `component A` using another inline `component B` of the same file fails with "A is not a type": inline B's body.

### Canvas
- `onPaint` doesn't follow bindings: put every colour and value it reads in the repaint key (`paintKey`, `GridCanvas`), Style colours through `Style.revision`.

### Effects
- A `MultiEffect` handed a visible item's own layer (`layer.enabled` source) pads that layer and redraws the item shrunk and offset; handed a `ShaderEffectSource` with `autoPaddingEnabled`, it stretches it. Shadows of visible surfaces go through `OutsideShadow` (explicit padding).
- A scroll view holding FormRows sets `bleed: Style.rowBleed` with matching negative `Layout` margins, so a row's tint paints inside the clip instead of being cut.
- Rounded clipping is Quickshell.Widgets' `ClippingRectangle`, never a `MultiEffect` mask; set its `color`, which defaults to white.
- A `Shape.CurveRenderer` stroke gives a device pixel whose centre lies exactly on the stroke's edge full coverage, not half (at 1.25, a whole logical edge ≡ 2 mod 4). Draw a stroke that has to read evenly a 64th in on each edge (`Utils.tieInset`); fills are not affected.
- `ShapePath.strokeGradient` is Qt 6.12; Fedora 44/45 ship 6.11, where an unknown property fails the whole file. Gradient strokes go through `SliceMasked`; axiom supports Fedora's current Qt (6.11) and later, so use no newer API.
- A visibility or size that feeds back into the size a Layout gives a Text, decided from that Text's `truncated` (or a wrap/elide-dependent metric), can re-polish forever (Qt's polish guard is INT_MAX iterations; the shell freezes). Decide it from a hidden `Text` whose width is bound to the visible one (`ClampedText`).
- A binding that walks visual parents adds a guard per ancestor for every instance; stop it at a publisher (InkHost/TextRender stop rules) rather than at the root.
- A hover source must be an ancestor of the controls it should survive: a `HoverHandler` on a sibling painted under them loses the hover to any child that takes it, and one on a sibling over them takes it from them (Qt 6.12), so put it on the row, not beside the body.
- A `ScrollView`'s contentItem (its Flickable) clips at the view's padding, so anything drawn into the padding (a row's tint, a focus ring) is cut. `StyledScrollView.bleed` switches that clip off and clips the view itself; test with the nearest clipping ancestor (`tst_ScrollBleed`), not the view's rect.
- A property named `on<X>` in an object that has a property `<x>` (own or inherited) never takes its value: it reads the type's default (Qt 6.12: the style's onAccent colour read black for months, the battery service's onBattery was always false, a bar's onScreen never held; `check_structure.py` catches a clash in the file and with a few Qt names). Name it otherwise (`inkAccent.text`, `runningOnBattery`).
- A colour glide to or from `"transparent"` passes through black (a ColorAnimation lerps r, g, b and a apart, and `"transparent"` is #00000000): a deselected row flashes grey on a light theme. Rest on the fill at alpha 0 (`Qt.alpha(Style.accentContainer, 0)` with a `// style-exempt:` reason); `check_style.py` R20 fails the bare literal beside a glide.
