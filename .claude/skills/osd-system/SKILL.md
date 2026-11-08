---
name: osd-system
description: Add a new OSD system to axiom (a folder in qml/components/surfaces/osd/systems with its pure definition, its watcher, its schema.yaml and its timeline rows in tests/osd). Use when the user asks to show something new on the OSD, a new OSD status icon, tile, bar or card, or an OSD system.
---

Read `docs/recipes/osd-system.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
