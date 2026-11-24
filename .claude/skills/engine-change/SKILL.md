---
name: engine-change
description: Edit an engine listed in scripts/engines.json (a case, rule, input, output, consumer, adapter or drawing item, tuning value, enum value, file split, kit, rule removal). Refuses a seam change, a new intake rule, moving a stage run to another owner, moving a rule between engines and a new stage or extra, which go to `/orchestrate` with an architect. Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/engine-change`.
argument-hint: "<engine, the edit and its kind>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/engine-change.md`. Follow `.claude/templates/brief.md` › Recipe skills.
