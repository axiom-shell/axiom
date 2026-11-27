# Ledger

Filled by: the architect, as `ledger.md` in the state folder; only an architect's ruling changes it.

## Where to search

The one home of the search-before-writing list: the engine manifest `scripts/engines.json` and `docs/dev/generated/engine-manifest.md` (for engine names), `qml/components/methods/`, `qml/components/reusable/`, `docs/dev/core/shared-ui-pieces.md`, the area's readers and services, `qml/config/schema/` shared definitions, the tests' helpers, existing `I18n.tr` strings. Search by verb and by noun, not only by name. A "none" comes with the grep.

```
# <slug>: ledger
## Reuse          job | existing piece (path:line) | how used | differs by ("nothing" proven)
## Becomes        X | built from (X's own implementation, path) | each behaviour X has today | kept by (path:line) or LOST → open question
## Names          name | kind | file | type and unit | meaning | status (moved from path:line, changed, or new: why) | siblings (two existing, path:line; or none + grep)
## Patterns       kind of site | the one way (precedent path:line)
## Precedents     new file or member | what it mirrors
## Strings        user string | reused from or new
## Changed pieces existing piece the change edits | every user outside the change | the acceptance check per user
## Not to build   what looks needed but exists, with where
## Disagreements  (audit-built ledgers only)
```

- Changed pieces: not "shared piece", which names reusable/forms/parts files.
- In a stack, rows are tagged `[P<n>]`.
