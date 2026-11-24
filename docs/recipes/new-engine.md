# Adding an engine

A new engine is a cross-system change: run it under `/orchestrate` with an architect. This recipe is the order of its pieces. At the end you have the facade with its stages, the rules tables, the rows that pin them, the owner and adapter that call it, the manifest entry and the side doc. Editing an existing engine is [engine-change](engine-change.md).

**Copy from:** [engines](../dev/core/engines.md) › The facade (the facade), › The runner (the test file), `tests/tst_EngineRows.qml` (row wiring), `backend/internal/idle/plan.go` (`SettingsFrom` `:41` → `Plan` `:121`, the Go shape of a pure plan)
**Background:** [engines](../dev/core/engines.md) › What an engine is, › Stages, › The manifest, › The side doc

## Files
1. `qml/components/methods/<engine>/`: the facade `<Name>Engine.qml` and the internal files.
2. The manifest entry in `scripts/engines.json`, added in the change that creates the facade.
3. The feeder in the owner (with its `// reads:` line).
4. The owner (`KeptList` for lists, one `_prev`).
5. The adapter.
6. `tests/<engine>/Rows.js`.
7. `tests/<engine>/Fixtures.js`.
8. `tests/tst_<Facade>.qml`, through `EngineRows`.
9. The side doc.

## Steps
1. Write the facade: `api` first, then `tuning`, the stages in order, the extras; each stage function in the one form `check_engines` › `shape` reads.
2. Write the internal files, opening with their tables; each rules table is listed in `tables` with its kind.
3. Write the rows (`Rows.js`, `Fixtures.js`) and the test file (`tst_<Facade>.qml`).
4. Add the manifest entry.
5. Write the feeder and the owner, then the adapter.
6. Write the side doc with its eleven headings.
7. Run `scripts/run_tests.sh <Facade>`, `python3 scripts/check_engines.py` and `scripts/dev/verify.sh`.

## Watch out for
- A stage is called only from the files its role allows: `model` and `reduce` from owners, `solve` from owners and adapters, `drawn` from adapters.
- The engine is listed only when its facade exists.
- A rule id is never renamed or reused.

## Check it
- `scripts/run_tests.sh <Facade>`
- `python3 scripts/check_engines.py`
- `scripts/dev/verify.sh`

## Docs to update
- The side doc, and the Seam register in [engines](../dev/core/engines.md) for each seam the engine has.
