# Adding a pure helper

A helper is a singleton in `qml/components/methods/` holding pure functions: geometry, parsing, formatting, layout maths, walking the schema. It follows the purity list in `.claude/rules/methods.md`, which `check_engines` › `purity` checks (no files, processes, timers or services), so it can be unit-tested outside the shell. At the end you have the helper, a `TestCase` for it, and callers that import it. Anything with side effects belongs in a [service](service.md) instead.

**Copy from:** `qml/components/methods/ColorTemperature.qml` + `tests/tst_ColorTemperature.qml` (the smallest pair), `qml/components/methods/TimeZones.qml` + `tests/tst_TimeZones.qml`
**Background:** [shared UI pieces](../dev/core/shared-ui-pieces.md) › Pure helpers (check that no helper already does the job: `Utils`, `Search`, `GridPlacement`, `SurfaceContext`, …), `docs/dev/generated/files.md` (`grep` it for what a file does)

## Files
1. `qml/components/methods/<domain>/<Name>.qml` (the root only for a generic helper): `pragma Singleton`, a `QtObject`, functions and readonly constants.
2. `tests/tst_<Name>.qml`: a `TestCase`.
3. The callers, which `import qs.components.methods`.

## Steps
1. Is the helper inside an engine's `folder` or `files` (`scripts/engines.json`)? Then it's an engine edit: `/engine-change`.
2. Which domain owns it? A helper of one domain goes in `qml/components/methods/<domain>/` with its `$domains` entry in `scripts/engines.json` (`uses`, `tables`, `prefix` for rows), added when the folder is new; only a generic helper two or more domains use goes in the root.
3. Look for an existing helper first (shared UI pieces, `files.md`).
4. Write the helper. Import only `QtQuick`; other helpers of the folder need no import. Put a comment on every function saying what goes in and what comes out, and a purpose comment above the root object.
5. Write the test. `name` matches the helper, and there is one `test_*` function per behaviour, with a message on any `compare` whose point isn't obvious. Repo files such as the built schema come through `RepoFiles { id: files }` (`files.json("path")`, `files.text("path")`), which lives in `tests/`.
6. Run `scripts/run_tests.sh <Name>`.
7. Change the callers to use it.

## Watch out for
- **No Quickshell.** `run_tests.sh` builds a `--pure` module tree (`scripts/qml_modules.py --pure`) that leaves out every file importing Quickshell, so a helper importing it is left out and its test fails at import. A helper importing anything outside that list (`qs.services.*`, `qs.config`) fails `check_engines` › `purity`. Pass values in as arguments.
- **JS engine gaps:** no `Array.prototype.flatMap` (use `[].concat(...arr.map(...))`), no `Object.fromEntries` (use `reduce`), both refused by `check_structure`; no `Intl` (time zones go through `TimeZoneManager` and `TimeZones.shift`, dates through `I18n.formatDate`).
- **Don't mutate arguments.** Return new objects (`Utils.clone` makes deep copies).
- **Geometry decisions** (`SurfaceContext`, `EdgeAttach`, `PopoutGeometry`, `BarEnds`, `GridPlacement`) have one source for every host. A new case is a rule in the helper plus a test row, never a special case in a host. Read the answer from the helper's output instead of working it out again in the caller.
- A domain helper's rows are `tests/<domain>/<Name>.js` and run through `tests/tst_<Name>.qml`.
- A changed helper gets a test case for the change, even a small one.

## Check it
- `scripts/run_tests.sh <Name>`
- `scripts/dev/verify.sh`: formatting, structure, generated docs, and it runs the test of a changed helper.
- `python3 scripts/check_qmllint.py`

## Docs to update
- A line in [shared UI pieces](../dev/core/shared-ui-pieces.md) › Pure helpers if other features should reuse it.
- The doc of the feature whose mechanics it implements.
