# Fix list

Filled by: the gate's architect for `gate<g>` (`.claude/skills/keep-order/SKILL.md` › gate); the lead for `review<r>`, `ci<c>` and a later ruling in the same round. Its one home is `fix-<source>-<n>.md` in the state folder (`.claude/skills/orchestrate/SKILL.md` › State); without a state folder, the lead puts it inline in the brief.

```
# Fix list: <source> <n>
Tree: <abs path> · Base: <sha>
F<n> [severity] path:line — defect · Fix: smallest change · Ruling: <quoted>
Behaviour decisions: none here
Done when: verify ok, then the gate
```

- A finding whose fix changes behaviour users notice is not listed: it goes to the user.
- Given to a fresh implementer in a brief (`.claude/templates/brief.md`), never a resumed one.
