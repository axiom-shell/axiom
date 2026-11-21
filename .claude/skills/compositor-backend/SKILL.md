---
name: compositor-backend
description: 'Add a compositor backend so axiom runs under another compositor (sway, niri, …): a qml/services/compositor/<Name>Manager.qml implementing the CompositorManager contract, its pure state parser and test. Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/compositor-backend`.'
argument-hint: "<compositor, what it supports, its IPC and config format>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/compositor-backend.md`. Follow `.claude/templates/brief.md` › Recipe skills.
