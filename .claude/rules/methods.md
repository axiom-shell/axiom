---
paths:
  - "qml/components/methods/**"
  - "tests/tst_*.qml"
---

# Pure helpers (`qml/components/methods/`)

`pragma Singleton` `QtObject`s of pure functions: no files, processes, dispatches, timers or `qs.*` imports. `scripts/run_tests.sh` builds them as a `--pure` module tree, so anything importing Quickshell is left out of tests. Recipe: `/methods-helper`.

- **Every helper has a test**, `tests/tst_<Name>.qml` (`TestCase { name: "<Name>" }`, fixtures through `RepoFiles`); copy `ColorTemperature` + `tst_ColorTemperature`. A behaviour change adds a case; run `scripts/run_tests.sh <Name>`.
- Geometry helpers (`SurfaceContext`, `EdgeAttach`, `PopoutGeometry`, `BarEnds`, `GridPlacement`) are the single source of their decisions: a new case is a rule here plus a test row.
- JS engine gaps (`flatMap`, `Object.fromEntries`, `Intl`): `docs/dev/core/qml-pitfalls.md`.
- Config migrations aren't here: they're Go format-2 steps in `backend/internal/migrate/steps/`.
