---
name: overlay-view
description: Add a new overlay page type or tool page (qml/components/views/<Type>/<Type>.qml plus schema, and for tool pages the default, a migration step, a launcher command and docs). Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/overlay-view`.
argument-hint: "<page type, what it shows, whether it is a tool page>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/overlay-view.md`. Follow `.claude/templates/brief.md` › Recipe skills. An editor tool page also follows `docs/recipes/tool-page.md`.
