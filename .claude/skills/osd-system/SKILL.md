---
name: osd-system
description: Add a new OSD system to axiom (a folder in qml/components/surfaces/osd/systems with its pure definition, its watcher, its schema.yaml and its timeline rows in tests/osd). Use when the user asks to show something new on the OSD, a new OSD status icon, tile, bar or card, or an OSD system.
argument-hint: "<system name, the event it shows, its parts (tile, bar, card), its settings>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

You don't see the conversation that asked for this: the task above is all you have. If it is empty, stop and say a task is needed.

1. Follow `docs/recipes/osd-system.md`: read the files its Copy from names, do its Steps, and keep to its Watch out for.
2. Run its Check it steps, then `scripts/dev/verify.sh` until it prints `verify ok`.
3. Update what its Docs to update lists, where behaviour changed.

Stop and report instead of guessing when the task leaves a behaviour decision open (what it shows, a default, a name, which compositors) or the recipe doesn't cover the case: name the open question, so the lead can settle it with the architect.

Report: the files changed (one line each), the verify result, and anything you decided or skipped.
