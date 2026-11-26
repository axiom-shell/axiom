# Verdict

Filled by: the architect, one reply for all findings sent to it.

## Brief

Send the merged findings, in one message, to one `architect`: "Judge each finding against its cited lines: confirmed (with the failing case), rejected (why), or unsure (what would settle it)."

## Reply

One line per finding, in the order received:

```
F<n>: confirmed — <failing case>
F<n>: rejected — <why it can't happen>
F<n>: unsure — <what would settle it>
```

- The judging rule stays in `.claude/agents/architect.md` › Judging findings.
