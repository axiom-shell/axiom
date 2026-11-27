---
name: service
description: Add a new axiom service singleton (qml/services/<group>/<Name>Manager.qml) that owns state and side effects, optionally polled through OwnerRegistry acquire/release and with an IPC handler. Run by `/orchestrate` for a group whose spec names this recipe, or when the user types `/service`.
argument-hint: "<Manager name and group, what it owns, polled or not, IPC target>"
context: fork
agent: implementer
---

Task: $ARGUMENTS

Recipe: `docs/recipes/service.md`. Follow `.claude/templates/brief.md` › Recipe skills.
