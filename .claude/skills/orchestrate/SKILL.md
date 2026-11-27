---
name: orchestrate
description: Runs every change to axiom (bug fix, alignment, improvement, feature) from request to a report ready for a pull request. Use when the user asks for a change or runs /orchestrate, or `resume <slug>`. Main session only; never from a subagent or from a skill it runs.
argument-hint: "<request> | align <description> | group <plan file> [--stack <k>] | resume <slug>"
---

# Orchestrate

You are the lead, in the main session: you size, plan, brief, gate, commit and write the report; you never push or open or edit a PR (the report says what to push). Agents read and write code.

Arguments: `$ARGUMENTS`
- Free text: the request, quoted verbatim into decisions.md.
- `align <description>`: an alignment request; step 2 runs `/align`.
- `group <plan file> [--stack <k>]`: run one stack of a plan file (`stacks.md`). `<plan file>` is an absolute path, or a file name in the plan files folder (› State). `--stack <k>` picks the k-th stack and is required when the plan has two or more; one run owns one stack.
- `resume <slug>`: continue a run: read state.md and decisions.md, `git -C <tree> status` and `log -3`, and the PR (`gh pr view <branch> --json number,comments`: its number goes into state.md, its answers become D; a stack: `stacks.md` › Resume); continue at Next.

Layouts: one file per hand-off in `.claude/templates/`; fill them, never restate them. Steps 1–3 are in `start.md`, 5–8 in `finish.md`, beside this file: read each before running any step it holds, never earlier. A `group` run, or its resume, reads `stacks.md` first; a run whose spec the architect splits into a stack reads it before the plan check.

## The lead

- **What you read.** Never source files or diffs: `--stat`/`--shortstat`, `new_names.py` output, reports, and check output (`tail`, `grep`). An unclear bug or claim goes to an `architect`.
- **Skills and agents.** Run skills with the Skill tool, each with `--tree <tree>` (a recipe skill gets it as the brief's `Tree:`), never by reading their files. Each role and round gets a fresh agent.
- **Briefs** are `.claude/templates/brief.md`, complete the first time. Quote decisions verbatim; add no step of your own.
- **A stopped agent** goes to an `architect`, or to the user if the decision is product.
- **Do nothing unasked:** no memory, CLAUDE.md or CLAUDE.local.md writes, PR comment edits, issues or standing rules.
- **"Was it checked?"** Answer from state.md, naming every `NOT RUN` and weak check.

## Questions

- Before relaying anything, reread decisions.md and the PR comments (`gh pr view <branch> --json comments`).
- Drop a question the request's own principle answers; record it as an R quoting the principle.
- Relay word for word, in one batch: product questions (defaults, behaviour users notice, migrations, takeovers) and every LOST Becomes row. Start nothing that depends on them.
- Your own questions use the codebase's names (schema key, UI label), never a nickname.
- Everything else you rule: an R in decisions.md with a one-line reason, restated in the report in plain technical terms, without R/D ids or anything quoted from a plan file (`.claude/templates/report.md` › Rulings).
- A default the request or a D already fixes goes under Defaults taken. Any other default is a question.
- User instructions go into decisions.md as D answers (verbatim, dated, where given).

## State

- **Folders**, from CLAUDE.local.md lines (a leading `~` is `$HOME`): plans `Plans folder:` (else `<main checkout>/.plans/`); worktrees `Worktrees folder:` (else `<main checkout>/.claude/worktrees/`); plan files `Plan files:` (none: `<plan file>` is an absolute path). `<main checkout>` is `git rev-parse --path-format=absolute --git-common-dir` less `/.git`. Each one outside the project, and any file the lead writes a status to, must be a working directory.
- **State folder** `<plans folder>/<slug>/` (a group run: `<plans folder>/<stem>/`, `<stem>-s<k>` with `--stack`, `<stem>` the plan file's name without `.md`): `state.md`, `decisions.md`, `spec.md` (`spec-<n>.md` per PR of a stack), `ledger.md`, `plan-check-<n>.md`, `fix-<source>-<n>.md` (source `gate<g>`, `review<r>` or `ci<c>`), `report.md` (`report-<n>.md` per PR of a stack), `census.md` (align). Update state.md after every step, and `Head:` after every commit. Delete it once its PR is merged (a stack: its top part, after `stacks.md` › Write-back).
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

## Steps

4. **Groups.** For each spec group:
   1. Brief (`Tree:`, `Base:` = state.md's Base) to a fresh `implementer`, or `/<recipe> "<the filled brief>"` when the group names a recipe.
   2. Read the implementer's report. Each acceptance check needs a PASS with evidence. FAIL, NOT RUN, weak or "by construction" is not done: a fresh implementer for it. It becomes a `LIVE:` line only on an architect's ruling that no test or log can reach it, and a nested check only on its ruling that one is necessary (CLAUDE.md › Working here). Log lines from another tree are not evidence.
   3. Re-tier check.
   4. `/keep-order gate --tree <tree> --state <state folder>`, and its Fix round (judged as in 4.2).
   5. Commit: `git -C <tree> add -A && git -C <tree> -c core.hooksPath=.githooks commit -F -`, ending with the session's attribution lines; set state.md's `Head:`.

Bounds: at about 150k tokens of context, hand off to a fresh context with `/orchestrate resume <slug>`.
