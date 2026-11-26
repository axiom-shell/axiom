# Orchestrate: stacks

- **What a plan file gives** (the `plan-file` example below): per stack a public **series title** (`## Stack <k> · <series title>`); per part, bottom → top, the example's columns (the **branch** descriptive kebab-case, never an id, a number or `<slug>/<part>`: `bar-layout-model`; the PR **subject** lower case), its **Binding** and **gate rows**. `Waits and status:` names the file holding Needs, Freeze, Blocked by and Status (`this file`, or absent: this file); the lead reads the waits there before a part starts and writes the status there: `in progress` at start, `PR #<n>` when ready, `merged` (the `Parts:` row's words).

```plan-file
Waits and status: this file

## Stack 1 · Bar layout

| Part | Id | Branch | Subject | Scope | Needs | Freeze | Blocked by | Status |
|---|---|---|---|---|---|---|---|---|
| 1/2 | lay1 | bar-layout-model | one model for bar sections | the bar reads its sections from one list | — | — | — | merged |
| 2/2 | lay2 | bar-layout-editor | edit bar sections in place | the editor writes that list | lay1 | — | — | open |

### lay1
Binding: the rows the part must follow, quoted into decisions.md
Gate rows: the checks that pass before its PR

### lay2
Binding: …
Gate rows: …
```

- **Planning.** At run start, one `/keep-order plan` for the whole stack: decisions.md › Request is the invocation verbatim, followed by `### Plan rows (private)`, the plan file's Binding block and the gate rows of the stack's parts, quoted; one ledger; `spec-<n>.md` and `pr-body-<n>.md` per part. When a part's turn comes and the code under it has moved, an architect revises that part's spec; a ledger change to the names of a part whose PR is open goes through that part's Fix round.
- **Tiers.** When the architect proposes a split, its spec names each part's branch (the form in › What a plan file gives) and each PR gets its own spec; the ledger is shared; each part is tiered by its own signals (its `Parts:` row's `tier`), and its plan check runs by that tier.
- **Per part** (steps 3–8): plan check by the part's Tier; groups, gate and commit as today; review `--base` = the part below's head (the bottom part: its `origin/main` base); `gh pr create --base <part below's branch | main>`; title `<series> <n>/<m>: <subject>` (a one-part stack: `<series>: <subject>`); a body that justifies the change on its own merits. `verify.sh --all` runs as › The stack rebase rule says. A part whose waits are unmet is `paused (<what>)`; the parts below it go on to PR and merge; state.md `Next:` names what it waits for. Each later part's branch: `git -C <tree> switch -c <branch> <part below>` in the same tree (a part whose parts below have all merged is the bottom part: `git -C <tree> fetch -q origin`, then `git -C <tree> switch -c <branch> origin/main`); `git rebase --update-refs` skips a branch checked out in another worktree. State: `Base:` is the part below's head (the bottom part: its `origin/main` sha); `Branch:`, `Base:`, `Head:`, `Tier:`, `Last reviewed:` and `Spec:` describe the active part, and on every `git switch` the lead writes them back to its `Parts:` row and copies the next part's values up; a `Parts:` row's `head` is updated after each commit of its part.
- **Resume** reads every part's `gh pr view <n> --json state,headRefOid,baseRefName`. A merged bottom part triggers the stack rebase rule's `--onto` lines, `gh pr edit <next> --base main` and the local merged branch's deletion, each push and PR edit with the leak check first (`finish.md` step 7); the lead then sets that part's status merged where the plan file says.
- **The stack rebase rule.** Every rebase runs once, from the top part, with `--update-refs`, so every branch in the stack moves in one pass: the block below. The merged part's old tip is its PR's `headRefOid` (`gh pr view <n> --json headRefOid`), cross-checked with its `Parts:` row's head. After any rebase, `git range-diff <old base>..<old head> <new base>..<new head>` per moved part: only `=` keeps its review (its last reviewed moves to the rebased sha); a changed patch gets `/keep-order audit --since <its pre-rebase last reviewed>`. Once its range-diff has read the old values, the part's `Parts:` row's `base` and `head` take the new ones (the active part's `Base:` and `Head:` too). `verify.sh --all` runs only on the top part (`finish.md` step 6); a lower part's verify is its review checker's run and its own CI. A conflict: `git rebase --abort`; a fresh implementer re-runs the command, resolves and runs `git rebase --continue` (its brief lifts "don't commit" for that command only); the lead pushes.

```bash stack-rebase
git switch <top>
git rebase --update-refs <fixed part>
git fetch origin
git rebase --update-refs origin/main
git rebase --onto origin/main <merged part's old tip> <top> --update-refs
git push --force-with-lease origin <each moved branch>
gh pr edit <n> --base main
```

Line 2 carries a lower part's fix up (`<fixed part>` holds the fix); lines 3–4 carry a newer `origin/main` the stack must carry (a Need or Freeze merged, or main moved under a conflict); lines 3 and 5–7 follow the user's squash-merge of the bottom PR. The old base and head are the part's `Parts:` row values. A conflict brief's Do is "run `<the command>`, resolve, `git rebase --continue`".

## Write-back

Runs when CLAUDE.local.md names `Amendments:` (the plan's error log) or `Plan lint:`; a bullet whose key is missing is skipped.
- Before planning: grep the amendments file's Open section for the stack's part ids, files and new names. A matching row goes to an architect, whose ruling edits the plan file; a Shape row goes to the user word for word, and its part waits.
- A plan error or ruling found during the run (a spec Decision contradicting a plan row, a stale cite) goes into the amendments file (ruled, or in its Open section) before the part's status becomes `PR #<n>`.
- Before deleting the state folder: its rulings, freeze deltas and plan corrections go into the amendments file (and the homes it names); nothing that changes the plan stays only in the state folder.
- The status update that sets `merged` cuts the part's plan section to a pointer at its repo home.
- After any plan edit: `<Plan lint> --tree <tree>`; log its findings, never silence them.
