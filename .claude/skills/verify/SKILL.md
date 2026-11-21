---
name: verify
description: Check a change to axiom the way CI will and see what the live shell logged. Use after editing QML, the schema or scripts, before saying a change is done, or when asked to "verify", "check my changes", "run the checks", "does it work", "take a screenshot of …".
argument-hint: "[--tree <path>] [--all] [files changed] [shot <page ViewType | launcher [text] | ipc target open [close]>]"
context: fork
agent: checker
---

Request: $ARGUMENTS

`--tree <path>` is where every command runs (default: `git rev-parse --show-toplevel`); every command is `cd <tree> &&`.

1. Run `scripts/dev/verify.sh`, or `scripts/dev/verify.sh --all` (every CI check) if the request says `--all`.
2. If the request names changed files, look in the shell log section verify.sh prints for new `WARN`/`ERROR` lines from those files.
3. If the request asks for `shot …`: `shot` shoots the live display, which runs the install or dev tree (`axiom dev status`), never a worktree. From a worktree, report `NOT RUN: shot shows another tree` and a `LIVE:` line. Otherwise run `scripts/dev/shot.sh` with what follows it (`page <ViewType>`, `launcher [text]`, `ipc <target> <open> [close]`) and give the PNG path it prints: the caller reads the image. Never move the cursor.

Report in `.claude/templates/checker-report.md`, plus the PNG path if you took one. Fix nothing.
