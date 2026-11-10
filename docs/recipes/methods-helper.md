# Adding a pure helper

A helper is a singleton in `qml/components/methods/` holding pure functions: geometry, parsing, formatting, layout maths, walking the schema. It has no files, processes, timers or services, so it can be unit-tested outside the shell. At the end you have the helper, a `TestCase` for it, and callers that import it. Anything with side effects belongs in a [service](service.md) instead.

**Copy from:** `qml/components/methods/ColorTemperature.qml` + `tests/tst_ColorTemperature.qml` (the smallest pair), `qml/components/methods/TimeZones.qml` + `tests/tst_TimeZones.qml`
**Background:** [shared UI pieces](../dev/core/shared-ui-pieces.md) › Pure helpers (check that no helper already does the job: `Utils`, `Search`, `GridPlacement`, `SurfaceContext`, …), `docs/dev/generated/files.md` (`grep` it for what a file does)

## Files
1. `qml/components/methods/<Name>.qml`: `pragma Singleton`, a `QtObject`, functions and readonly constants.
2. `tests/tst_<Name>.qml`: a `TestCase`.
3. The callers, which `import qs.components.methods`.

## Steps
1. Look for an existing helper first (shared UI pieces, `files.md`).
2. Write the helper. Import only `QtQuick`; other helpers of the folder need no import. Put a comment on every function saying what goes in and what comes out, and a purpose comment above the root object.
3. Write the test. `name` matches the helper, and there is one `test_*` function per behaviour, with a message on any `compare` whose point isn't obvious. Repo files such as the built schema come through `RepoFiles { id: files }` (`files.json("path")`, `files.text("path")`), which lives in `tests/`.
4. Run `scripts/run_tests.sh <Name>`.
5. Change the callers to use it.

## Watch out for
- **No Quickshell.** `run_tests.sh` builds a `--pure` module tree (`scripts/qml_modules.py --pure`) that leaves out every file importing Quickshell, so a helper importing it, or any `qs.services.*` or `qs.config`, silently disappears and its test fails to find it. Pass values in as arguments.
- **JS engine gaps:** no `Array.prototype.flatMap` (use `[].concat(...arr.map(...))`), no `Object.fromEntries` (use `reduce`), both refused by `check_structure`; no `Intl` (time zones go through `TimeZoneManager` and `TimeZones.shift`, dates through `I18n.formatDate`).
- **Don't mutate arguments.** Return new objects (`Utils.clone` makes deep copies).
- **Geometry decisions** (`SurfaceContext`, `EdgeAttach`, `PopoutGeometry`, `BarEnds`, `GridPlacement`) have one source for every host. A new case is a rule in the helper plus a test row, never a special case in a host. Read the answer from the helper's output instead of working it out again in the caller.
- A changed helper gets a test case for the change, even a small one.

## Check it
- `scripts/run_tests.sh <Name>`
- `scripts/dev/verify.sh`: formatting, structure, generated docs, and it runs the test of a changed helper.
- `python3 scripts/check_qmllint.py`

## Docs to update
- A line in [shared UI pieces](../dev/core/shared-ui-pieces.md) › Pure helpers if other features should reuse it.
- The doc of the feature whose mechanics it implements.
