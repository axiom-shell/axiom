---
name: orchestrate
description: Runs every change to axiom (bug fix, alignment, improvement, feature) from request to a ready PR. Use when the user asks for a change or runs /orchestrate, or `resume <slug>` in a fresh session. Main session only; never from a subagent or another skill.
argument-hint: "<request> | align <description> | resume <slug>"
---

# Orchestrate

You are the lead, in the main session: you size, plan, brief, gate, commit, open the PR and report. Agents read and write code.

Arguments: `$ARGUMENTS`
- Free text: the request, quoted verbatim into decisions.md.
- `align <description>`: an alignment request; step 2 runs `/align`.
- `resume <slug>`: continue a change in a fresh session (step 1).

Layouts: every hand-off has one file in `.claude/templates/`: `brief.md`, `spec.md`, `ledger.md`, `decisions.md`, `state.md`, `finding.md` (a plan check), `verdict.md`, `fix-list.md`, `implementer-report.md`, `checker-report.md`, `review-report.md`, `pr-body.md`. Fill them; never restate them.

## The lead

- **What you read.** Never source files or diffs: `--stat`/`--shortstat`, `new_names.py` output, reports, and check output (`tail`, `grep`). An unclear bug or claim goes to an `architect`.
- **Skills and agents.** Run skills with the Skill tool, each with `--tree <tree>`, never by reading their files. Each role and round gets a fresh agent.
- **Briefs** are `.claude/templates/brief.md`, complete the first time. Quote decisions verbatim; add no step of your own.
- **A stopped agent** goes to an `architect`, or to the user if the decision is product.
- **Nested shells** follow CLAUDE.md › Working here.
- **Never** merge or push to main. Do nothing unasked: no memory writes, PR comment edits, issues or standing rules.
- **"Was it checked?"** Answer from state.md, naming every `NOT RUN` and weak check.

## Questions

- Before relaying anything, reread decisions.md and the PR comments (`gh pr view <n> --json comments`).
- Drop a question the request's own principle answers; record it as an R quoting the principle.
- Relay word for word, in one batch: product questions (defaults, behaviour users notice, migrations, takeovers) and every LOST Becomes row. Start nothing that depends on them.
- Everything else you rule: an R in decisions.md with a one-line reason, repeated in the PR body.
- A default the request or a D already fixes goes under Defaults taken. Any other default is a question.
- User instructions go into decisions.md as D answers (verbatim, dated, where given), never into standing rules, memory, CLAUDE.md or CLAUDE.local.md unasked.

## State

- **Plans folder:** CLAUDE.local.md's `Plans folder:`, else `<main checkout>/.plans/`. **Worktrees folder:** `Worktrees folder:`, else `<main checkout>/.claude/worktrees/`. `<main checkout>` is `git rev-parse --path-format=absolute --git-common-dir` less `/.git`. A folder outside the project must be a working directory.
- **State folder** `<plans folder>/<slug>/`: `state.md`, `decisions.md`, `spec.md` (`spec-<n>.md` per PR of a stack), `ledger.md`, `plan-check-<n>.md`, `fix-<source>-<n>.md` (source `gate<g>`, `review<r>` or `ci<c>`), `pr-body.md` (`pr-body-<n>.md` per PR of a stack), `census.md` (align). Update state.md after every step, and `Head:` after every commit.
- **Tree and base:** the tree is the worktree; Base is state.md's `Base:`. Every command runs as `git -C <tree>` or `cd <tree> &&`. Before each skill, `git -C <tree> rev-parse --show-toplevel` must print the tree.

## Tiers

Every tier has a ledger; tiers scale planning and review, never alignment.

| Tier | Signals | Size (`/review-branch` › 2. Size) | Plan check | Review `--size` |
|---|---|---|---|---|
| T0 Fix | a bug or alignment fix in one place; no new public name; no Becomes phrase in the request | Tiny | yours, against the templates | tiny |
| T1 Improvement | changes something existing, one area | Small | one round (+1 if a Blocker/Major was revised) | small |
| T2 Feature | new feature or rework in one system | Larger | up to two rounds | larger |
| T3 Cross-system | two or more `.claude/rules/` areas, schema + backend + UI, tooling contracts, or a stack | Larger | up to two rounds | larger |

- You propose the tier; the planning architect confirms or raises it in spec.md's Tier line. Tiers only go up; the user may lower one.
- Re-tier up when the spec's files exceed the size; the gate rules a new ledger row (at T0, any name); an implementer stops for a new name; or `git -C <tree> diff --shortstat <Base>` (generated files out) passes the size. Run the new tier's missing planning steps before the next group, and record it.
- A stack: when the architect proposes a split, each PR gets its own spec; the ledger is shared.

## Steps

1. **Start.**
   - Slug (kebab-case, the branch name; a stack's parts `<slug>/<part>`); decisions.md (request verbatim; Scope line with what it includes and, quoted, what it excludes); tier proposed.
   - Tree: `git -C <main checkout> fetch -q origin`; `git -C <main checkout> worktree add --no-track -b <branch> <worktrees folder>/<slug> origin/main` (a stack's later part: `<slug>-<part>`, off the previous branch); `cd <tree> && scripts/generate.sh`.
   - state.md with `Tree:`, `Branch:`, `Base:` (`git -C <tree> rev-parse HEAD`), `Head:` (the same), `Tier:`.
   - `resume <slug>`: read state.md and decisions.md, `git -C <tree> status` and `log -3`, and the stack's PR comments (answers become D); continue at Next.
2. **Plan.** `/keep-order plan --state <state folder> --tree <tree>`; an alignment request runs `/align "<description>" --state <state folder> --tree <tree>` instead. Relay open questions per Questions.
3. **Plan check.** Per tier. A fresh `architect` (brief: `Tree:`, `Base:`) runs › Checking a plan and writes `plan-check-<n>.md`. NOT READY: a fresh architect revises the spec and ledger, then the next round if the tier allows. After the last round, any Blocker, Major or open question goes to the user.
4. **Groups.** For each spec group:
   1. Brief (`Tree:`, `Base:` = state.md's Base) to a fresh `implementer`, or `/<recipe> "<the filled brief>"` when the group names a recipe.
   2. Read the report. Each acceptance check needs a PASS with evidence. FAIL, NOT RUN, weak or "by construction" is not done: a fresh implementer for it. It becomes a `LIVE:` line only on an architect's ruling that no test or log can reach it (CLAUDE.md › Working here). Log lines from another tree are not evidence.
   3. Re-tier check.
   4. `/keep-order gate --tree <tree> --state <state folder>`, and its Fix round (judged as in 4.2).
   5. Commit: `git -C <tree> add -A && git -C <tree> -c core.hooksPath=.githooks commit -F -`, ending with the session's attribution lines; set state.md's `Head:`.
5. **Review.**
   - `/keep-order audit --state <state folder> --tree <tree> --fix` (it passes `--base <Base> --size <Tier's size> --state <state folder>` and, once recorded, `--since <Last reviewed>` to `/review-branch`).
   - After each Fix round, commit as in 4.5.
   - Never a second full review. A round that fixed a Blocker or Major gets one more audit (now with `--since`); if that round still finds one, go to the user.
6. **Verify.** Only if commits came after the review's checker: a `checker` (brief: `Tree:`) runs `scripts/dev/verify.sh --all` and must print `all checks passed`.
7. **PR.** `git -C <tree> push -u origin <branch>`; write `<state folder>/pr-body.md` (`.claude/templates/pr-body.md`); `cd <tree> && gh pr create --base <main | previous branch> --body-file <state folder>/pr-body.md`.
8. **CI.** `cd <tree> && gh pr checks <n> --watch`. On a failure: a Fix round with source `ci<c>` (fix list from `gh run view <id> --log-failed | tail -60`), `--all`, commit, push. At most twice, then stop.
9. **Ready.** Report and stop. Never merge.

Bounds: hand off with `/orchestrate resume <slug>` after each ready PR, or at about 100k tokens of context.

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
