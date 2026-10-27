---
name: theme-integration
description: Add a new axiom theme integration that themes another app (an entry in the Go integrations table, its template, ThemeIntegrations schema switch with x-hookup, reader property, goldens). Use when the user says "theme X too", "add a theme integration for X", "make X follow the axiom theme", or "support X colors".
---

Read `docs/recipes/theme-integration.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
