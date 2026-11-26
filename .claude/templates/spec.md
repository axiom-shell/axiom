# Spec

Filled by: the architect, as `spec.md` (`spec-<n>.md` per PR of a stack) in the state folder. `ledger.md` beside it binds names, reuse and patterns.

```
# <slug>: spec
Tier: T<n> (<proposed> → confirmed | raised: why) · Tree, branch, base
## Goal
## Ledger      ledger.md binds; only what the spec adds
## Removed     what the change deletes or merges: path:line → where it goes, or why it can go
## Files       each file: what changes; copy-from; recipe
## Decisions   choice, one-line reason, D/R id
## Acceptance  A<n>: command or read → expected. ≥1 end to end on the real host (nested shells per CLAUDE.md, else LIVE:); a parity check per Becomes row and per "same as", "keeps" or "like" in the request; one per user of each Changed piece. "By construction" is not acceptance.
## Groups      G<n>: files, done-when (A ids), gate focus; verifiable alone
## Not doing   with reasons
## Risks
## Open questions  product only, word for word
## Align       (alignment requests) census table · The one way · Each site · Behaviour changes · Tests · Order
```

- Keep it short; the ledger holds the names.
- Name a real file to copy from, and the recipe in `docs/recipes/` for a known kind of change.
- Risks: the traps in `.claude/rules/` for the area and `docs/dev/core/qml-pitfalls.md`.
