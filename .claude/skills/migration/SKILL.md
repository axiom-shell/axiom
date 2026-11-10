---
name: migration
description: Write an axiom config migration step (a format-2 step in backend/internal/migrate/steps, version bump, Go test) for renaming, moving or reshaping config keys. Use when the user says "rename a config key", "move setting X", "change the config layout", "migrate old configs", or "bump the config version".
argument-hint: "<old key or shape → new one, the version it lands in>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

You don't see the conversation that asked for this: the task above is all you have. If it is empty, stop and say a task is needed.

1. Follow `docs/recipes/migration.md`: read the files its Copy from names, do its Steps, and keep to its Watch out for.
2. Run its Check it steps, then `scripts/dev/verify.sh` until it prints `verify ok`.
3. Update what its Docs to update lists, where behaviour changed.

Stop and report instead of guessing when the task leaves a behaviour decision open (what it shows, a default, a name, which compositors) or the recipe doesn't cover the case: name the open question, so the lead can settle it with the architect.

Report: the files changed (one line each), the verify result, and anything you decided or skipped.
