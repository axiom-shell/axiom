# Recipe: a pure helper in `components/methods/` (with its test)

> **Use when:** logic that can be a pure function: geometry, parsing, formatting, layout maths, schema walking. Anything with files, processes, timers or dispatches is a [service](service.md).
> **Copy from:** `components/methods/ColorTemperature.qml` + `tests/tst_ColorTemperature.qml` (smallest), `components/methods/TimeZones.qml` + `tests/tst_TimeZones.qml`
> **Docs:** `components/methods/AGENTS.md`, [shared-ui-pieces](../dev/core/shared-ui-pieces.md) (check an existing helper doesn't already do it: `Utils`, `Search`, `GridPlacement`, `SurfaceContext`, …)

## Files to touch
1. `components/methods/<Name>.qml`: `pragma Singleton` `QtObject` with functions (and readonly constants).
2. `tests/tst_<Name>.qml`: a `TestCase`.
3. The callers (`import qs.components.methods`).

## Skeleton
```qml
pragma Singleton
import QtQuick

// What it computes and for whom. No file access, processes or services.
QtObject {
  id: root

  // { r, g, b } in 0-255 for `kelvin` (clamped to 1000-40000)
  function rgb(kelvin) {
    const t = Math.max(1000, Math.min(40000, kelvin)) / 100;
    …
    return {
      "r": r,
      "g": g,
      "b": b
    };
  }
}
```
```qml
import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ColorTemperature"

  function test_rgb() {
    compare(ColorTemperature.rgb(6600), {
      "r": 255,
      "g": 255,
      "b": 255
    }, "daylight is white");
  }
}
```

## Steps
1. Check `docs/dev/core/shared-ui-pieces.md` (Pure helpers) and `docs/dev/generated/files.md` for an existing helper first.
2. Write the helper. Imports are `QtQuick` only (plus other `qs.components.methods` helpers). Every function gets a comment with its inputs and outputs.
3. Write the test. `name` matches the file, and there's one `test_*` per behaviour, with a message on the non-obvious `compare`s. Fixtures from the repo come through `RepoFiles { id: files }` (`files.json("path")`, `files.text("path")`), which lives in `tests/`.
4. Run `scripts/run_tests.sh <Name>`.

## Gotchas
- **No Quickshell:** `run_tests.sh` builds a `--pure` module tree, so a helper importing Quickshell or any `qs.services.*` / `qs.config` module is silently left out and its test fails to find it. Pass the values in as arguments instead.
- **JS engine gaps:** no `Array.prototype.flatMap` (use `[].concat(...arr.map(...))`), no `Object.fromEntries` (use `reduce`), no `Intl` (time zones go through `TimeZoneManager` + `TimeZones.shift`).
- **Don't mutate arguments.** Return new objects (`Utils.clone` for deep copies).
- **Geometry decisions** (`SurfaceContext`, `EdgeAttach`, `PopoutGeometry`, `BarEnds`, `GridPlacement`) are the single source for every host. A new case is a rule plus a test row, never a special case in a host.
- **Generated Lua:** a test writing Lua to `tests/.out/` gets it checked with `luac -p` (`*.run.lua` also run, `*.hypr.lua` read by `Hyprland --verify-config` where it's installed). See `tst_HyprLua`.

## Verify
- `scripts/run_tests.sh <Name>`
- `scripts/dev/verify.sh` (formatting, structure, generated docs)
- `python3 scripts/check_qmllint.py`

## Docs to update
- A line in [shared-ui-pieces](../dev/core/shared-ui-pieces.md) if other features should reuse it.
- The feature doc whose mechanics it implements.
