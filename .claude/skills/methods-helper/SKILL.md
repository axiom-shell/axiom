---
name: methods-helper
description: Add a pure helper singleton in axiom's qml/components/methods/ with its qmltestrunner test (tests/tst_<Name>.qml). Use when the user says "add a helper", "pure function for X", "extract this logic into methods", "unit-testable helper", or for geometry/parsing/formatting logic with no side effects.
---

Read `docs/recipes/methods-helper.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
