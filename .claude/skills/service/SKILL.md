---
name: service
description: Add a new axiom service singleton (qml/services/<group>/<Name>Manager.qml) that owns state and side effects, optionally polled through ConsumerRegistry acquire/release and with an IPC handler. Use when the user says "new service", "new manager", "poll X", "run a command periodically", "add an IPC target", or a feature needs a command, file writes or a daemon call.
argument-hint: "<Manager name and group, what it owns, polled or not, IPC target>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

You don't see the conversation that asked for this: the task above is all you have. If it is empty, stop and say a task is needed.

1. Follow `docs/recipes/service.md`: read the files its Copy from names, do its Steps, and keep to its Watch out for.
2. Run its Check it steps, then `scripts/dev/verify.sh` until it prints `verify ok`.
3. Update what its Docs to update lists, where behaviour changed.

Stop and report instead of guessing when the task leaves a behaviour decision open (what it shows, a default, a name, which compositors) or the recipe doesn't cover the case: name the open question, so the lead can settle it with the architect.

Report: the files changed (one line each), the verify result, and anything you decided or skipped.
