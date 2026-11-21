# Fix list

Used by: `.claude/skills/keep-order/SKILL.md` (Fix round), `.claude/skills/review-branch/SKILL.md`, `.claude/skills/review-system/SKILL.md`.
Filled by: the lead, as `fix-<source>-<n>.md` in the state folder (inline in the brief without one), from confirmed findings and architect rulings.

```
# Fix list: <source> <n>
Tree: <abs path> · Base: <sha>
F<n> [severity] path:line — defect · Fix: smallest change · Ruling: <quoted>
Behaviour decisions: none here
Done when: verify ok, then the gate
```

- A finding whose fix changes behaviour users notice is not listed: it goes to the user.
- Given to a fresh implementer in a brief (`.claude/templates/brief.md`), never a resumed one.
