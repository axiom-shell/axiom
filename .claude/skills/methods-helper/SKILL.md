---
name: methods-helper
description: Add a pure helper singleton in axiom's qml/components/methods/ with its qmltestrunner test (tests/tst_<Name>.qml). Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/methods-helper`.
argument-hint: "<helper name, the functions with inputs and outputs, the cases to test>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/methods-helper.md`. Follow `.claude/templates/brief.md` › Recipe skills.
