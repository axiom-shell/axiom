# Editing an engine

An engine is a facade, its internal files and its rules tables under `qml/components/methods/`, listed in `scripts/engines.json`. Every edit to one is a kind in [engines](../dev/core/engines.md) › Editing an engine, with one edit point, a contract row written first and a side-doc section to update. At the end you have the edit at its edit point, the row that pins it, and a side doc that still describes the engine as it is. A new engine, a seam change and the other kinds routed to `/orchestrate` are not this recipe.

**Copy from:** the engine's own files: its rows file (`tests.rows` in its manifest entry) for a row, its rules table for a table row.
**Background:** [engines](../dev/core/engines.md) › Editing an engine, › Readability, › The row format

## Files
1. The edit point the kind names (the rules table, the stage's internal file, the facade's `api` or `tuning`, the feeder, the host).
2. The engine's rows file (`tests.rows`), the contract row for the edit.
3. The side doc (the manifest `doc`), the section the kind names.

## Steps
1. Find the kind in [engines](../dev/core/engines.md) › Editing an engine. A kind whose route there isn't `/engine-change` stops here: report its route and change nothing. The five `/orchestrate` kinds (seam change, new intake rule, moving a stage run to another owner, moving a rule between engines, new stage or extra) go to `/orchestrate` with an architect; a plug-in goes to its kind's recipe, a helper to `/methods-helper`, an exception to an architect.
2. Find the edit point on the engine's section of `docs/dev/generated/engine-manifest.md` › Edit points (built from its manifest entry's `editPoints`), then in its `scripts/engines.json` entry: `tables`, `feeder`, `adapters`, `itemPaths`. A rules table's rows are on its page under `docs/dev/generated/rules/`.
3. For an edit that adds a case, a rule or an output, write its contract row first, in the engine's `tests.rows` file, with a new id (`<prefix>-<nn>`, never a removed one's) whose `expect` names the rule id it pins. A rule removal removes the rule's rows instead; the other kinds add no row.
4. Make the edit at the one edit point. A cell case is one row per new cell, and a new axis value goes in `axes` with its rows. A file split moves whole functions, by stage or by rule family, into a file the entry holds (under its `folder`, or added to its `files`).
5. Run `scripts/run_tests.sh <Facade>` and `python3 scripts/check_engines.py`.
6. Update the side-doc sections › Editing an engine names for the kind (none for a case or an enum value).

## Watch out for
- A rule id is never renamed: add a new one and remove the old with its rows.
- A removed rule removes its rows in the same change.
- Exactly one table row per cell: `check_engines` › `tables` fails an uncovered cell and a cell with two rows.
- A number in a decision is a `tuning` field or a table cell, never a literal in a function.
- The pages under `docs/dev/generated/` are built by `scripts/generate.sh` from the manifest and the engine's files: edit the source, never a page.

## Check it
- `scripts/run_tests.sh <Facade>`
- `python3 scripts/check_engines.py`
- `scripts/dev/verify.sh`

## Docs to update
- The side doc's sections per [engines](../dev/core/engines.md) › Editing an engine.
