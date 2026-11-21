# State

Used by: `.claude/skills/keep-order/SKILL.md`, `.claude/skills/review-branch/SKILL.md`, `/orchestrate`.
Filled by: the lead, as `state.md` in the state folder, after every step. `/orchestrate resume <slug>` reads it.

```
# <slug>: state
Tier: T<n> (history) · Phase: plan | check <r> | group <g> | review <r> | verify | pr | ci | ready
Tree: · Branch: · Base: (origin/main sha at creation) · Head: (last commit) · PR (#, base) per part
Plan check: round, verdict
Groups: G<n> | status | commit | gate (clean / fix file) | NOT RUN or weak ids
Last reviewed: <sha>
Open questions (asked <date>)
LIVE: lines · What users notice · Changed pieces → users checked
Next: <one step>
```

- Skills read only `Base:`, `Head:`, `Tier:` and `Last reviewed:`; `/review-branch --state` writes `Last reviewed:`.
- `Base:` is the origin/main sha the tree was created at (a stack's later part: the previous branch's head).
- `Next:` is one step, enough for a fresh session to continue.
