---
name: review-system
description: Deep review of one whole axiom system (compositor layer, a backend, backend parity, popouts, bar, modules, config, theming, blur, lockscreen, greeter, launcher, …, or any feature): docs vs code, bugs on rarely taken paths, dead and repeated code, simpler shapes, rule breaks, seams. Remembers each review so the next one only rereads what changed. Use when the user says "review the X system", "audit X", "is X in good shape", or runs /review-system.
argument-hint: "<system> [focus text] [--full] [--record] [--fix] [--deep]"
---

# System review

You are reviewing one whole system of axiom, not a change. The maintainer wants to know what is wrong in it, what is dead or repeated, and where it could be simpler, each item proven and with its fix. A review that pads the list with guesses is worse than a short one.

Arguments: `$ARGUMENTS`
- `<system>`: a name from `systems.md` (next to this file), or `feature:<name>` (`docs/dev/features/<name>.md`), `doc:<path>`, `files:<glob>`. Missing or unknown: print `python3 .claude/skills/review-system/scope.py --list` and stop.
- Free text after it narrows the review to a concern ("event stream recovery"). Words in it are never flags; only the `--` forms are.
- `--full` ignores the last review and reviews everything.
- `--record` adds the confirmed findings to `docs/dev/issues.md` after the report.
- `--fix` fixes the confirmed findings after the report (Phase 6).
- `--deep` fans out agents (Phase 3b): for a first review of a big system, only when asked.

## Budget

A review stays **under ~200k tokens in all**, done by you alone. Reading is what costs; spend it on the code where bugs live.
- `AGENTS.md` is already in your context. Never read it, a doc or a file twice.
- Command output to `$SCRATCH/review-system/` (`$SCRATCH` = this session's scratchpad), then read only what you need.
- Deep reading: the enclosing function (`grep -n` its bounds, `sed -n`), not whole files, except small ones or the system's core. Everything else by outline: `grep -n 'function \|property \|signal \|Connections\|Process\|Timer\|IpcHandler' <file>`.
- Tests and `.json` data: grep for what you need, never read whole. The schema: read the system's own files under `config/schema/` (`sections/<Section>.yaml`, `definitions/**/<Name>.yaml`), never the generated `config.schema.json`.
- Past ~150k, stop opening new files and say in Coverage what you only outlined.

## Phase 0: scope

1. `python3 .claude/skills/review-system/scope.py <system> > $SCRATCH/review-system/scope.txt` and read it: the docs, the code ranked by risk (size × churn × fix commits), files shared with other systems (`[also in: …]`: seams here, outline them unless they're this system's core), tests and data, the last review and what changed since, and the open `issues.md` entries on these files.
2. **Incremental by default.** If there's a last review (`.claude/reviews/<system>.md`) and no `--full`: read it; the deep pass covers only the files changed since its commit plus rechecking each of its open findings (still there? fixed?). Unchanged files get no reading beyond what a check needs. Nothing changed and nothing open: say so and stop.
3. Open `issues.md` entries are known: don't report them again; say if the code now fixes one or makes it worse.

## Phase 1: the contract

Read every doc the scope lists, in full (they're short), and the system's entry in `systems.md` (its Checks are the most valuable things to verify). Write `$SCRATCH/review-system/contract.md`: one line per behavioural statement the docs make and per Check, each with how to verify it (a grep, a function to read).

## Phase 2: mechanical, cheap

On the system's files only, as greps (CI already runs the `check_*` scripts: don't rerun them):
- the `rules` lens greps that apply, for what no check holds (`ConfigManager.config` outside services/readers, a `Timer` in UI, compositor names in gating);
- dead members: each `function`/`property`/`signal`/`readonly property` defined in the system, counted repo-wide (`grep -rnw <name> --include=*.qml --include=*.py --include=*.sh --include=*.json . | wc -l`): one hit is a candidate (check name-loaded uses before reporting);
- `scripts/log.sh` lines naming the system's files.

## Phase 3: review

Read `lenses.md` once. For `parity` and `collection` modes, do what their lens says first (the table), then read the cells and outliers.

Then go down the risk ranking: for each file in the deep set, read its risky parts (state, processes, event handling, geometry, anything a Check or contract line points at) through all lenses at once. Verify each `contract.md` line as you reach its code; tick it off. Keep candidates in `$SCRATCH/review-system/findings.md` (one line each: `path:line`, claim, lens, what proves it). Then grep the system's public members from outside it (seams lens).

**One helper agent at most**, for a question that needs a lot of reading (e.g. "do all 40 users of X use it as the docs say?"): give it the exact question and files, ask for under 300 words with `path:line` evidence, no edits.

To settle a finding against a real compositor (does sway accept this line, does niri send that event), use a nested one through `scripts/dev/nested.sh <sway|niri|hyprland>` (scratch folders, its own socket), never the live session and never one you start by hand.

### Phase 3b: deep (only with `--deep`)

Split the deep set into chunks of ≤ ~5k lines along the docs' boundaries; one `general-purpose` Agent per chunk, all in one message, each given "Every reviewer" from `../review-branch/lenses.md`, this `lenses.md`, `contract.md`, its file list and output path. Do the seams and parity/collection table yourself meanwhile. Then verifier agents (about six findings each) told to refute each finding: `CONFIRMED` / `PLAUSIBLE` / `REFUTED` with evidence, no edits. Under ten agents in all.

## Phase 4: verify

Try to prove each candidate false before it goes in the report: is the path reachable, handled elsewhere, the "dead" code reached by name, the rule actually stated, the simpler shape keeping every behaviour? Drop what fails; mark `PLAUSIBLE` what only running the shell can settle, keeping those only at major or above.

## Phase 5: report

Print the report and save it to `$SCRATCH/review-system/report.md`:

```
# System review: <system>  (full | incremental since <sha>)

**Verdict:** <one or two sentences: the state of the system, the biggest problem>
**Since last review:** <fixed / still open / new, when incremental>

## Blockers   (wrong behaviour users hit, safety or security rules broken)
## Major      (bugs on rarer paths, contract broken, rule breaks the checks miss, design that will bite)
## Cleanups   (dead code, duplication, simpler shapes: each with the simpler version)
## Minor      (misleading names, comments, docs)

### <n>. <claim>  `path:line`
<what is wrong and the concrete scenario>
**Fix:** <the change; code when short>

## Contract
<docs statements that hold, briefly; those that don't are findings above>

## Coverage
Read deeply: <files> · Outlined: <files> · Skipped: <files, why>

## Outside the system
<problems found in other systems' files>
```

With `--record`, add the Blockers, Major and Cleanups to `docs/dev/issues.md` in its format (`Found:` "while reviewing the <system> system"). Problems outside the system go in `issues.md` whatever the flags, as `AGENTS.md` asks. Either way, grep `issues.md` for the files and the problem first: never add an entry that's already there.

## Phase 6: fix (only with `--fix`)

Fix the confirmed findings, smallest change each, following the repo rules and recipes; skip and list any that need the maintainer's decision. Then `scripts/dev/verify.sh` until `verify ok`, read the log section and the docs it lists; remove any `issues.md` entry the fix closes. Don't commit.

## Phase 7: the reviews file

Last, write `.claude/reviews/<system>.md` (`:` and `/` in the name become `_`), replacing the previous one. It is what the next review starts from, not a copy of the report: **only what is still true**. A fixed finding leaves it (git history has the fix); one that is still open stays in full, so the next review can recheck it without this one.

```
# <system>
reviewed: <short sha of the code reviewed> <date>  (full | incremental since <sha>)

<the verdict, rewritten for the state after any fixes>

## Open findings
### <n>. <claim>  `path:line`
<the finding as in the report, with its Fix>
(or "None.")

## Contract
<from the report: what holds, so the next review needn't re-derive it>

## Coverage
<from the report>

## History
- <date> <full | incremental>: <n> findings; <fixed in <sha> | recorded in issues.md | left open: numbers>
  (one line per review; keep the earlier lines)
```

`reviewed:` stays the commit the review read, even after `--fix`: the next incremental review then rereads the fixes too. The file is meant to be committed: say so, and leave committing to the user unless they asked for it.
