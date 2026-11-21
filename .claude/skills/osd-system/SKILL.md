---
name: osd-system
description: Add a new OSD system to axiom (a folder in qml/components/surfaces/osd/systems with its pure definition, its watcher, its schema.yaml and its timeline rows in tests/osd). Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/osd-system`.
argument-hint: "<system name, the event it shows, its parts (tile, bar, card), its settings>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/osd-system.md`. Follow `.claude/templates/brief.md` › Recipe skills.
