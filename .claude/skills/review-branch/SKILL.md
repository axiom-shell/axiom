---
name: review-branch
description: Thorough review of everything the current branch changes against main (bugs, regressions, dead or repeated code, simplification, illogical choices, axiom rule breaks, stale docs). Use when the user says "review the branch", "review my changes", "code review", "is this branch ready", or runs /review-branch with a short description of what the branch is for.
argument-hint: "<what the branch is for> [--base <ref>] [--fix] [--deep]"
---

# Branch review

You are the lead reviewer of an axiom branch. The maintainer wants it merged only when it is correct, as simple as it can be, and follows every rule in `AGENTS.md`. Your job is to find what is actually wrong, prove it, and say exactly how to fix it. A review that pads the list with guesses is worse than a short one: the maintainer has to check each item.

Arguments: `$ARGUMENTS`
- Free text is the author's description of what the branch is for. It is a claim to check, not a fact. Words in it ("fix the popout", "deep blur") are never flags: only the `--` forms below are.
- `--base <ref>` reviews against `<ref>` instead of `main`.
- `--fix` applies every confirmed finding, Minor included, after the report (Phase 4). Without it the review changes no code.
- `--deep` uses reviewer and verifier agents (Phase 2b), for a large or risky branch. Several times the tokens: only when asked.

Uncommitted edits under `.claude/` (skills, settings) are tooling, not the branch: leave them out unless the branch's commits touch them.

## Token budget

A normal review stays **under ~150k tokens in all**, so it is done by you alone, in this context. What costs tokens is reading: spend it on the code where bugs live, not on what tools already checked or what you already have.
- `AGENTS.md` is already in your context. Never read it, a doc, or a file twice.
- Command output goes to a file in `$SCRATCH/review/`; read only the part you need (`grep`, `tail`, `sed -n`).
- Diffs at `-U3`, per file. Skip generated files entirely (`docs/dev/config/`, `docs/dev/generated/`, `config/i18n/`, `config/themes/template/`) and lock-step boilerplate; skim tests for what they assert.
- Context around a hunk: the enclosing function (`grep -n` its bounds, `sed -n`), callers via `grep -rn … | head -30`. A whole file only when it's small or is the heart of the change.
- Docs: outline first (`grep -n '^###'`), then the one relevant section.
- If you notice you're past ~100k with risky hunks still unread, prioritise them and say in the report what you skimmed.

## Phase 0: scope and brief

Work in `$SCRATCH/review/` (`$SCRATCH` = this session's scratchpad directory). If a `report.md` from an earlier run is there, move it to `report.prev.md`.

1. `mb=$(git merge-base <base> HEAD)`. The review covers `git diff $mb` (committed **and** uncommitted work) plus untracked files (`git ls-files -o --exclude-standard`). Nothing changed: say so and stop.
2. `git log --format='%h %s%n%b' $mb..HEAD` and `git diff --stat $mb`. From these, rank the changed files by risk: logic in services, methods, geometry, compositor backends, schema/migrations and scripts first; plain UI wiring next; docs, tests and mechanical renames last.
3. Write a short `brief.md` (ten lines or so, for you and any agent): the **intent** (arguments + commits; where they disagree, say so), the **claims** (every "fix X", "support Y", `issues.md` entry added or removed: each gets checked), the **compositors** touched and `CompositorManager.supports` keys read or added, and the **docs** for the changed files (`grep -rln '<path>' docs/dev --include='*.md' | grep -v generated/` and the touched dirs' `AGENTS.md`).

## Phase 1: mechanical checks (background)

`git status --porcelain > status.before`, then one background Bash: `{ scripts/check_all.sh --no-docs; python3 scripts/gen_docs.py --check; python3 scripts/check_doc_drift.py; } > checks.log 2>&1`. When it finishes read only `grep -nE 'failed|FAIL|error|Error|stale|drift' checks.log | head -40` and `tail -5 checks.log`; compare `git status --porcelain` to `status.before` (a check that rewrote a file is a finding). Also `scripts/log.sh > log.txt` and read the lines not marked `(known: …)` (`grep -v known log.txt | tail -30`): a warning naming a changed file, or one the change could cause, is a finding. The shell may not have reloaded the latest state; say so rather than guess.

Every failing check is a blocker. Don't spend reading on what the checks cover (format, lint, structure, i18n keys, generated docs).

## Phase 2: review

Read `lenses.md` (next to this file) once. Then go through the files in risk order, one `git diff -U3 $mb -- <file>` at a time, and judge each behaviour-changing hunk through all five lenses at once (bugs, regressions, cleanup, rules, design), reading context as the budget allows. Keep candidate findings in `findings.md` as you go (one line each: `path:line`, claim, lens, what would prove it).

Check every **claim** from the brief against the code: a "fix" that doesn't fix, or fixes a symptom one caller over, is the most valuable finding there is.

Then verify each candidate before it goes in the report: try to prove it false (is the path reachable, is it handled elsewhere, does the "dead" code have a caller loaded by name, does AGENTS.md actually state the rule, does the simpler version keep every behaviour). Drop what fails; mark `PLAUSIBLE` what only running the shell can settle, keeping those only at major or above.

**One helper agent at most**, and only for a question that needs a lot of reading you'd otherwise do yourself (e.g. "does anything still depend on X's old behaviour across these 15 callers?"). Give it the exact question, the files, and "answer in under 300 words with `path:line` evidence; change no files".

## Phase 2b: deep (only with `--deep`)

Instead of Phase 2's single pass: launch one `general-purpose` Agent per lens from `lenses.md` in a single message (the "Every reviewer" contract + that lens + paths to `brief.md` and the output file `findings-<lens>.md`), and do the claims check yourself while they run. Merge and dedupe by root cause, then launch verifier agents (about six findings each, grouped by file) told to refute each finding and answer `CONFIRMED` / `PLAUSIBLE` / `REFUTED` with evidence, changing no files. Stay under ten agents.

## Phase 3: report

Write `report.md` and print it. Order by severity, then file. Nothing in it the maintainer can't act on.

```
# Review: <branch> vs <base> (<n> commits, <files> files, +<a> −<d>)

**Verdict:** ready / ready after the fixes below / needs rework: <one sentence why>
**Intent check:** <does the branch do what it says; any claim that doesn't hold>

## Blockers        (wrong behaviour, regressions, failing checks, safety rules broken)
## Major           (bugs on a less common path, rule breaks the checks miss, design that will bite)
## Cleanups        (dead code, duplication, simpler shape: each with the simpler version)
## Minor           (naming, comments or docs that mislead, small inconsistencies)

Each finding:
### <n>. <claim in a few words>  `path/File.qml:123`
<what is wrong, and the concrete scenario: the input, state or compositor, what happens, what should>
**Fix:** <the change, as code when it's short>

## Checked and fine
<a few lines: risky things you looked at and found sound, and anything you only skimmed>

## Questions for the author
<only where the intent can't be read from the code and the answer changes a finding>

## Pre-existing problems
<problems found outside the branch's changes: added to docs/dev/issues.md in its format, listed here by title>
```

If `report.prev.md` exists, add a line under the verdict: which earlier findings are now fixed, which still stand.

Adding the pre-existing problems to `docs/dev/issues.md` (its format is at its top; check it doesn't already have them) is the only edit a review makes without `--fix`. Say that you did it.

## Phase 4: fix (only with `--fix`)

Apply **every** finding, Minor included: a Minor one is fixed as properly as a Blocker, at its cause (the producer, not one caller over), never left as a note. Make the smallest change that removes the cause, following the repo rules (recipes, shared pieces, docs and tests updated with the code). A finding whose fix needs a decision from the maintainer (a migration, a changed default, a behaviour trade-off) isn't applied: add it to `docs/dev/issues.md` in its format and list it under Questions. Then `scripts/dev/verify.sh` until `verify ok`, read the log section and the docs it lists. Don't commit. Report what changed per finding, and anything that turned out different once you were in the code.
