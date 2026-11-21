---
name: bar-widget
description: Add a new bar widget type to axiom (a QML file in qml/components/bar/widgets plus its schema entry). Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/bar-widget`.
argument-hint: "<widget type name, what it shows, what clicking does, its settings>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/bar-widget.md`. Follow `.claude/templates/brief.md` › Recipe skills.
