---
name: align
description: Take an abstract description of a concept or job ("how surfaces fit into their screen", "zoom hosts", "config edit points", "the Shrunk to N% wording") and make every place in axiom that does it do it one way, under one name, through one shared piece. Use when the user says "align X", "make X consistent", "one way of doing X", "unify X", "these should all work the same", or runs /align with a description.
argument-hint: "<what to align, in words> [--scope <paths>] [--fix]"
---

# Align

`keep-order` stops a branch from adding drift; `align` removes drift already in the codebase. Input is a description, not a file list: the copies of one job rarely share a name, which is why they were never merged.

You lead: agents read the code, you read their reports. Alignment is axiom's top priority (`CLAUDE.md` › Working here), so the goal is convergence, not a list: one piece, one name, one pattern, every site using it.

Arguments: `$ARGUMENTS`
- Free text: the concept to align. It is a description to search by, not a symbol.
- `--scope <paths>`: limit the search (default: the whole tree).
- `--fix`: after the user approves the plan, build it.

## 1. Census

One `architect`: "Find every place in axiom that does this job: `<description>`. Search by what the code does, not only by name: the verbs and nouns of the job, the values it reads and writes, the units it works in, the call sites of every candidate, the schema and docs that describe it, the tests that pin it (`qml/`, `backend/`, `qml/config/schema/`, `docs/dev/`, `tests/`). For each site report: `path:line`, the symbol, its name, its inputs and output with units, how it differs from the others in behaviour (a real case, or 'none'), and its callers' count. Then: the sites that are the same job (one table), the ones that only look alike (and why they differ), and which existing site is the precedent: the one in the right layer (`CLAUDE.md` › Layering: decisions in `qml/components/methods/`, UI pieces in `qml/components/reusable/`), with a test, the most callers, the codebase's naming. No code changes. Under 800 words."

Nothing found beyond one site: report that and stop.

## 2. Target

The same architect (or a fresh one with the census) writes the target as a ledger (`.claude/skills/keep-order/SKILL.md` › The ledger) at `<plans dir>/align-<slug>-ledger.md` (the folder the user keeps plans in; never inside the repo), plus:
- **The one way**: the shared piece (the precedent, extended if needed, or a new methods helper or reusable piece when none is in the right layer), its name, signature and units; the one pattern every call site uses.
- **Each site**: what it becomes (calls the piece / deleted / kept, with the behaviour difference that keeps it).
- **Behaviour changes**: every case where converging changes what users see (a value off by a pixel, a wording, a default). Each one is listed, never folded in silently.
- **Tests**: the methods test rows that pin the one way, and the parity rows that pin each converted site to it (`CLAUDE.md`: "a new case is a helper rule plus a test row").
- **Order**: commit groups, each passing `scripts/dev/verify.sh` alone: the shared piece and its tests first, then the sites, then the docs (one home for the fact, others link to it).

## 3. Approve

Show the user: the census table (sites, names, how they differ), the one way, and the behaviour changes. Converging is a refactor the user owns; wait for a yes, or for the changes they want. Any listed behaviour change is a product choice: ask.

## 4. Build (with `--fix` or after the yes)

In a worktree, never the user's checkout. Per commit group, a fresh `implementer` with the target as its spec ("the ledger at `<path>` is binding; anything it doesn't cover is a stop"), then `/keep-order gate` on that group. After the last group: `/keep-order audit`, then `/review-branch`, then a PR whose body carries the census table and the behaviour changes.

## 5. Report

```
# Align: <description>
**Sites:** <n> doing one job (<m> only look alike)
**One way:** <piece, path> · **Pattern:** <one line>
## Sites            (path:line | name | becomes)
## Behaviour changes (each, and the user's answer)
## Done / next      (commits or the plan path; PR link)
```
