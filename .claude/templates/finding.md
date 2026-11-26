# Finding

Filled by: a reviewer, most severe first. The architect uses § Plan check for a plan.

```
- [Blocker|Major|Cleanup|Minor] `path:line` (`symbol`): the defect in one sentence
  **Case:** the input or state, and what happens instead of what should (quoted code, a grep count, a doc line; "PLAUSIBLE: <what settles it>" when it applies)
  **Fix:** the smallest change (code when short; for a deletion, the lines it removes)
```

Then `Outside the slice:` problems seen that the change didn't cause (a title and `path:line` each). Nothing found: say so in one line.

## Plan check

The same items, citing `spec.md › <section>` or `ledger.md › <row>` in place of `path:line`. The last line is:

```
Verdict: READY | NOT READY (<open Blockers/Majors>)
```
