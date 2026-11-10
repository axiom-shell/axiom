---
name: bar-popout
description: Add a popout panel that a bar widget opens on hover (qml/components/content/<Name>/<Name>.qml with a PopoutAnchor). Use when the user asks for a hover popout, a panel or dropdown from a bar widget, or details shown when hovering the bar.
argument-hint: "<the widget it opens from, what the popout shows and does>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

You don't see the conversation that asked for this: the task above is all you have. If it is empty, stop and say a task is needed.

1. Follow `docs/recipes/bar-popout.md`: read the files its Copy from names, do its Steps, and keep to its Watch out for.
2. Run its Check it steps, then `scripts/dev/verify.sh` until it prints `verify ok`.
3. Update what its Docs to update lists, where behaviour changed.

Stop and report instead of guessing when the task leaves a behaviour decision open (what it shows, a default, a name, which compositors) or the recipe doesn't cover the case: name the open question, so the lead can settle it with the architect.

Report: the files changed (one line each), the verify result, and anything you decided or skipped.
