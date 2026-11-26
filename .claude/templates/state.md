# State

Used by: `.claude/skills/keep-order/SKILL.md`, `.claude/skills/review-branch/SKILL.md`, `/orchestrate`.
Filled by: the lead, as `state.md` in the state folder, after every step. `/orchestrate resume <slug>` reads it.

```
# <slug>: state
Tier: T<n> (history) · Phase: plan | check <r> | group <g> | review <r> | verify | pr | ci | ready
Tree: · Branch: · Base: (origin/main sha at creation) · Head: (last commit) · PR (#, base; a stack: per part in Parts:)
Plan check: round, verdict
Groups: G<n> | status | commit | gate (clean / fix file) | NOT RUN or weak ids
Last reviewed: <sha>
Open questions (asked <date>)
LIVE: lines · What users notice · Changed pieces → users checked
Next: <one step>
Spec: <spec file of the active part; default spec.md>
Stack: <k> of <plan file> · <tree> · <open | paused (<what>) | done>
Parts: <n>/<m> · <part id> · <branch> · base <branch below | main> @ <sha> · head <sha> · tier T<n> · last reviewed <sha | —> · PR #<n> | — · <open | in progress | paused (<what>) | PR #<n> | merged>
```

- Skills read only `Base:`, `Head:`, `Tier:`, `Last reviewed:` and `Spec:`; `/review-branch --state` writes `Last reviewed:`.
- `Base:` is the origin/main sha the tree was created at (a stack: `stacks.md` › Per part).
- `Spec:`, `Stack:` and `Parts:` are stack-only except `Spec:` (default `spec.md`).
- `Next:` is one step, enough for a fresh session to continue.
