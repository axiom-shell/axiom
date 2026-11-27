# Checker report

Filled by: the checker, after running what it was asked.

```
Tree:
Result: ok | failed: <steps> | NOT RUN: <why>
Failures: each with its step, file:line and the error lines, verbatim
Log: new WARN/ERROR lines from the caller's files
Outside the task: each line a passing check printed about a problem the change didn't cause (a doc behind its files), verbatim; or none (the lead files them)
With --all: the last line, verbatim
```

- Trim passing output and repeated lines, except Outside the task. Nothing else.
