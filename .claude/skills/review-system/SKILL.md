---
name: review-system
description: 'Deep review of one whole axiom system (compositor layer, a backend, backend parity, popouts, bar, modules, menus, config, theming, blur, lockscreen, greeter, launcher, …, or any feature): docs vs code, bugs on rarely taken paths, dead and repeated code, simpler shapes, rule breaks, seams. Use when the user says "review the X system", "audit X", "is X in good shape", or runs /review-system.'
argument-hint: "<system> [focus text] [--fix]"
---

# System review

You lead the review of one whole system of axiom, not a change: you list its files, split them into slices, hand them to `reviewer` agents, have one `architect` judge what they found, and report. **You never read the system's code yourself**: your context stays small, the reviewers look closely. Nothing is saved between reviews.

Arguments: `$ARGUMENTS`
- `<system>`: a name from `systems.md` (next to this file), or `feature:<name>` (`docs/dev/features/<name>.md`), `doc:<path>`, `files:<glob>`. Missing or unknown: list the names in `systems.md` and stop.
- Free text after it narrows the review to a concern; tell every reviewer. Its words are never flags.
- `--fix`: after the report, have the confirmed findings fixed (step 6). Without it nothing changes.

## 1. Scope

Read only the system's entry in `systems.md` (`sed -n '/^## <system>$/,/^## /p'`). Its files: each **Docs** entry's `> **Files:**` header (line 3 of the doc: `sed -n 3p`; globs and `{a,b}` allowed, a folder `dir/` means the files directly in it), plus **Extra**. Size them with `wc -l`; don't open them. A path matching nothing is a finding (a moved file or a bad pattern hides code). Note the **Mode**, **Checks** and **Seams**.

## 2. Slices

Group the files into slices of at most ~1500 lines, along the docs' boundaries: a file stays whole, a doc's files and their tests stay together. The docs go with the slice whose code they describe.

## 3. Reviewers, in parallel

Lenses: `bugs`+`edges` (and `security` for the `security` and `greeter` systems), `contract`+`tests`, `cleanup`+`deletion`+`design`, `rules`+`seams` (this folder's `lenses.md` and `../review-branch/lenses.md`). Per slice: one reviewer per group; a slice under ~400 lines gets one reviewer with all of them. With **Mode** `parity` or `collection`, one more reviewer builds that table across all the system's files (outlines only, `grep -n`), then reads the cells and outliers. At most ~8 reviewers in all: past that, merge lens groups (`cleanup`… with `rules`…, then all in one per slice) before merging slices.

Launch them all in one message (`subagent_type: reviewer`). Each brief:
- **System:** its name, scope line, the focus text if any, and its Checks (each reviewer verifies those its slice holds).
- **Slice:** its files and docs; the Seams, for the `seams` lens.
- **Lenses:** read `.claude/skills/review-branch/lenses.md` › Every reviewer, and the sections for each lens named (`bugs`, `cleanup`, `rules`, `design` there; the others in `.claude/skills/review-system/lenses.md`).
- Reply in the Reply shape, under 800 words; "Outside the slice" holds problems in other systems' files.

## 4. Judge

Merge the replies: one finding per cause, missing paths from step 1 included. Send them all, in one message, to one `architect`: "Judge each finding against its cited lines: confirmed (with the failing case), rejected (why), or unsure (what would settle it)." Keep the confirmed ones; list the unsure ones separately.

## 5. Report

```
# System review: <system>

**Verdict:** <one or two sentences: the state of the system, the biggest problem>
**Deletion:** <the deletion findings' titles with their line counts and the total; or "nothing found">
<parity or collection table, short, if the mode has one>

## Blockers / ## Major / ## Cleanups / ## Minor
<each confirmed finding: title, `path:line`, the case, the fix>

## Unsure          (what would settle each)
## Coverage        (the slices and the lenses each got; files left out and why)
## Outside the system (problems in other systems' files: title and `path:line`)
```

Outside the system is for the user only: those are never fixed here and never filed anywhere.

## 6. Fix (only with `--fix`)

Hand the confirmed findings to one `implementer`, the list as its spec: smallest change each, following the rules and recipes, docs and tests updated with the code; don't commit. A finding whose fix needs a behaviour decision (a changed default, a migration, a trade-off) isn't handed over: ask the user. Then a `checker` runs `scripts/dev/verify.sh`. Report per finding what changed and the check result.
