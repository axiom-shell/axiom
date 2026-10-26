---
name: next-step
description: Take the next step of axiom's roadmaps (the cleanup roadmap and the backend roadmap, as one ordered list). Use when the user says "next step", "continue the roadmap", "what's next", "keep going", "do phase N", "do stage N", or names a roadmap row or issue to work on.
---

Read `docs/dev/roadmap.md` › Taking the next step and follow it exactly: it says how to find the step (the first Full order row not `done`), how to pick the batch (a PR of related items, a commit each), and how to update both roadmaps and `docs/dev/issues.md` in each item's commit.
Finish when `scripts/dev/verify.sh` prints `verify ok` and the roadmap's statuses match what was done; then report the next batch.
