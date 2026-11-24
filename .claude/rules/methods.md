---
paths:
  - "qml/components/methods/**"
  - "tests/tst_*.qml"
---

# Pure helpers (`qml/components/methods/`)

`pragma Singleton` `QtObject`s of pure functions: no files, processes, timers, clocks, randomness, logging, deferral or Quickshell; imports only `QtQuick`, `qs.components.methods` and the engine or domain folders its manifest entry `uses` (`check_engines` › `purity`). `scripts/run_tests.sh` builds them as a `--pure` module tree, so anything importing Quickshell is left out of tests. Recipe: `/methods-helper`.

- **Every helper has a test**, `tests/tst_<Name>.qml` (`TestCase { name: "<Name>" }`, fixtures through `RepoFiles`); copy `ColorTemperature` + `tst_ColorTemperature`. A behaviour change adds a case; run `scripts/run_tests.sh <Name>`.
- Engines (`scripts/engines.json`) are entered through their facade; a new case is a rules row plus a contract row (`docs/dev/core/engines.md`); a helper's new case is a rule in its file plus a test row.
- JS engine gaps (`flatMap`, `Object.fromEntries`, `Intl`): `docs/dev/core/qml-pitfalls.md`.
- Config migrations aren't here: they're Go format-2 steps in `backend/internal/migrate/steps/`.
