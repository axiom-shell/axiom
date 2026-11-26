# Orchestrate: steps 5–9 and the report

5. **Review.**
   - `/keep-order audit --state <state folder> --tree <tree> --fix` (it passes `--base <Base> --size <Tier's size> --state <state folder>` and, once recorded, `--since <Last reviewed>` to `/review-branch`).
   - After each Fix round, commit as in `SKILL.md` step 4.5.
   - Never a second full review. A round that fixed a Blocker or Major gets one more audit (now with `--since`); if that round still finds one, go to the user.
6. **Verify.** Only if state.md's `Head:` differs from `Last reviewed:` (the review's checker ran at that sha): a `checker` (brief: `Tree:`) runs `scripts/dev/verify.sh --all` and must print `all checks passed` (a stack: `stacks.md` › The stack rebase rule).
7. **PR.** `git -C <tree> push -u origin <branch>`; write `<state folder>/pr-body.md` (`.claude/templates/pr-body.md`); `cd <tree> && gh pr create --base main --title "<subject>" --body-file <state folder>/pr-body.md`. The subject is one line in the style of `git -C <tree> log --oneline -5 origin/main` (a stack: `stacks.md` › Per part).
   - **Leak check.** When there is a leak check file (`SKILL.md` › State), before every push and every `gh pr create`/`gh pr edit` run `grep -nEf <that file>` over the lines the part adds (`git -C <tree> diff <Base>...HEAD | grep '^+'`), its commit messages (`git -C <tree> log --format=%B <Base>..HEAD`), its branch name and its `pr-body-<n>.md` (plain run: `pr-body.md`); a hit is fixed first (code or comment: a Fix round; commit message: reworded; body: rewritten). The skill names no pattern. A blank line in that file matches every line; the lead asks the user to remove it before the check runs.
8. **CI.** `cd <tree> && gh pr checks <n> --watch`. On a failure: a Fix round with source `ci<c>` (fix list from `gh run view <id> --log-failed | tail -60`), `--all`, commit, leak check first (step 7), push. At most twice, then stop.
9. **Ready.** Report and stop. Never merge.

## Report

```
# Ready: <slug> — PR #<n> at <sha> (CI green; verify --all: all checks passed)
Tier: T<n> · Review: <rounds>, last reviewed <sha>
## Not run, weak or LIVE   (every such acceptance check, with why)
## Changed pieces          (piece: every user and the check that covered it)
## Rulings and defaults taken
## Questions               (word for word; or none)
## Outside the branch      (also written to the follow-ups file when CLAUDE.local.md names one)
```
