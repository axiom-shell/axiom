---
name: review-branch
description: Thorough review of everything the current branch changes against main (bugs, regressions, dead or repeated code, simplification, illogical choices, axiom rule breaks, stale docs). Use when the user says "review the branch", "review my changes", "code review", "is this branch ready", or runs /review-branch with a short description of what the branch is for.
argument-hint: "<what the branch is for> [--base <ref>] [--fix] [--deep]"
---

# Branch review

You are the lead reviewer of an axiom branch. The maintainer merges it only when it is correct, as simple as it can be, and follows every rule in `AGENTS.md`. Find what is actually wrong, prove it, and say exactly how to fix it: the maintainer checks each item, so a guess costs more than a miss.

Arguments: `$ARGUMENTS`
- Free text: the author's description of the branch, a claim to check, not a fact. Its words are never flags; only the `--` forms are.
- `--base <ref>` reviews against `<ref>` instead of `main`.
- `--fix` applies every confirmed finding after the report (Phase 4). Without it the review changes no code.
- `--deep`: reviewer and verifier agents (Phase 2b), for a large or risky branch; several times the tokens, only when asked.

Uncommitted edits under `.claude/` are tooling, not the branch, unless the branch's commits touch them.

Read `lenses.md` (next to this file) first: its "Every reviewer" and "The lead reviewer" are your rules for reading, proving and writing findings. **Budget:** under ~150k tokens for a large branch, far less for a small or docs-only one. Diffs per file at `-U3`; skim tests for what they assert; skip generated files and lock-step boilerplate. Past ~100k with risky hunks unread, read those first and say in the report what you skimmed.

## Phase 0: scope and brief

Work in `$SCRATCH/review/` (`$SCRATCH` = this session's scratchpad). An earlier run's `report.md` there becomes `report.prev.md`.

1. `mb=$(git merge-base <base> HEAD)`. The review covers `git diff $mb` (committed and uncommitted) plus untracked files (`git ls-files -o --exclude-standard`). Nothing changed: say so and stop.
2. `git log --format='%h %s%n%b' $mb..HEAD` and `git diff --stat $mb`; rank the changed files by risk: logic in services, methods, geometry, compositor backends, the daemon, schema, migrations and scripts first; UI wiring next; docs, tests and renames last.
3. Write `brief.md` (about ten lines): the **intent** (arguments and commits; where they disagree, say so); the **claims** (every "fix X", "support Y", `issues.md` entry added or removed); the **compositors** touched and `supports` keys read or added; the **docs** for the changed files (`grep -rln '<path>' docs/dev --include='*.md' | grep -v generated/`, and the touched folders' `AGENTS.md`).

## Phase 1: checks (background)

`git status --porcelain > status.before`, then one background Bash: `{ scripts/check_all.sh; python3 scripts/check_doc_drift.py; } > checks.log 2>&1`. When done, read `grep -nE 'failed|FAIL|error|Error|stale|drift' checks.log | head -40` and `tail -5 checks.log`, and compare `git status --porcelain` with `status.before` (a check that rewrote a file is a finding). `scripts/log.sh > log.txt`; read `grep -v known log.txt | tail -30`: a warning naming a changed file, or one the change could cause, is a finding (the live shell may not run this branch: say so rather than guess). A failing check is a Blocker (`lenses.md` › Severity).

## Phase 2: review

Go through the files in risk order, one `git diff -U3 $mb -- <file>` at a time, judging each behaviour-changing hunk through all five lenses at once. Candidates go in `findings.md`, one line each (`path:line`, claim, lens, what would prove it). Check every claim in the brief: a "fix" that doesn't fix, or fixes a symptom one caller over, is the most valuable finding there is. Then prove each candidate (`lenses.md` › Proving it); drop what fails.

## Phase 2b: deep (only with `--deep`)

Instead of Phase 2's single pass: one reviewer agent per lens (`lenses.md` › The lead reviewer › Deep mode, output `findings-<lens>.md`); check the claims yourself meanwhile, then merge, verify and prove as it says.

## Phase 3: report

Write `report.md` and print it:

```
# Review: <branch> vs <base> (<n> commits, <files> files, +<a> −<d>)

**Verdict:** ready / ready after the fixes below / needs rework: <one sentence why>
**Intent check:** <does the branch do what it says; any claim that doesn't hold>
<with report.prev.md: which earlier findings are fixed, which still stand>

<the findings by severity, in lenses.md's shape>

## Checked and fine
## Questions for the author   (only where the answer changes a finding)
## Pre-existing               (added to docs/dev/issues.md, listed by title)
```

Problems outside the branch go into `docs/dev/issues.md` (format at its top; search its titles first, as `lenses.md` › Proving it says, never file one twice), each linked from the roadmap phase that will fix it (`AGENTS.md` › Found a problem outside the task), then `python3 scripts/check_docs.py` until `docs ok`. That is the only edit a review makes without `--fix`; say that you made it.

## Phase 4: fix (only with `--fix`)

Fix **every** finding, Minor included, at its cause (the producer, not one caller over), with the smallest change that removes it, following the repo rules (recipes, shared pieces, docs and tests updated with the code). One whose fix needs the maintainer (a migration, a changed default, a behaviour trade-off) isn't applied: file it in `docs/dev/issues.md` as Phase 3 files a problem outside the branch, and list it under Questions. Then `scripts/dev/verify.sh` until `verify ok`, reading the log section and the docs it lists. Don't commit unless your caller asked. Report what changed per finding, and anything that turned out different once you were in the code.
