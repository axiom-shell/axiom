# Report

Filled by: the lead, as `report.md` in the state folder, at step 7; whoever opens the PR works from it.

```
# Ready for a PR: <slug> at <sha> (verify --all: all checks passed)
Branch: <branch> · Tier: T<n> · Review: <rounds>, last reviewed <sha>
PR: base <main | part below's branch> · title <subject>
Push: <branch>; after a stack rebase, lines 6–7 of `stacks.md` › The stack rebase rule, filled in
## What and why                  3–5 bullets: the problem, the fix, what users notice
## Live checks                    the LIVE: lines: what to try on the real host
## Not run, weak or inconclusive  each such acceptance check, with why
## Changed pieces                 piece: every user and the check that covered it
## Rulings                        each ruling and default taken, in plain technical terms: no R/D ids, step, plan or question ids, no plan quotes
## Questions                      word for word; or none
## Outside the branch             each item: filed to <file> | not filed: why
```

- One line per bullet; a section with nothing says `none`.
- An alignment request adds its census table, and its behaviour changes under What and why.
