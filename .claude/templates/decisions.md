# Decisions

Used by: `.claude/skills/keep-order/SKILL.md`, `.claude/agents/architect.md` (Checking a plan), `/orchestrate`.
Filled by: the lead, as `decisions.md` in the state folder, from the user's own words.

```
## Request (verbatim)
## Scope            what it includes; what it excludes, quoted
## User answers     D<n>: verbatim, date, where
## Lead rulings     R<n>: one line and the reason
## Defaults taken
```

- Quote the user; never paraphrase a request or an answer.
- Product choices are D ids (the user's answer); technical scope calls with no product stake are R ids.
- The plan check reads every "becomes", "acts as", "is treated as", "like", "same as" or "exactly as" in Request.
