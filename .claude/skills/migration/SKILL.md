---
name: migration
description: Write an axiom config migration step (a format-2 step in backend/internal/migrate/steps, version bump, Go test) for renaming, moving or reshaping config keys. Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/migration`.
argument-hint: "<old key or shape → new one, the version it lands in>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/migration.md`. Follow `.claude/templates/brief.md` › Recipe skills.
