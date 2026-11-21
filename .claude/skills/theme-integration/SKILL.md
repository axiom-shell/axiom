---
name: theme-integration
description: Add a new axiom theme integration that themes another app (an entry in the Go integrations table, its template, ThemeIntegrations schema switch with x-hookup, reader property, goldens). Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/theme-integration`.
argument-hint: "<app, its config file and colour format, how it reloads>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/theme-integration.md`. Follow `.claude/templates/brief.md` › Recipe skills.
