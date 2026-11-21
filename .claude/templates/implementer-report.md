# Implementer report

Used by: `.claude/agents/implementer.md`, the recipe skills, `.claude/skills/keep-order/SKILL.md` (gate, Fix round), `/orchestrate`.
Filled by: the implementer, when it finishes or stops. A brief adds to it and never drops a field.

```
Tree:
Files: one line each, what changed
Acceptance: A<n> PASS <command + output line> | FAIL <what> | NOT RUN <why>
Verify: the final line, verbatim
Log: each WARN/ERROR, from this tree, another tree (`axiom dev status`) or unknown
Names added: new_names.py --base <Base> --files <files> output; each name `spec` or `not in spec: <why>`; each `also defined` explained; or `none`
Reused: job → piece (path:line)
Changed pieces: each existing file or function edited, its users outside the change (grep count and paths), whether the ledger has a row
Docs: verify's doc list, each updated, or unchanged with why
Decided or skipped:
Stopped: why, and what is needed
```

- "By construction", "should" and untested claims count as NOT RUN.
- A PASS whose evidence exercises neither the user-visible path nor a changed piece's user is marked **weak**.
- On a committed tree, `nothing changed since HEAD` is not a pass.
- No diffs.
