---
name: overlay-module
description: 'Add a new overlay module (a card type for overlay pages and menus: qml/components/content/<Type>/<Type>.qml plus its schema entry). Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/overlay-module`.'
argument-hint: "<module type, what it shows and does, sizes, hosts>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/overlay-module.md`. Follow `.claude/templates/brief.md` › Recipe skills.
