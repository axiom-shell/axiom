---
name: methods-helper
description: Add a pure helper singleton in axiom's qml/components/methods/ with its qmltestrunner test (tests/tst_<Name>.qml). Use when the user says "add a helper", "pure function for X", "extract this logic into methods", "unit-testable helper", or for geometry/parsing/formatting logic with no side effects.
argument-hint: "<helper name, the functions with inputs and outputs, the cases to test>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

You don't see the conversation that asked for this: the task above is all you have. If it is empty, stop and say a task is needed.

1. Follow `docs/recipes/methods-helper.md`: read the files its Copy from names, do its Steps, and keep to its Watch out for.
2. Run its Check it steps, then `scripts/dev/verify.sh` until it prints `verify ok`.
3. Update what its Docs to update lists, where behaviour changed.

Stop and report instead of guessing when the task leaves a behaviour decision open (what it shows, a default, a name, which compositors) or the recipe doesn't cover the case: name the open question, so the lead can settle it with the architect.

Report: the files changed (one line each), the verify result, and anything you decided or skipped.
