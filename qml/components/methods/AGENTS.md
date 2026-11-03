# Pure helpers (`components/methods/`)

`pragma Singleton` `QtObject`s with pure functions: no files, processes, dispatches, timers or `qs.*` imports. `scripts/run_tests.sh` builds them as a `--pure` module tree, so anything importing Quickshell is left out of tests.

**Recipe:** `docs/recipes/methods-helper.md` / `docs/recipes/migration.md`; verify with `scripts/dev/verify.sh`.

- **Every helper has a test**: `tests/tst_<Name>.qml` (`import QtQuick; import QtTest; import qs.components.methods; TestCase { name: "<Name>"; function test_x() { compare(…) } }`). Copy `ColorTemperature.qml` + `tst_ColorTemperature.qml` or `TimeZones.qml` + `tst_TimeZones.qml`. Fixtures through `RepoFiles`.
- Add a test case whenever you change a helper's behaviour; run `scripts/run_tests.sh <Name>`.
- JS engine gaps: no `flatMap` (`[].concat(...arr.map(...))`), no `Object.fromEntries` (`reduce`), no `Intl`.
- Geometry rules (`SurfaceContext`, `EdgeAttach`, `PopoutGeometry`, `BarEnds`, `GridPlacement`) are the single source for their decisions: a new case is a rule here plus a test row, not a special case in a host. See `docs/dev/popouts/`.
- Config migrations aren't here: the axiom binary owns them (format-2 steps in `backend/internal/migrate/steps/`, [migration recipe](../../docs/recipes/migration.md)); the format-1 ones are its frozen `backend/internal/migrate/legacy/legacy.js`.
