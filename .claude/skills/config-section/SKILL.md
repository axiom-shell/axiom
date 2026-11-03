---
name: config-section
description: Add a new top-level config section to axiom's schema plus its reader singleton in qml/config/. Use when the user says "new config section", "add a section for X settings", "new settings category for a feature", or a new feature needs its own settings.
---

Read `docs/recipes/config-section.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
