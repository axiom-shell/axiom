---
name: service
description: Add a new axiom service singleton (services/<group>/<Name>Manager.qml) that owns state and side effects, optionally polled through ConsumerRegistry acquire/release and with an IPC handler. Use when the user says "new service", "new manager", "poll X", "run a command periodically", "add an IPC target", or a feature needs a process, file writes or Hyprland calls.
---

Read `docs/recipes/service.md` and follow it exactly: it names the files to touch, the files to copy from, the traps (Gotchas) and how to verify.
Finish when its Verify steps pass and `scripts/dev/verify.sh` prints `verify ok`.
