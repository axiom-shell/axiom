---
name: review-system
description: Deep review of one whole axiom system (compositor layer, a backend, backend parity, popouts, bar, modules, config, theming, blur, lockscreen, greeter, launcher, …, or any feature): docs vs code, bugs on rarely taken paths, dead and repeated code, simpler shapes, rule breaks, seams. Use when the user says "review the X system", "audit X", "is X in good shape", or runs /review-system.
argument-hint: "<system> [focus text] [--fix] [--deep]"
---

# System review

You are reviewing one whole system of axiom, not a change. The maintainer wants to know what is wrong in it, what is dead or repeated, and where it could be simpler, each item proven and with its fix: every finding becomes work, so a guess costs more than a miss.

Arguments: `$ARGUMENTS`
- `<system>`: a name from `systems.md` (next to this file), or `feature:<name>` (`docs/dev/features/<name>.md`), `doc:<path>`, `files:<glob>`. Missing or unknown: list the names in `systems.md` and stop.
- Free text after it narrows the review to a concern. Its words are never flags; only the `--` forms are.
- `--fix` fixes the confirmed findings after the report (Phase 6).
- `--deep` fans out agents (Phase 3): for a big system, only when asked.

Read `../review-branch/lenses.md` › Every reviewer and The lead reviewer first: your rules for reading, proving and writing findings. Your work folder is `$SCRATCH/review-system/` (`$SCRATCH` = this session's scratchpad); every file below goes there. **Budget:** under ~200k tokens in all. Deep reading is the risky parts of the deep set; everything else by outline (`grep -n 'func \|function \|property \|signal \|Connections\|Process\|Timer\|IpcHandler' <file>`). Past ~150k, stop opening files and say in Coverage what you only outlined.

## Phase 0: scope

From the system's entry in `systems.md`, list its files: each **Docs** entry's `> **Files:**` header gives the code (globs and `{a,b}` allowed; a folder `dir/` means the files directly in it), **Extra** adds more. A path matching nothing is a finding (a moved file or a bad pattern hides code: find the files it meant and review them too). Rank the files by risk (size, `git log --oneline -- <file> | wc -l`, fix commits), and note files shared with other systems (seams: outline them unless they're this system's core). Also note the tests and data.

## Phase 1: the contract

Read every doc the scope lists, in full, and the system's entry in `systems.md` (its Checks are the most valuable things to verify). Write `contract.md`: one line per behavioural statement and per Check, each with how to verify it (a grep, a function to read).

## Phase 2: mechanical

On the system's files, as greps (CI runs the `check_*` scripts: don't): the `rules` lens's unchecked breaks; dead members (each `function`/`property`/`signal`/Go func defined in the system, counted repo-wide with `grep -rnw <name> . --include=*.qml --include=*.go --include=*.py --include=*.sh --include=*.json | wc -l`: one hit is a candidate, then check name-loaded uses); `scripts/log.sh` lines naming the system's files.

## Phase 3: review

Read `lenses.md` (next to this file). For `parity` and `collection` modes, build their table first, then read its cells and outliers. Then down the risk ranking: each file in the deep set, its risky parts (state, processes, event handling, geometry, anything a Check or contract line points at) through all lenses at once, ticking off `contract.md` lines as you reach their code. Candidates go in `findings.md`, one line each (`path:line`, claim, lens, proof). Then the seams.

To settle a finding against a real compositor, use a nested one (`scripts/dev/nested.sh <sway|niri|hyprland>`), never the live session.

**`--deep`:** split the deep set into chunks of about 8–10k lines along the docs' boundaries, one reviewer agent each, given both lenses files (the deletion lens included), `contract.md`, its files and output path; do the seams and the parity/collection table yourself meanwhile (`../review-branch/lenses.md` › The lead reviewer › Deep mode).

## Phase 4: prove

Every candidate passes `../review-branch/lenses.md` › Proving it before it goes in the report, agents' ones included: the cited line re-read, every count and total recomputed, the other findings searched for the same function or cause. Drop what fails.

## Phase 5: report

`findings.md`, printed too:

```
# System review: <system>

**Verdict:** <one or two sentences: the state of the system, the biggest problem>
**Deletion pass:** <its findings' titles with their line counts and the total; or "nothing found" and what was checked>

<the findings by severity, in the lenses' shape>

## Contract
<the docs' statements that hold, briefly; those that don't are findings above>

## Coverage
Read deeply: <files> · Outlined: <files> · Skipped: <files, why>

## Outside the system
<problems in other systems' files, in the same entry shape>
```

## Phase 6: fix

Without `--fix` the review changes nothing: the report is the result, for the user to act on.

- `--fix`: fix the confirmed findings, smallest change each, following the repo rules and recipes; skip and list any that need the maintainer's decision. `scripts/dev/verify.sh` until `verify ok`, reading the log section and the docs it lists. Don't commit.
