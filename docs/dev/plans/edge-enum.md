# `Bar` reader holds the edges enum and breaks reader naming

> **Issue:** [`Bar` reader holds the edges enum and breaks reader naming](../issues.md#bar-reader-holds-the-edges-enum-and-breaks-reader-naming)
> **Status:** proposed

### Problem
`config/Bar.qml` does two jobs. It is the `Bars` section's reader (`enrichBarConfig`, the look helpers, `savedBars`, `expandBars`, the schema groups), named `Bar` where every other reader is named for its section (`EdgeMenusConfig`, `PopoutsConfig`, …). And it declares `enum Location { Top, Bottom, Left, Right }` plus four edge helpers (`edgeName`, `locationOf`, `oppositeOf`, `getLocationFromString`) that docks, OSDs, the launcher, popouts, edge menus and the border use, none of which is about bars.

Counted on main (cd4e0ff), occurrences in `*.qml`:
- 278 `Bar.` references in 64 files.
- The enum: 160 values (`Bar.Right` 45, `Bar.Top` 40, `Bar.Left` 39, `Bar.Bottom` 36), plus 24 `Bar.Location(s)`, all in comments ("a Bar.Location"). The edge helpers: 38 (`edgeName` 28, `getLocationFromString` 5, `locationOf` 3, `oppositeOf` 2). Together in 32 files, 12 of them in `components/hosts/popout/`, 25 in `services/ui/ScreenEdgeManager.qml`.
- The reader proper: about 80 references (`cellColors` 9, `lookOf` 8, `enrichBarConfig` 8, …).

Further evidence:
- `components/methods/` may not import `qs.*`, so `SurfaceOutline` keeps its own copy of the enum (`readonly property int top: 0` … `right: 3`) and its doc says "`edge` is a Bar.Location number". The edge numbers are a contract kept in two places.
- Quickshell exports its own `Edges` (flags: `Top`, `Left`, `Right`, `Bottom`, other values). `components/surfaces/dock/DockMenu.qml` already mixes the two in one line (`_edge === Bar.Bottom ? Edges.Top : …`). A singular `Edge.Top` next to it is one letter from a different number that qmllint accepts.
- `shell/Bar.qml` is also a type named `Bar`. Today no file imports both `qs.shell` and `qs.config` (only `shell.qml` and `greeter.qml` import `qs.shell`), but the rule "no file may see both" holds only by luck.
- `scripts/check_docs.py`'s `RETIRED` matches a span's first word. `Bar` is also the schema definition docs cite (`Bar.background`, `Bar.floatGap`, `Bar.pillMerge`, `` `Bar` `` in bar/composition.md), so `"Bar": …` in `RETIRED` as the issue suggests would fail on those correct spans. The member check doesn't help either: once no singleton is named `Bar`, a stale `Bar.enrichBarConfig` in a doc passes without a word.

QML enum rules, checked with qmltestrunner on Qt 6.12 (a scratch module, not guessed): an enum declared in a QML file works as `Type.Value` whether the file is a singleton or a plain type, also from inside that file (`[Edge.Bottom, …][l]`). `Type.Location` is an object and `Type.Location.Right` works too. A misspelled value is `undefined` at runtime without a warning, and qmllint flags it (`Member "Nope" not found [missing-property]`), so the enum keeps its compile-time check wherever it lives. The values are ints, and the code indexes arrays by them (`["top", "bottom", "left", "right"][location]`): the order `Top, Bottom, Left, Right` must not change. Under `qs` the singleton form is proven (`Bar.Top` today), the plain-type form isn't, so a singleton is the safe shape.

### Options
#### A. A config/ singleton (the issue's plan)
A new config/Edge.qml with the enum and the four helpers, then the reader renamed. Readers, services and UI can use it. Costs: `components/methods/` still can't, so `SurfaceOutline`'s copy stays and methods keep passing bare numbers. It's not a reader (it reads no config), so it sits in config/ only because the enum used to.

#### B. A pure helper in components/methods/ (recommended)
`components/methods/` gets an edge singleton with the enum and the helpers, which are pure (array lookups). Every layer can import methods: readers (`EdgeMenusConfig`, `LauncherConfig`), services, UI and other methods. `SurfaceOutline` drops its copy. The helpers get a `tests/tst_<Name>.qml` (the order contract, name round trip, opposite, the fallback to Top for an unknown name). Costs: the same 32-file sweep as A, plus a test. It leaves out nothing A covers.

#### C. Put it with ScreenEdgeManager (services/ui/)
The enum on the service that owns screen-edge geometry. This breaks the layering: config readers (`Bar`, `EdgeMenusConfig`, `LauncherConfig`) would import a service, and methods still couldn't use it. ScreenEdgeManager uses the edge numbers, it doesn't define what an edge is. Rejected.

#### The reader's new name
- `BarsConfig`: named for its section with the suffix, like `EdgeMenusConfig` and `PopoutsConfig`. It can't be read as the `Bars` config path (`check_docs` treats `Bars.items` as a setting) or as `shell/Bar`. Recommended.
- `Bars`: shorter, but docs and AGENTS.md already use `Bars` for the config array, and `Bars.savedBars` next to `Bars.items` makes it unclear which is the reader and which is the setting.

`config/BarStyle.qml` (the `Bars.style` reader) stays as it is: merging it in is a separate question.

### Recommendation
B with `BarsConfig`. The edge numbers are a pure contract that methods need too, so they belong in methods/, and one copy replaces two. For the singleton's name, `ScreenEdge` (`ScreenEdge.Top`) rather than the issue's `Edge`: it reads like `ScreenEdgeManager`, and it can't be confused with Quickshell's `Edges.Top`, whose values differ and which `DockMenu` uses in the same expression. `Edge` is the shorter choice if the maintainer prefers it. Moving the enum first, then renaming the reader, keeps each diff to one kind of change.

### Items
Each one commit, in this order, one PR (a batch). Force a reload after each (testing.md › Reloads and logs).

1. **Add `methods/ScreenEdge` with its test.** The enum (`Top, Bottom, Left, Right`, same order) and `name(edge)` (was `edgeName`), `fromName(name)` (was `locationOf`, -1 if unknown), `fromConfig(name)` (was `getLocationFromString`, Top if unknown), `opposite(edge)` (was `oppositeOf`). Its test, tests/tst_ScreenEdge.qml. `SurfaceOutline` uses it instead of its own ints. `Bar.qml` is untouched.
2. **Move every enum and edge-helper user to `ScreenEdge`.** `Bar.Top` … → `ScreenEdge.Top` …, `Bar.edgeName` → `ScreenEdge.name` and so on, in the 32 files and the comments ("a Bar.Location" → "a ScreenEdge"). Delete the enum and the four helpers from `config/Bar.qml`. Docs: config-readers.md's `edgeName` line, and the `Bar.Top` / `Bar.Left` / `Bar.Location` / `edge === Bar.Right` spans. Run qmllint, which catches a missed value.
3. **Rename the reader `Bar` → `BarsConfig`.** `git mv config/Bar.qml config/BarsConfig.qml` and its about 80 references, then the docs (`Bar.enrichBarConfig`, `Bar.lookOf`, …; config-readers.md's entry). In `scripts/check_docs.py`, make a retired name that is also a schema definition fail only when a span names a member that isn't a config path (so `Bar.background` still passes and `Bar.enrichBarConfig` fails), and add `"Bar": "BarsConfig"` that way. A test case for that check goes in `tests/scripts/`. Remove the issues.md entry and its roadmap link.
