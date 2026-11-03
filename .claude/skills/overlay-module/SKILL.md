---
name: overlay-module
description: Add a new overlay module (a card type for overlay pages and edge menus: qml/components/content/<Type>/<Type>.qml plus its schema entry). Use when the user asks for a new module, card, tile or widget for the overlay, an edge menu, the desktop or the lock screen.
---

Read `docs/recipes/overlay-module.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
