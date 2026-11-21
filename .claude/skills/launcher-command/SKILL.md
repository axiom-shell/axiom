---
name: launcher-command
description: Add a slash command to the launcher (an entry in qml/services/ui/LauncherCommands.qml). Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/launcher-command`.
argument-hint: "<command name, what it does, its arguments>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/launcher-command.md`. Follow `.claude/templates/brief.md` › Recipe skills.
