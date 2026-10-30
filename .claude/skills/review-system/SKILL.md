---
name: review-system
description: Deep review of one whole axiom system (compositor layer, a backend, backend parity, popouts, bar, modules, config, theming, blur, lockscreen, greeter, launcher, …, or any feature): docs vs code, bugs on rarely taken paths, dead and repeated code, simpler shapes, rule breaks, seams. Remembers each review so the next one only rereads what changed. Use when the user says "review the X system", "audit X", "is X in good shape", or runs /review-system.
argument-hint: "<system> [focus text] [--full] [--record] [--out <dir>] [--fix] [--deep]"
---

# System review

You are reviewing one whole system of axiom, not a change. The maintainer wants to know what is wrong in it, what is dead or repeated, and where it could be simpler, each item proven and with its fix: every finding becomes work, so a guess costs more than a miss.

Arguments: `$ARGUMENTS`
- `<system>`: a name from `systems.md` (next to this file), or `feature:<name>` (`docs/dev/features/<name>.md`), `doc:<path>`, `files:<glob>`. Missing or unknown: print `python3 .claude/skills/review-system/scope.py --list` and stop.
- Free text after it narrows the review to a concern. Its words are never flags; only the `--` forms are.
- `--full` ignores the last review and reviews everything.
- `--record` files the Blockers, Major and Cleanups in `docs/dev/issues.md` (Phase 6).
- `--out <dir>` (audits run in parallel): `--record`, deferred: change nothing in the tree; the report and the reviews file go to `<dir>`, and whoever started the audits files them all at once with `scope.py --apply <dir>…` (Phase 6).
- `--fix` fixes the confirmed findings after the report (Phase 6).
- `--deep` fans out agents (Phase 3): for a big system, only when asked.

Read `../review-branch/lenses.md` › Every reviewer and The lead reviewer first: your rules for reading, proving and writing findings. Work in `$SCRATCH/review-system/` (`$SCRATCH` = this session's scratchpad). **Budget:** under ~200k tokens in all. Deep reading is the risky parts of the deep set; everything else by outline (`grep -n 'func \|function \|property \|signal \|Connections\|Process\|Timer\|IpcHandler' <file>`). Past ~150k, stop opening files and say in Coverage what you only outlined.

## Phase 0: scope

1. `python3 .claude/skills/review-system/scope.py <system> > $SCRATCH/review-system/scope.txt` and read it: the docs, the code ranked by risk (size × churn × fix commits), files shared with other systems (`[also in: …]`: seams; outline them unless they're this system's core), tests and data, the last review and what changed since, and the open `issues.md` entries on these files (known: never report them again; say if the code now fixes one or makes it worse).
2. **Incremental by default.** With a last review (`.claude/reviews/<system>.md`) and no `--full`: read it; the deep set is the files changed since its commit, plus a recheck of each open finding (its `issues.md` entry gone means fixed). Nothing changed and nothing open: say so and stop.

## Phase 1: the contract

Read every doc the scope lists, in full, and the system's entry in `systems.md` (its Checks are the most valuable things to verify). Write `contract.md`: one line per behavioural statement and per Check, each with how to verify it (a grep, a function to read).

## Phase 2: mechanical

On the system's files, as greps (CI runs the `check_*` scripts: don't): the `rules` lens's unchecked breaks; dead members (each `function`/`property`/`signal`/Go func defined in the system, counted repo-wide with `grep -rnw <name> . --include=*.qml --include=*.go --include=*.py --include=*.sh --include=*.json | wc -l`: one hit is a candidate, then check name-loaded uses); `scripts/log.sh` lines naming the system's files.

## Phase 3: review

Read `lenses.md` (next to this file). For `parity` and `collection` modes, build their table first, then read its cells and outliers. Then down the risk ranking: each file in the deep set, its risky parts (state, processes, event handling, geometry, anything a Check or contract line points at) through all lenses at once, ticking off `contract.md` lines as you reach their code. Candidates go in `findings.md`, one line each (`path:line`, claim, lens, proof). Then the seams.

To settle a finding against a real compositor, use a nested one (`scripts/dev/nested.sh <sway|niri|hyprland>`), never the live session.

**`--deep`:** split the deep set into chunks of ≤ ~5k lines along the docs' boundaries, one reviewer agent each, given both lenses files, `contract.md`, its files and output path; do the seams and the parity/collection table yourself meanwhile (`../review-branch/lenses.md` › The lead reviewer › Deep mode).

## Phase 4: prove

Every candidate passes `../review-branch/lenses.md` › Proving it before it goes in the report, agents' ones included: the cited line re-read, every count and total recomputed, `issues.md` grepped for the same function or cause. Drop what fails.

## Phase 5: report

`report.md` (in `--out <dir>`, else in `$SCRATCH/review-system/`), printed too:

```
# System review: <system>  (full | incremental since <sha>)

**Verdict:** <one or two sentences: the state of the system, the biggest problem>
**Since last review:** <fixed / still open / new, when incremental>

<the findings by severity, in the lenses' shape>

## Contract
<the docs' statements that hold, briefly; those that don't are findings above>

## Coverage
Read deeply: <files> · Outlined: <files> · Skipped: <files, why>

## Outside the system
<problems in other systems' files, in the same entry shape>
```

## Phase 6: record or fix

- `--record`: `python3 .claude/skills/review-system/scope.py --apply $SCRATCH/review-system` files Blockers, Major, Cleanups and Outside the system (entries already in `issues.md` by title are skipped), links each under `docs/dev/roadmap.md` › "Found by the audits:", lists pairs of entries naming the same `path` (`symbol`), and runs `check_docs`. Settle each pair (one cause: merge into one entry; two fixes to one function: one entry with one fix) and each check_docs error, until `docs ok`.
- `--out <dir>`: nothing here; the caller runs `scope.py --apply` on every audit's dir at once (so pairs across audits show), then settles pairs and errors as above.
- Neither: file only Outside the system, by hand (`issues.md` format at its top, linked from the roadmap phase that fixes it).
- `--fix`: fix the confirmed findings, smallest change each, following the repo rules and recipes; skip and list any that need the maintainer's decision. `scripts/dev/verify.sh` until `verify ok`, reading the log section and the docs it lists; remove any `issues.md` entry a fix closes. Don't commit.

## Phase 7: the reviews file

Last, write `.claude/reviews/<system>.md` (`:` and `/` become `_`; with `--out`, `<dir>/review.md`, which `--apply` copies there), replacing the previous one. It is what the next review starts from: **only what is still true**.

```
# <system>
reviewed: <short sha of the code reviewed> <date>  (full | incremental since <sha>)

<the verdict, for the state after any fixes>

## Open findings
- <severity>: [<title>](../../docs/dev/issues.md#<anchor>)   (one line per recorded finding)
<unrecorded ones (Minor, or all without --record) in the lenses' shape; or "None.">

## Contract
<from the report: what holds, so the next review needn't re-derive it>

## Coverage
<from the report>

## History
- <date> <full | incremental>: <n> findings; <fixed in <sha> | recorded | left open>   (one line per review, earlier lines kept)
```

`reviewed:` stays the commit read, even after `--fix`, so the next incremental review rereads the fixes. The file is meant to be committed: say so, and leave committing to the user unless they asked.
