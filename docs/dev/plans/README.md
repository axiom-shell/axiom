# Plans

> **Files:** this folder
> **Config:** none
> **Related:** [Cleanup roadmap](../roadmap.md) › Items that need a plan, [Known issues](../issues.md)

One file per "needs a plan" issues.md entry while it's being designed and built: `<slug>.md`, from the entry's title. It's written and merged through [the roadmap's plan cycle](../roadmap.md#items-that-need-a-plan) and deleted with the last item built from it, so this folder only holds what's in flight.

### Format
```
# <The entry's title>

> **Issue:** [<title>](../issues.md#<anchor>)
> **Status:** proposed | decided: <option> (YYYY-MM-DD)

### Problem
What's wrong, with evidence (paths, log lines, measurements), and who it affects.

### Options
#### A. <name>
What changes, what it costs, what it risks, what it leaves out.
#### B. <name>
…

### Recommendation
The option and why, in a few sentences.

### Items
The small pieces it splits into, in order, each one PR. On approval each
becomes an issues.md entry (Size trivial or small) linked in the roadmap phase
the plan's entry was in.
```
Keep it short enough to decide from: a page or two. Settled details (names, files) belong in the items, not the options.
