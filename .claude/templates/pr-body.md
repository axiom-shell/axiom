# PR body

Used by: `/orchestrate`.
Filled by: the lead, as `pr-body.md` (`pr-body-<n>.md` per PR of a stack) in the state folder; `gh pr create --body-file`.

`.github/pull_request_template.md` filled as it is, plus these sections:

```
## Tier
## What users notice
## Live checks              the LIVE: lines
## Not run, weak or inconclusive
## Changed pieces           users and the check that covered each
## Rulings                  each ruling and default taken, in plain technical terms: no R/D ids, step, plan or question ids, no plan quotes
<the session's attribution line>
```

- An alignment request adds its census table and behaviour changes under What users notice.
- Nothing in the GitHub template changes.
