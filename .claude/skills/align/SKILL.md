---
name: align
description: Take an abstract description of a concept or job ("how surfaces fit into their screen", "zoom hosts", "config edit points", "the Shrunk to N% wording") and make every place in axiom that does it do it one way, under one name, through one shared piece. Run by `/orchestrate` step 2 for an alignment request (`/orchestrate align <description>`); typed without `--state`, it tells the user to run that and stops.
argument-hint: "<what to align, in words> --state <folder> --tree <path> [--scope <paths>]"
---

# Align

`keep-order` stops a branch from adding drift; `align` removes drift already in the codebase. Input is a description, not a file list: the copies of one job rarely share a name, which is why they were never merged.

Without `--state`, say "run `/orchestrate align <description>`" and stop. Alignment is axiom's top priority (`CLAUDE.md` › Working here), so the goal is convergence, not a list: one piece, one name, one pattern, every site using it.

Arguments: `$ARGUMENTS`
- Free text: the concept to align. It is a description to search by, not a symbol.
- `--state <folder>`: the state folder; `--tree <path>`: where every command runs (`cd <tree> && …`).
- `--scope <paths>`: limit the search (default: the whole tree).

## 1. Census

One `architect`, briefed from `.claude/templates/brief.md` (`Tree:`, `Base:`), writes `<folder>/census.md`: "Find every place in axiom that does this job: `<description>`. Search by what the code does, not only by name (`.claude/templates/ledger.md` › Where to search; also `backend/`, `docs/dev/` and `tests/`): the verbs and nouns of the job, the values it reads and writes, the units it works in, the call sites of every candidate, the schema and docs that describe it, the tests that pin it. For each site report: `path:line`, the symbol, its name, its inputs and output with units, how it differs from the others in behaviour (a real case, or 'none'), and its callers' count. Then: the sites that are the same job (one table), the ones that only look alike (and why they differ), and which existing site is the precedent: the one in the right layer (`CLAUDE.md` › Layering: decisions in `qml/components/methods/`, UI pieces in `qml/components/reusable/`), with a test, the most callers, the codebase's naming. No code changes. Under 800 words."

Nothing found beyond one site: report that and stop.

## 2. Ledger

`/keep-order plan --state <folder> --tree <tree>`. It reads `census.md`; the spec gets its Align section (`.claude/templates/spec.md`): the census table, **the one way** (the precedent, extended if needed, or a new methods helper or reusable piece when none is in the right layer: its name, signature and units, and the one pattern every call site uses), each site (calls the piece / deleted / kept, with the behaviour difference that keeps it), every behaviour change (a value off by a pixel, a wording, a default; each listed, never folded in), the tests (methods rows that pin the one way, parity rows that pin each converted site to it) and the order (commit groups, each passing `scripts/dev/verify.sh` alone: the shared piece and its tests, then the sites, then the docs).

## 3. Approve

Show the user: the census table (sites, names, how they differ), the one way, and the behaviour changes. Converging is a refactor the user owns; wait for a yes, or for the changes they want. Any listed behaviour change is a product choice: ask.

Then return to `/orchestrate` step 3.
