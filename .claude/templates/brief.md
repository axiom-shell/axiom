# Brief

Used by: `.claude/skills/keep-order/SKILL.md`, `.claude/skills/review-branch/SKILL.md`, `.claude/skills/review-system/SKILL.md`, `.claude/skills/align/SKILL.md`, `/orchestrate`, the recipe skills.
Filled by: the lead, for every agent it starts (fresh agent, `subagent_type: <role>`).

```
To: <role> · Goal: <one or two sentences> · Tier: T<n>
Tree: <abs path> — every Bash call starts `cd <tree> &&` (or `git -C <tree>`); never run in your start folder
Base: <sha> (new_names.py --base <it>) · Branch <b>, head <sha>; earlier groups built: <one line>
Read: <state folder>/spec.md › <sections>, ledger.md, decisions.md (absolute paths)
Binding: <ledger rows and D/R decisions quoted verbatim>. Anything they don't cover is a stop.
Do: <group n only / the fix list / the check>
Rules: CLAUDE.md › Never and › Working here (nested shells); don't commit (except the `git rebase --continue` a rebase-conflict Do names); never run `shot.sh` or a bare `axiom` from a worktree; no sudo, pkexec, su; no memory or CLAUDE.local.md writes.
Done when: <acceptance ids, verbatim> + `verify.sh` → `verify ok` (`--all` → `all checks passed`)
Report: <template path>; nothing it lists is dropped
```

- Quote ledger rows; never paraphrase a name.
- An agent with no `Tree:` stops (a recipe skill typed directly: › Recipe skills).
- Add your own decisions to `Binding` only as quoted D/R ids.

## Recipe skills

- The task is all you have; if it is empty, stop and say so.
- Typed directly, with no `Tree:` or `Base:` in the task: Tree is `git rev-parse --show-toplevel` of the start folder, and Base is `git -C <tree> merge-base origin/main HEAD`.
- Follow the recipe's Copy from, Steps and Watch out for.
- Run its Check it steps (if it has none, the checks its Steps name), then verify until `verify ok`.
- Update its Docs to update.
- Stop on an open behaviour decision or a case the recipe doesn't cover, and name the question.
- Report in `.claude/templates/implementer-report.md`, with **Names added**.
