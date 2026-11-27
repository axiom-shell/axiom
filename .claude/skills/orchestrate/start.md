# Orchestrate: steps 1–3

1. **Start.**
   - Slug (kebab-case, the branch name; a stack's: `stacks.md`); decisions.md (request verbatim; Scope line with what it includes and, quoted, what it excludes); tier proposed.
   - Tree: `git -C <main checkout> fetch -q origin`; `git -C <main checkout> worktree add --no-track -b <slug | bottom part's branch> <worktrees folder>/<slug | stem | stem-s<k>> origin/main` (later parts: `stacks.md` › Per part); `cd <tree> && scripts/generate.sh`.
   - state.md with `Tree:`, `Branch:`, `Base:` (`git -C <tree> rev-parse HEAD`), `Head:` (the same), `Tier:`.
2. **Plan.** `/keep-order plan --state <state folder> --tree <tree>`; an alignment request runs `/align "<description>" --state <state folder> --tree <tree>` instead. Relay open questions per `SKILL.md` › Questions.
3. **Plan check.** Per tier. A fresh `architect` (brief: `Tree:`, `Base:`) runs › Checking a plan and writes `plan-check-<n>.md`. NOT READY: a fresh architect revises the spec and ledger, then the next round if the tier allows. After the last round, any Blocker, Major or open question goes to the user.
