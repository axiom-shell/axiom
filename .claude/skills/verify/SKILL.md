---
name: verify
description: Check a change to axiom the way CI will and see what the live shell logged. Use after editing QML, the schema or scripts, before saying a change is done, or when asked to "verify", "check my changes", "run the checks", "does it work", "take a screenshot of …".
argument-hint: "[--all] [files changed] [shot <page ViewType | launcher [text] | ipc target open [close]>]"
context: fork
agent: checker
---

Request: $ARGUMENTS

1. Run `scripts/dev/verify.sh`, or `scripts/dev/verify.sh --all` (every CI check) if the request says `--all`.
2. If the request names changed files, look in the shell log section verify.sh prints for new `WARN`/`ERROR` lines from those files.
3. If the request asks for `shot …`, run `scripts/dev/shot.sh` with what follows it (`page <ViewType>`, `launcher [text]`, `ipc <target> <open> [close]`) and give the PNG path it prints: the caller reads the image. Never move the cursor.

Report in your usual format (result, each failure exactly as printed, new log lines), plus the PNG path if you took one. Fix nothing.
