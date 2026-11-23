---
name: orchestrate
description: Runs every change to axiom (bug fix, alignment, improvement, feature) from request to a ready PR. Use when the user asks for a change or runs /orchestrate, or `resume <slug>` in a fresh session. Main session only; never from a subagent or another skill.
argument-hint: "<request> | align <description> | group <plan file> [--stack <k>] | resume <slug>"
---

# Orchestrate

You are the lead, in the main session: you size, plan, brief, gate, commit, open the PR and report. Agents read and write code.

Arguments: `$ARGUMENTS`
- Free text: the request, quoted verbatim into decisions.md.
- `align <description>`: an alignment request; step 2 runs `/align`.
- `group <plan file> [--stack <k>]`: run one stack of a plan file (› Stacks). `<plan file>` is an absolute path, or a file name in the plan files folder (› State). `--stack <k>` picks the k-th stack and is required when the plan has two or more; one run owns one stack.
- `resume <slug>`: continue a change in a fresh session (step 1).

Layouts: every hand-off has one file in `.claude/templates/`: `brief.md`, `spec.md`, `ledger.md`, `decisions.md`, `state.md`, `finding.md` (a plan check), `verdict.md`, `fix-list.md`, `implementer-report.md`, `checker-report.md`, `review-report.md`, `pr-body.md`. Fill them; never restate them.

## The lead

- **What you read.** Never source files or diffs: `--stat`/`--shortstat`, `new_names.py` output, reports, and check output (`tail`, `grep`). An unclear bug or claim goes to an `architect`.
- **Skills and agents.** Run skills with the Skill tool, each with `--tree <tree>` (a recipe skill gets it as the brief's `Tree:`), never by reading their files. Each role and round gets a fresh agent.
- **Briefs** are `.claude/templates/brief.md`, complete the first time. Quote decisions verbatim; add no step of your own.
- **A stopped agent** goes to an `architect`, or to the user if the decision is product.
- **Nested shells** follow CLAUDE.md › Working here.
- **Never** merge or push to main. Do nothing unasked: no memory writes, PR comment edits, issues or standing rules.
- **"Was it checked?"** Answer from state.md, naming every `NOT RUN` and weak check.

## Questions

- Before relaying anything, reread decisions.md and the PR comments (`gh pr view <n> --json comments`).
- Drop a question the request's own principle answers; record it as an R quoting the principle.
- Relay word for word, in one batch: product questions (defaults, behaviour users notice, migrations, takeovers) and every LOST Becomes row. Start nothing that depends on them.
- Everything else you rule: an R in decisions.md with a one-line reason, restated in the PR body in plain technical terms, without R/D ids or anything quoted from a plan file (`.claude/templates/pr-body.md` › Rulings).
- A default the request or a D already fixes goes under Defaults taken. Any other default is a question.
- User instructions go into decisions.md as D answers (verbatim, dated, where given), never into standing rules, memory, CLAUDE.md or CLAUDE.local.md unasked.

## State

- **Plans folder:** CLAUDE.local.md's `Plans folder:`, else `<main checkout>/.plans/`. **Worktrees folder:** `Worktrees folder:`, else `<main checkout>/.claude/worktrees/`. **Plan files folder:** `Plan files:`, no default (without the line, `<plan file>` must be an absolute path). **Leak check file:** `Leak check:`, no default (without the line, step 7's leak check is skipped). A leading `~` in any of these lines expands to `$HOME`. `<main checkout>` is `git rev-parse --path-format=absolute --git-common-dir` less `/.git`. A folder outside the project must be a working directory; so must the plan files folder, the leak check file's folder and any file the lead writes a status to.
- **State folder** `<plans folder>/<slug>/` (a group run: `<plans folder>/<stem>/`, `<stem>-s<k>` with `--stack`, `<stem>` the plan file's name without `.md`): `state.md`, `decisions.md`, `spec.md` (`spec-<n>.md` per PR of a stack), `ledger.md`, `plan-check-<n>.md`, `fix-<source>-<n>.md` (source `gate<g>`, `review<r>` or `ci<c>`), `pr-body.md` (`pr-body-<n>.md` per PR of a stack), `census.md` (align). Update state.md after every step, and `Head:` after every commit.
- **Tree and base:** the tree is the worktree; Base is state.md's `Base:`. Every command runs as `git -C <tree>` or `cd <tree> &&`. Before each skill, `git -C <tree> rev-parse --show-toplevel` must print the tree.

## Tiers

Every tier has a ledger; tiers scale planning and review, never alignment.

| Tier | Signals | Size (`/review-branch` › 2. Size; lowercased, the `--size`) | Plan check |
|---|---|---|---|
| T0 Fix | a bug or alignment fix in one place; no new public name; no Becomes phrase in the request | Tiny | yours, against the templates |
| T1 Improvement | changes something existing, one area | Small | one round (+1 if a Blocker/Major was revised) |
| T2 Feature | new feature or rework in one system | Larger | up to two rounds |
| T3 Cross-system | two or more `.claude/rules/` areas, schema + backend + UI, tooling contracts | Larger | up to two rounds |

- You propose the tier; the planning architect confirms or raises it in spec.md's Tier line. Tiers only go up; the user may lower one.
- Re-tier up when the spec's files exceed the size; the gate rules a new ledger row (at T0, any name); an implementer stops for a new name; or `git -C <tree> diff --shortstat <Base>` (generated files out) passes the size. Run the new tier's missing planning steps before the next group, and record it.
- A stack: when the architect proposes a split, each PR gets its own spec; the ledger is shared; each part is tiered by its own signals (its `Parts:` row's `tier`), and its plan check runs by that tier.

## Steps

1. **Start.**
   - Slug (kebab-case, the branch name; a stack's parts get descriptive kebab-case branch names (the spec's split names them; a group run: the plan file), never `<slug>/<part>`); decisions.md (request verbatim; Scope line with what it includes and, quoted, what it excludes); tier proposed.
   - Tree: `git -C <main checkout> fetch -q origin`; `git -C <main checkout> worktree add --no-track -b <slug | bottom part's branch> <worktrees folder>/<slug | stem | stem-s<k>> origin/main`; each later part `git -C <tree> switch -c <branch> <part below>` in the same tree (a part whose parts below have all merged is the bottom part: `git -C <tree> fetch -q origin`, then `git -C <tree> switch -c <branch> origin/main`) (`git rebase --update-refs` skips a branch checked out in another worktree); `cd <tree> && scripts/generate.sh`.
   - state.md with `Tree:`, `Branch:`, `Base:` (`git -C <tree> rev-parse HEAD`), `Head:` (the same), `Tier:`.
   - `resume <slug>`: read state.md and decisions.md, `git -C <tree> status` and `log -3`, and the stack's PR comments (answers become D); continue at Next. A stack: every part's `gh pr view <n> --json state,headRefOid,baseRefName` (› Stacks › Resume).
2. **Plan.** `/keep-order plan --state <state folder> --tree <tree>`; an alignment request runs `/align "<description>" --state <state folder> --tree <tree>` instead. Relay open questions per Questions.
3. **Plan check.** Per tier. A fresh `architect` (brief: `Tree:`, `Base:`) runs › Checking a plan and writes `plan-check-<n>.md`. NOT READY: a fresh architect revises the spec and ledger, then the next round if the tier allows. After the last round, any Blocker, Major or open question goes to the user.
4. **Groups.** For each spec group:
   1. Brief (`Tree:`, `Base:` = state.md's Base) to a fresh `implementer`, or `/<recipe> "<the filled brief>"` when the group names a recipe.
   2. Read the report. Each acceptance check needs a PASS with evidence. FAIL, NOT RUN, weak or "by construction" is not done: a fresh implementer for it. It becomes a `LIVE:` line only on an architect's ruling that no test or log can reach it, and a nested check only on its ruling that one is necessary (CLAUDE.md › Working here). Log lines from another tree are not evidence.
   3. Re-tier check.
   4. `/keep-order gate --tree <tree> --state <state folder>`, and its Fix round (judged as in 4.2).
   5. Commit: `git -C <tree> add -A && git -C <tree> -c core.hooksPath=.githooks commit -F -`, ending with the session's attribution lines; set state.md's `Head:`.
5. **Review.**
   - `/keep-order audit --state <state folder> --tree <tree> --fix` (it passes `--base <Base> --size <Tier's size> --state <state folder>` and, once recorded, `--since <Last reviewed>` to `/review-branch`).
   - After each Fix round, commit as in 4.5.
   - Never a second full review. A round that fixed a Blocker or Major gets one more audit (now with `--since`); if that round still finds one, go to the user.
6. **Verify.** Only if state.md's `Head:` differs from `Last reviewed:` (the review's checker ran at that sha): a `checker` (brief: `Tree:`) runs `scripts/dev/verify.sh --all` and must print `all checks passed` (a stack: › The stack rebase rule says which part).
7. **PR.** `git -C <tree> push -u origin <branch>`; write `<state folder>/pr-body.md` (`.claude/templates/pr-body.md`); `cd <tree> && gh pr create --base main --title "<subject>" --body-file <state folder>/pr-body.md`. The subject is one line in the style of `git -C <tree> log --oneline -5 origin/main` (a stack: base and title as › Stacks › Per part).
   - **Leak check.** When there is a leak check file (› State), before every push and every `gh pr create`/`gh pr edit` run `grep -nEf <that file>` over the lines the part adds (`git -C <tree> diff <Base>...HEAD | grep '^+'`), its commit messages (`git -C <tree> log --format=%B <Base>..HEAD`), its branch name and its `pr-body-<n>.md` (plain run: `pr-body.md`); a hit is fixed first (code or comment: a Fix round; commit message: reworded; body: rewritten). The skill names no pattern. A blank line in that file matches every line; the lead asks the user to remove it before the check runs.
8. **CI.** `cd <tree> && gh pr checks <n> --watch`. On a failure: a Fix round with source `ci<c>` (fix list from `gh run view <id> --log-failed | tail -60`), `--all`, commit, leak check first (step 7), push. At most twice, then stop.
9. **Ready.** Report and stop. Never merge.

Bounds: hand off with `/orchestrate resume <slug>` after each ready PR, or at about 100k tokens of context.

## Stacks

- **What a plan file gives** (stated once, with a fenced example whose info string is `plan-file`): per stack a public **series title** in plain words (`## Stack <k> · <series title>`); per part, bottom → top, the columns of the example: a plan-local id, a **branch** (descriptive kebab-case, never an id or a number: `bar-layout-model`), a PR **subject** (lower case), a one-line scope and the part's waits (Needs, Freeze, Blocked by) and Status; each part's **Binding** and **gate rows**; `Waits and status:` names the file holding the Needs, Freeze, Blocked by and Status columns (`this file` when it names none, or absent). The lead reads the waits there before a part starts and writes the part's status there at start, ready and merged. The status words are the `Parts:` row's (`.claude/templates/state.md`): `in progress` at start, `PR #<n>` when ready, `merged`.

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

## Stack 2 · Popout placement

| Part | Id | Branch | Subject | Scope | Needs | Freeze | Blocked by | Status |
|---|---|---|---|---|---|---|---|---|
| 1/1 | pop1 | popout-edge-placement | place popouts on the nearest edge | one placement rule for every popout | — | — | — | open |

### pop1
Binding: …
Gate rows: …
```

- **Planning.** At run start, one `/keep-order plan` for the whole stack: decisions.md › Request is the invocation verbatim, followed by `### Plan rows (private)`, the plan file's Binding block and the gate rows of the stack's parts, quoted; one ledger; `spec-<n>.md` and `pr-body-<n>.md` per part. When a part's turn comes and the code under it has moved, an architect revises that part's spec; a ledger change to the names of a part whose PR is open goes through that part's Fix round.
- **Per part** (steps 3–8): plan check by the part's Tier; groups, gate and commit as today; review `--base` = the part below's head (the bottom part: its `origin/main` base); `gh pr create --base <part below's branch | main>`; title `<series> <n>/<m>: <subject>` (a one-part stack: `<series>: <subject>`); a body that justifies the change on its own merits. `verify.sh --all` runs as › The stack rebase rule says. A part whose waits are unmet is `paused (<what>)`; the parts below it go on to PR and merge; state.md `Next:` names what it waits for.
- **Resume** reads every part's `gh pr view <n> --json state,headRefOid,baseRefName`. A merged bottom part triggers the stack rebase rule's `--onto` lines, `gh pr edit <next> --base main` and the local merged branch's deletion, each push and PR edit with the leak check first (step 7); the lead then sets that part's status merged where the plan file says.
- **The stack rebase rule.** Every rebase runs once, from the top part, with `--update-refs`, so every branch in the stack moves in one pass. A fix on a lower part: `git rebase --update-refs <fixed part>` (the part that holds the fix). A newer `origin/main` the stack must carry (a Need or Freeze merged, or main moved under a conflict): `git fetch origin`, then `git rebase --update-refs origin/main`. After the user squash-merges the bottom PR: `git fetch origin`, then `git rebase --onto origin/main <merged part's old tip> <top> --update-refs`, and the next PR's base goes to main with `gh pr edit <n> --base main`. Push each moved branch with `--force-with-lease`. The merged part's old tip is its PR's `headRefOid` (`gh pr view <n> --json headRefOid`), cross-checked with the part's head in state.md. After any rebase, `git range-diff <old base>..<old head> <new base>..<new head>` per moved part: a part showing only `=` keeps its review (its last reviewed moves to the rebased sha); a part with a changed patch gets `/keep-order audit --since <its pre-rebase last reviewed>`. `verify.sh --all` runs only on the top part (orchestrate step 6); a lower part's verify is its review checker's run and its own CI. A conflict: `git rebase --abort`; a fresh implementer re-runs the command, resolves and runs `git rebase --continue` (its brief lifts "don't commit" for that command only); the lead pushes.

```bash stack-rebase
git switch <top>
git rebase --update-refs <fixed part>
git fetch origin
git rebase --update-refs origin/main
git rebase --onto origin/main <merged part's old tip> <top> --update-refs
git push --force-with-lease origin <each moved branch>
gh pr edit <n> --base main
```

Line 2 carries a lower part's fix up; lines 3–4 carry a newer `origin/main`; lines 3 and 5–7 follow the user's squash-merge of the bottom PR. The old base and head are the part's `Parts:` row values. A conflict brief's Do is "run `<the command>`, resolve, `git rebase --continue`".

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
