---
name: compositor-backend
description: Add a compositor backend so axiom runs under another compositor (sway, niri, …): a services/compositor/<Name>Manager.qml implementing the CompositorManager contract, its pure state parser and test. Use when the user says "support sway", "niri backend", "run under another compositor", or "port to <compositor>".
---

Read `docs/recipes/compositor-backend.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
