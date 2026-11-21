---
name: config-section
description: Add a new top-level config section to axiom's schema plus its reader singleton in qml/config/. Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/config-section`.
argument-hint: "<section name, the feature it configures, its keys with defaults>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/config-section.md`. Follow `.claude/templates/brief.md` › Recipe skills.
