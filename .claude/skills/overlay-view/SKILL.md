---
name: overlay-view
description: Add a new overlay page type or tool page (qml/components/views/<Type>/<Type>.qml plus schema, and for tool pages the default, a migration step, a launcher command and docs). Use when the user asks for a new overlay page, view, tool page or editor page.
---

Read `docs/recipes/overlay-view.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
