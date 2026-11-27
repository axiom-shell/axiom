# Orchestrate: steps 5–8

5. **Review.**
   - `/keep-order audit --state <state folder> --tree <tree> --fix` (it passes `--base <Base> --size <Tier's size> --state <state folder>` and, once recorded, `--since <Last reviewed>` to `/review-branch`).
   - After each Fix round, commit as in `SKILL.md` step 4.5.
   - Never a second full review. A round that fixed a Blocker or Major gets one more audit (now with `--since`); if that round still finds one, go to the user.
6. **Verify.** Only if state.md's `Head:` differs from `Last reviewed:` (the review's checker ran at that sha): a `checker` (brief: `Tree:`) runs `scripts/dev/verify.sh --all` and must print `all checks passed` (a stack: `stacks.md` › The stack rebase rule).
7. **Report.** Write `<state folder>/report.md` (`.claude/templates/report.md`). Its PR title is one line in the style of `git -C <tree> log --oneline -5 origin/main` (a stack: `stacks.md` › Per part). Set state.md's Phase to `ready` and `Next:` to `open the PR from the report` (a stack: `, then /orchestrate resume <slug>`); give the user the report's path and its Questions; stop.
8. **CI fix.** A failed CI run (named by `Next:` or by the user): Phase `ci`, a Fix round with source `ci<c>` (fix list from `gh run view <id> --log-failed | tail -60`; no id: the failed check's link in `gh pr checks <branch>`), `--all`, commit as in `SKILL.md` step 4.5, then step 7. At most two per PR; a third failure goes to the user.
