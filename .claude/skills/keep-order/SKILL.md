---
name: keep-order
description: Keep a change aligned with the axiom codebase - no duplicate code, existing functions reused, one name and one pattern per concept - from plan to PR. Use when the user says "keep order", "keep it aligned", "no duplicates", "check consistency", "does this match the codebase", before building any feature bigger than a small edit (plan), after each implementer group (gate), and before opening or updating a PR (audit). Runs /keep-order plan|gate|audit.
argument-hint: "plan --state <folder> --tree <path> | gate --tree <path> (--state <folder> | --base <ref>) | audit --state <folder> --tree <path> [--fix]"
---

# Keep order

Alignment with the codebase is axiom's top priority: the **ledger** (`.claude/templates/ledger.md`) pins names, reuse and patterns before code, the **gate** checks every group after it, the **audit** checks the whole branch before a PR. Nothing unlisted is "fine for now": an unlisted name is a ruling, a copy is a fix.

You lead: you read agents' reports and `new_names.py` output, never diffs (`/orchestrate` › The lead).

Arguments: `$ARGUMENTS`. The first word is the mode. `--tree` is where every command runs (default: `git rev-parse --show-toplevel`); git as `git -C <tree>`, the rest as `cd <tree> && …`. `--state` is the state folder, always a folder: `ledger.md`, the spec file state.md's `Spec:` names (default `spec.md`) and `state.md` (`.claude/templates/state.md`) are read from it. Every brief is `.claude/templates/brief.md`, with `Tree:` and `Base:`.

## plan

Before any code. One `architect` writes `spec.md` and `ledger.md` in the state folder (a stack: one `spec-<n>.md` per part and one ledger) from `decisions.md` (`.claude/templates/decisions.md`) and `census.md` when present. It confirms or raises the tier, and proposes a stack split when one PR would exceed what `/review-branch` covers in one review (~6 slices).

Open questions go to the user word for word, and nothing starts until they are answered. Implementers' briefs quote the ledger's lines; a plan that changes after the ledger gets its ledger updated by the architect first.

## gate

After each implementer group or fix round, before the next starts. Base is state.md's `Head:` (the last group commit); without `--state`, `--base`.
1. In the tree: `git -C <tree> diff --name-only <base>` plus untracked files, and `cd <tree> && python3 scripts/dev/new_names.py --base <base>`.
2. Compare the names with the ledger by name only: every added public name is in Names with the same name; every `also defined` is a reuse the ledger names. Also compare the implementer's **Names added**. Without a state folder: against Names added and the fix list only.
3. With `--state` only: files outside the spec's Files, and files the implementer's **Changed pieces** field lists with users outside the change but no ledger row, go to one `architect`. It rules on each (in ledger / rename to `<x>` / replace with the existing `<path:line>` / add to the ledger with why), updates the ledger, and adds a check per user.
4. Skip only when steps 1-3 find nothing.
5. Rulings that change code, and rulings that add a check, go to a Fix round (`Do:` the fixes and `run A<n>`); that check's PASS, weak or NOT RUN result is judged like a group report before the commit. A group gets at most two Fix rounds from its gate; a ruling after the second goes to the user.

## audit

Before opening or updating a PR. Read state.md, then run `/review-branch "<purpose>" --tree <tree> --base <Base> --state <folder> --size <Tier's size> [--since <Last reviewed>] [--fix]`. Its whole-branch reviewers carry the `consistency` lens, so nothing here runs a second set; its consistency findings are Major, never deferred.

## Fix round

The one home of fixing, for `--fix` here and in `/review-branch` and `/review-system`.
- With a state folder: the fix list `<folder>/fix-<source>-<n>.md` (`.claude/templates/fix-list.md`, source `gate<g>`, `review<r>` or `ci<c>`) goes to a fresh `implementer` (never resumed), then a `checker` runs `scripts/dev/verify.sh` in the tree, then `gate --state`.
- Without one (a hand-run `--fix`): the fix list goes inline in the brief, then the checker, then `gate --base <the review's --base; review-system: HEAD>` steps 1-2 only, with file rulings to an architect without a spec.
- A fix that changes behaviour users notice goes to the user instead.
