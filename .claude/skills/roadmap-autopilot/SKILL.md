---
name: roadmap-autopilot
description: Work through axiom's roadmaps unattended, one item per run: branch, implement, verify, open a PR, review-branch --fix in a fresh agent, CI, merge, update the roadmaps. Use when the user says "autopilot", "run the roadmap", "automate the roadmap", "work through the roadmap", or runs /loop /roadmap-autopilot. `--dry-run` only reports the next item.
argument-hint: "[--dry-run]"
---

Read `docs/dev/roadmap.md` › Running it unattended and follow it exactly, one item per run, as its leader: orchestrate, brief fresh agents for the implementing and the review, and never read source or diffs yourself. With `--dry-run`, do its Preflight and Pick only and report the item without changing anything.
End each run as its step 10 says, the roadmap page's rebuild and publish included (your memory names its builder and URL): stop the loop (and report) at any stop condition, when a Full order row turns `done` or after the session's sixth item; otherwise schedule the next iteration.
