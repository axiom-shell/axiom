---
name: setting
description: Add a new config setting (key) to an existing axiom config section, with its schema entry, default and reader property. Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/setting`.
argument-hint: "<section, key, type, default, what it changes, scope>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/setting.md`. Follow `.claude/templates/brief.md` › Recipe skills.
