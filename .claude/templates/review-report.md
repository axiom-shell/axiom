# Review report

Used by: `.claude/skills/review-branch/SKILL.md` (§ Branch), `.claude/skills/review-system/SKILL.md` (§ System).
Filled by: the lead of the review, from the confirmed findings.

## Branch

```
# Review: <branch> vs <base> (<n> commits, <files> files, +<a> −<d>)

**Verdict:** ready / ready after the fixes below / needs rework: <one sentence why> (never "ready" with a consistency finding open)
**Purpose check:** <does the branch do what it says; any claim that doesn't hold>

## Blockers / ## Major / ## Cleanups / ## Minor
<each confirmed finding: title, `path:line`, the case, the fix>

## Unsure            (what would settle each)
## Outside the branch (problems the reviewers saw that the branch didn't cause: title and `path:line`)
```

Outside the branch is for the user only: those are never fixed here; the lead reports them (and `/orchestrate` writes them to the follow-ups file when CLAUDE.local.md names one), never files them elsewhere.

## System

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

Outside the system is for the user only: those are never fixed here; the lead reports them (and `/orchestrate` writes them to the follow-ups file when CLAUDE.local.md names one), never files them elsewhere.
