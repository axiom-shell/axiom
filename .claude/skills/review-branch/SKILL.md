---
name: review-branch
description: Thorough review of everything the current branch changes against main (bugs, regressions, dead or repeated code, simplification, illogical choices, axiom rule breaks, stale docs). Use when the user says "review the branch", "review my changes", "code review", "is this branch ready", or runs /review-branch with a short description of what the branch is for.
argument-hint: "<what the branch is for> [--base <ref>] [--fix]"
---

# Branch review

You lead the review: you split the branch into slices, hand them to `reviewer` agents, have one `architect` judge what they found, and report. **You never read the diff yourself beyond `--stat`**: your context stays small, the reviewers look closely.

Arguments: `$ARGUMENTS`
- Free text: what the branch is for. It's a claim to check, not a fact; its words are never flags.
- `--base <ref>`: review against `<ref>` instead of `main`.
- `--fix`: after the report, have the confirmed findings fixed (step 6). Without it nothing changes.

## 1. Scope

- `mb=$(git merge-base <base> HEAD)`; `git diff --stat $mb` (committed and uncommitted, the same as `git diff <base>...HEAD --stat` plus the working tree), `git ls-files -o --exclude-standard` for new files, and `git log --oneline $mb..HEAD` for the commits' own account of the purpose. Nothing changed: say so and stop.
- Uncommitted edits under `.claude/` are tooling, not the branch, unless its commits touch them.
- Leave out generated files (`docs/dev/generated/`, `docs/dev/config/`, `qml/config/i18n/*.json`, `qml/config/json/config.schema.json`, `qml/config/themes/template/`) and pure renames.
- The purpose: the arguments, plus the commit subjects. Where they disagree, tell the reviewers both.

## 2. Slices

Group the files into slices of at most ~400 changed lines (the `--stat` counts):
- A file stays whole, whatever its size (a big one is a slice of its own).
- Related files go together: a QML file with its `schema.yaml`, its test and its doc; a service with its reader; a Go package with its tests.
- Docs-only changes form their own slice.

## 3. Reviewers and checks, in parallel

Lenses (`lenses.md` next to this file): `bugs`, `regressions`, `cleanup`, `rules`, `design`. Per slice:
- a code slice over ~150 lines: three reviewers, lenses `bugs`+`regressions`, `cleanup`+`design`, `rules`;
- a smaller code slice: one reviewer, all five lenses;
- a docs-only slice: one reviewer, `design` (are the docs true to the code, and complete) and `rules` (do the files, members and steps they name exist and agree).

At most ~8 reviewers in all: past that, merge lenses (`cleanup`+`design`+`rules` in one, then everything in one per slice) before merging slices.

Launch them all in one message (`subagent_type: reviewer`), plus one `checker` running `scripts/dev/verify.sh --all` (a failing check is a Blocker). Each reviewer's brief:
- **Purpose:** the branch's purpose and its claims ("fixes X", "supports Y").
- **Slice:** its files, read with `git diff <mb> -- <files>` (new files in full), and the base, `<mb>`.
- **Lenses:** read `.claude/skills/review-branch/lenses.md` › Every reviewer and › `<lens>` for each lens named.
- Look only at your slice's changes, and what they call; reply in the lenses file's Reply shape, under 600 words.

## 4. Judge

Merge the replies: one finding per cause (the same line or function from two lenses is one), the checker's failures as Blockers. Send them all, in one message, to one `architect`: "Judge each finding against its cited lines: confirmed (with the failing case), rejected (why), or unsure (what would settle it)." Keep the confirmed ones; list the unsure ones separately with what would settle them.

## 5. Report

```
# Review: <branch> vs <base> (<n> commits, <files> files, +<a> −<d>)

**Verdict:** ready / ready after the fixes below / needs rework: <one sentence why>
**Purpose check:** <does the branch do what it says; any claim that doesn't hold>

## Blockers / ## Major / ## Cleanups / ## Minor
<each confirmed finding: title, `path:line`, the case, the fix>

## Unsure            (what would settle each)
## Outside the branch (problems the reviewers saw that the branch didn't cause: title and `path:line`)
```

Outside the branch is for the user only: those are never fixed here and never filed anywhere.

## 6. Fix (only with `--fix`)

Hand the confirmed findings to one `implementer`, the list as its spec: fix each at its cause with the smallest change, following the rules and recipes, docs and tests updated with the code; don't commit. A finding whose fix needs a behaviour decision (a changed default, a migration, a trade-off) isn't handed over: ask the user. Then a `checker` runs `scripts/dev/verify.sh`. Report per finding what changed and the check result.
