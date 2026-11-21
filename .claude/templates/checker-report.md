# Checker report

Used by: `.claude/agents/checker.md`, `.claude/skills/verify/SKILL.md`, `.claude/skills/review-branch/SKILL.md`, `.claude/skills/keep-order/SKILL.md` (Fix round).
Filled by: the checker, after running what it was asked.

```
Tree:
Result: ok | failed: <steps> | NOT RUN: <why>
Failures: each with its step, file:line and the error lines, verbatim
Log: new WARN/ERROR lines from the caller's files
With --all: the last line, verbatim
```

- `nothing changed since HEAD` is `NOT RUN`, never `ok`; committed code is checked with `--all`.
- Trim passing output and repeated lines. Nothing else.
