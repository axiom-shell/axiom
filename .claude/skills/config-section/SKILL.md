---
name: config-section
description: Add a new top-level config section to axiom's schema plus its reader singleton in qml/config/. Use when the user says "new config section", "add a section for X settings", "new settings category for a feature", or a new feature needs its own settings.
argument-hint: "<section name, the feature it configures, its keys with defaults>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

You don't see the conversation that asked for this: the task above is all you have. If it is empty, stop and say a task is needed.

1. Follow `docs/recipes/config-section.md`: read the files its Copy from names, do its Steps, and keep to its Watch out for.
2. Run its Check it steps, then `scripts/dev/verify.sh` until it prints `verify ok`.
3. Update what its Docs to update lists, where behaviour changed.

Stop and report instead of guessing when the task leaves a behaviour decision open (what it shows, a default, a name, which compositors) or the recipe doesn't cover the case: name the open question, so the lead can settle it with the architect.

Report: the files changed (one line each), the verify result, and anything you decided or skipped.
