# System review lenses

`SKILL.md` Phase 3's checklist, walked through for each file read deeply, on top of `../review-branch/lenses.md` (Every reviewer, and its bugs, cleanup, rules and design lenses read for "the system", where everything is fair game: no problem inside it is pre-existing). A deep-mode agent gets both files.

## contract: are the docs true?
The system's docs are its contract. For each statement about behaviour (who decides what, what never happens, which file owns what, what a member returns), find the code that makes it true; a statement no code backs, or code that does otherwise, is a finding naming which side is wrong. Also a `Files:` header naming files gone or no longer doing what the doc says, and a mechanism no doc mentions where the docs are otherwise complete.

## edges
`bugs` › the paths nobody takes daily, walked for each risky function: long-lived code hides its bugs there.

## deletion: what can go or shrink
`cleanup` over the whole system, plus mechanisms nothing needs since a stage moved their work, options nobody would miss, and a layer whose job has shrunk to forwarding. Each finding states the lines it removes, counted (`sed -n 'a,bp' <file> | wc -l` per part, summed), and names the simpler shape and what moves where.

## seams: how the rest of axiom uses it
Grep the system's public members from outside it (the scope's `[also in: …]` files are where it meets other systems): users reaching into private (`_`) members, decisions re-derived outside instead of read from the system, uses the docs forbid, two users relying on contradictory behaviour.

## tests: are the decisions pinned down?
Each methods helper's decisions have rows, including the edge cases found above; each migration step and Go package with behaviour has its cases; each script its test class. A finding names the missing row and the bug it would catch.

## parity (mode `parity`)
Build the table first: each contract member, `supports` key or rule × backend, one line per cell (`implemented` / `differs: how` / `missing`), from the code, not the docs. A differing cell is a declared `supports` gap (check it's declared on every backend) or a finding. Look hardest at the same input giving a different shape: ids, names, ordering, units, empty states, events on reload.

## collection (mode `collection`)
Many files of one kind: grep each rule from the docs and the Checks across all of them (`grep -L` finds those missing a pattern, `grep -c` the outliers) into a small file × rule table, then read only the odd ones out and the biggest. Findings: the files that break a rule, and a pattern repeated in several that belongs in a base or shared piece.

## security (systems `security`, `greeter`)
What is reachable, shown or runnable while locked or in greeter mode; every unlock and authentication path (only PAM succeeds); secrets in argv, config, logs, environment or loosely permissioned files; input from other processes (IPC, D-Bus, user-writable files) trusted unchecked; a failure that fails open.
