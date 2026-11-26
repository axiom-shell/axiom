# Implementer report

Filled by: the implementer, when it finishes or stops.

```
Tree:
Files: one line each, what changed
Acceptance: A<n> PASS <command + output line> | FAIL <what> | NOT RUN <why>
Verify: the final line, verbatim
Log: each WARN/ERROR, from this tree, another tree (`axiom dev status`) or unknown
Names added: new_names.py --base <Base> --files <files> output; each name `spec` or `not in spec: <why>`; each `also defined` explained; or `none`
Reused: job → piece (path:line)
Removed: each symbol deleted or merged (path → where); `git -C <tree> add -A -N && git -C <tree> diff --shortstat HEAD` (a generated file's lines named, not counted); more lines added than deleted: why
Changed pieces: each existing file or function edited, its users outside the change (grep count and paths), whether the ledger has a row
Docs: verify's doc list, each updated, or unchanged with why
Decided or skipped:
Stopped: why, and what is needed
```

- "By construction", "should" and untested claims count as NOT RUN.
- A PASS whose evidence exercises neither the user-visible path nor a changed piece's user is marked **weak**.
- No diffs.
