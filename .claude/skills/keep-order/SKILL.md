---
name: keep-order
description: Keep a change aligned with the axiom codebase - no duplicate code, existing functions reused, one name and one pattern per concept - from plan to PR. Use when the user says "keep order", "keep it aligned", "no duplicates", "check consistency", "does this match the codebase", before building any feature bigger than a small edit (plan), after each implementer group (gate), and before opening or updating a PR (audit). Runs /keep-order plan|gate|audit.
argument-hint: "plan <plan file> | gate [--base <ref>] [--ledger <file>] | audit [--base <ref>] [--ledger <file>] [--fix]"
---

# Keep order

Alignment with the codebase is axiom's top priority, above speed and above scope: a change reuses what axiom already has, names things the way axiom already names them, and does each job one way. Agents drift when nothing pins this down: each fresh implementer invents its own names, copies a piece it didn't find, and writes its edit site its own way, and a review split into slices can't see a copy spread across three files. This skill pins it down before code (the **ledger**), checks it after every group of code (the **gate**), and checks the whole branch before a PR (the **audit**).

You lead: agents read the code, you read their reports and `scripts/dev/new_names.py` output, never diffs.

Arguments: `$ARGUMENTS`. The first word is the mode.

## The ledger

One file beside the plan, `<plan name>-ledger.md` (or `--ledger <file>`), owned by the architect, updated only by an architect's ruling. It is the implementers' Shape (`.claude/agents/architect.md` › Writing a spec) for the whole feature, so every group builds against the same names:

```
# <feature>: ledger
## Reuse        job | existing piece (path:line) | how it is used (called / extended / referenced by $ref)
## Names        name | kind | file | type and unit | meaning (one line) | status (planned / built)
## Patterns     kind of site (config write, helper call, form hook, …) | the one way it is written (path:line of the precedent)
## Precedents   new file or member | the existing one it mirrors (path)
## Strings      user string | reused from (path:line) or new
## Not to build what looks needed but already exists, with where (a near copy someone will be tempted to write)
```

## plan `<plan file>`

Before any code. One `architect`: "Read the plan `<file>` and the code it touches. Write its ledger to `<ledger path>` in the shape below (paste the shape). For every job the plan needs, search for what already does it: `qml/components/methods/`, `qml/components/reusable/`, `docs/dev/core/shared-ui-pieces.md`, the readers and services of the areas, the schema's shared definitions, the tests' helpers, the existing `I18n.tr` strings; by verb and by noun. "None" comes with the grep. Every name the plan uses or implies goes in Names with its unit; a name the codebase already uses for another thing is renamed; one concept gets one name everywhere. Report: counts per section, every plan name you renamed and why, every plan step that would have duplicated an existing piece."

Then give the plan's implementers the ledger as part of their brief ("the ledger at `<path>` is binding: its names, units, reuse and patterns; anything it doesn't cover is a stop"). A plan that changes after the ledger gets its ledger updated by the architect first.

No plan (a small change): the architect's spec carries its own Shape; no ledger file.

## gate

After each implementer group or fix round, before the next one starts, so drift never compounds.
1. Run `python3 scripts/dev/new_names.py --base <base>` (base: the commit the group started from; `--files` for a group's own files).
2. Compare it with the ledger yourself, by name only: every added public name must be in Names with the same name; every `also defined` must be a reuse the ledger names. Also compare the implementer's **Names added** report.
3. Anything else goes to one `architect` with the list: "Rule on each name: in ledger / rename to `<x>` / replace with the existing `<path:line>` / add to the ledger (why it is new). For each `also defined`: same concept (then one of the two goes) or a clash (rename). Read only the cited lines and the existing piece." It updates the ledger with its rulings.
4. Rulings that change code go to a **fresh** `implementer` as a fix list, then `scripts/dev/verify.sh`. Only then does the next group start.

Nothing unlisted is "fine for now": an unlisted name is a ruling, a copy is a fix.

## audit

Before opening or updating a PR, and on any branch on request (no ledger: the architect first writes one from the branch's code, in the shape above, and lists every place the branch disagrees with itself or the codebase).
1. Two `reviewer`s in one message, both over the **whole branch**, never slices, each reading `.claude/skills/review-branch/lenses.md` › Every reviewer and › consistency:
   - **code**: Duplicates, Names, Patterns, Decisions, Schema and Ledger from the lens, starting from `new_names.py --base <mb>`;
   - **words**: User strings and docs from the lens: every new `I18n.tr` string against the existing ones, every UI label a schema description or doc names against the QML, one home per fact.
   Each gets the purpose, the base `<mb>` and the ledger path.
2. One `architect` judges the merged findings (`.claude/agents/architect.md` › Judging findings).
3. Report:
   ```
   # Keep order: <branch> vs <base>
   **Aligned:** yes / no: <n> to fix
   ## To fix   (each: what, both locations, which is the precedent, the fix)
   ## Ledger    (rulings added)
   ## Unsure    (what would settle each)
   ```
4. `--fix`: confirmed findings to a fresh `implementer` as a fix list file, then verify, then `gate` on the fix. A finding whose fix changes behaviour users notice goes to the user instead.

A branch with an open audit finding is not ready: `review-branch` won't say "ready" with a consistency finding open.

## Rules for every brief this skill writes

- Quote the ledger's lines; never paraphrase a name.
- Fix rounds use a fresh implementer with a fix-list file, never a resumed one.
- Consistency findings are Major. They are never deferred, filed for later or traded for speed.
