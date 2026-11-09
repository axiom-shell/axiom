# Cleanup roadmap

> **Files:** this file, [issues.md](issues.md)
> **Config:** none
> **Related:** [Moving the service layer to the axiom binary](backend/roadmap.md), [Known issues](issues.md), [Developer docs](README.md)

The phased plan for getting the repository into an excellent, clean state: correct on its rarely taken paths, organized so each file has one job and an obvious home, equal on every compositor, quiet in its log, and documented without excess. It turns [issues.md](issues.md) into an order of work: every entry there is linked from the phase that resolves it.

[The backend roadmap](backend/roadmap.md), which moved the services' side effects into the axiom binary, is finished: its stages are rows of [Full order](#full-order), all `done`. A finished phase is one line under [Finished phases](#finished-phases); its full record is in git history. This file keeps what is open, and the rules for working through it.

## Where things stand
- **Done:** rows 1–15 and 17–19 of [Full order](#full-order): every backend stage, Phases 0–6, 8 and 10 ([Finished phases](#finished-phases)), and [Phase 11](#phase-11-audits-clear-out-and-hardening)'s guardrails (step 0) and audits (step 1).
- **In progress:** row 20, [Phase 11](#phase-11-audits-clear-out-and-hardening) step 2: clearing out issues.md, cluster by cluster ([plans/clear-out.md](plans/clear-out.md)). [Ready for the autopilot](#ready-for-the-autopilot) is empty, so the autopilot has nothing queued.
- **Next:** row 21, Phase 11 step 3: the frozen hardening weeks (the maintainer's). **Later:** row 22, [Phase 9](#phase-9-docs-tooling-and-process), then the post for testers once [the launch gate](#the-launch-gate) is met.
- **On hold:** row 16, [Phase 13](#phase-13-the-maintainers-notes) (the maintainer's notes).
- **Any time (the parallel lane):** [Phase 7](#phase-7-fit-geometry-and-performance) (fit at 1080p, page speed) and [Phase 12](#phase-12-memory-footprint) (memory).
- **Waits on the maintainer:** the [live checks](live-checks.md); Phase 13's "Needs a plan" and "Waiting for the maintainer" lists; entries marked as needing a decision or a choice; the [Deferred](#deferred) entries, to move to GitHub. [Unconfirmed](#unconfirmed) entries wait for a confirmation (on screen, in a log or traced), not a decision.

## Full order
Both roadmaps as one sequence. A row starts when the one above it has merged; the parallel lane fills the gaps at any time. **Status** is `done`, `in progress` (normally one row), `next` (the row after it), `later`, or `on hold` (skipped for now by the maintainer; it blocks no later row); it's kept current by [Taking the next step](#taking-the-next-step), so the first row neither `done` nor `on hold` is always where work resumes.

| # | Status | Work | Why here |
|---|---|---|---|
| 1 | done | Backend stage 2: night light, then clipboard (and [Phase 2](#finished-phases)) | Idle, the clipboard, typing and night light on the daemon's Wayland clients; hypridle, cliphist, wl-clipboard, wtype and hyprsunset dropped. |
| 2 | done | [Phase 0](#finished-phases): stop committing generated docs | About 290 generated files left the tree and every PR's diff. |
| 3 | done | [Phase 1](#finished-phases), except the entries stage 7 fixes | Data and session safety first. |
| 4 | done | [Phase 4](#finished-phases) | archtest and the shell–daemon contract check, before the stages that added packages. |
| 5 | done | [Phase 3](#finished-phases)'s moves and splits (not `KeybindManager`), and [Phase 5](#finished-phases)'s `execDetached` quick wins | One quiet window for every move. |
| 6 | done | Backend stage 3: brightness | brightnessctl dropped. |
| 7 | done | [Backend stage 3b](backend/roadmap.md): exec (polled and streamed commands, JSON) | `CommandManager` in the daemon, which the custom JSON widgets build on. |
| 8 | done | Backend stage 4: scripts | Theming, calendar, hookup, self-update and the greeter installer in Go. |
| 9 | done | [Phase 12](#phase-12-memory-footprint) step 0 and the shell's THP opt-out ([memory](core/memory.md) › Transparent huge pages) | Memory measured; 110–125 MB less at rest and after use. |
| 10 | done | Backend stage 5: HTTP | Weather and the chat in Go; keys never reach QML. |
| 11 | done | Backend stage 6: the funnels | Files, secrets, the compositor sockets and IPC through the daemon. |
| 12 | done | Backend stage 7: the config path, with the `KeybindManager` split | Saves are path ops, takeovers held by the store, one validator; only Go writes compositor configs. |
| 13 | done | [Phase 6](#finished-phases) | sway, SwayFX and Hyprland parity; niri's entries deferred. |
| 14 | done | [Phase 8](#finished-phases) | A clean log. |
| 15 | done | Backend stage 8: the last scripts (`pick_path.py`, `bug_info.sh`) | Nothing at runtime runs python3. |
| 16 | on hold | [Phase 13](#phase-13-the-maintainers-notes): the maintainer's notes | Bugs and small features from the maintainer's own use; after the parity and log rows (some are compositor-specific, and those land there), before Phase 10 so the last feature and the audits are built on them. On hold (maintainer, 2026-10-29: "put maintainers notes on hold (mark it to be skipped for now), and continue forward on Audits, clear-out, and hardening"). |
| 17 | done | [Phase 10](#finished-phases): custom JSON widgets, with their editor page | Waybar-style scripts drawn as bar widgets and modules from one definition. |
| 18 | done | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 0: audit and tighten the guardrails (checks, tests, CI, agent rules) | The guardrails audit (#220) and its 13 batches. |
| 19 | done | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 1: a full audit of every system | Every system audited; the findings filed in issues.md. |
| 20 | in progress | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 2: clear out issues.md, then audit again | Fixes after the audits, so the list isn't refilled behind them; the second pass catches what the fixes broke. |
| 21 | next | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 3: 1–2 weeks of hardening, frozen | The maintainer drives sway and niri daily; only fixes land. |
| 22 | later | [Phase 9](#phase-9-docs-tooling-and-process), then post for testers | Last, so the docs describe the final shape; the post follows [the launch gate](#the-launch-gate). |

**Parallel lane** (any time, between rows): [Phase 7](#phase-7-fit-geometry-and-performance) and [Phase 12](#phase-12-memory-footprint)'s open entries.

**Binaries** (done: #144, #145, #147, #148): every clone takes the official binary built from the commit it checks out ([packaging](packaging.md) › Edge builds), `go` only as the fallback.

## Rules
- **One batch, one PR; one item, one commit.** A batch is one to four items of the same row that sit in the same area, about 800 changed lines at most, so a review still reads it whole. Each item is its own commit ending with `scripts/dev/verify.sh` printing `verify ok`, and a move is a commit of its own that changes no behaviour (its diff reviews as a rename). Batching is what keeps CI's fixed cost (a run per push) per batch, not per item.
- **Delete before adding.** A fix first looks for what to remove: a mechanism made unnecessary, a duplicate, a special case the general path already covers. Between two fixes that work, the smaller one wins, and a fix that makes the code shorter is the best kind. Each PR body states its net lines (QML, Go, scripts; tests and docs apart).
- **A rare path gets the smallest fix, or stays logged** (decided 2026-10-26, after #107 and #108 spent about 840 lines holding the compositor mode while config.json doesn't load, and opened three new entries doing it). A fix for a path a user rarely takes that grows past about 150 lines (tests apart) stops and becomes a plan ([Items that need a plan](#items-that-need-a-plan)), or the entry stays open. Never a stopgap that a later stage then has to delete.
- **The batch size is a gate, not a guide.** Over about 800 changed lines (moves, generated files and tests apart), the batch is split before review, never reviewed whole.
- **A bug that got past the checks adds a check.** When a mechanical check could have caught it, the fix adds that check (or a ratchet), or its PR says why none could. So the guardrails grow from what actually went wrong, and [Phase 11](#phase-11-audits-clear-out-and-hardening) step 0 revamps them rather than starting them.
- **A decision is settled before it's built.** An item resting on a choice the maintainer hasn't made, or might change, stops for the decision first. #116 built a topic floor and #120 removed it the next day.
- **A fix removes its entry from issues.md and its link here** in the same change; a phase is done when its list is empty. A new issues.md entry gets a link in the phase that will fix it.
- **Waits for a backend stage** means the item touches code that stage deletes or rewrites: it's done in that stage's change or after it, never before (no polishing code about to go). Items without one can run at any time, in parallel with the backend roadmap.
- Phases are grouped by kind, not run in number order: [Full order](#full-order) interleaves them with the backend stages. Three rules set it: moves land in quiet windows between stages (they collide with everything); enforcement (archtest, the contract check) lands before the stages that add packages; and nothing polishes code a stage will replace.

## Done means
- `scripts/dev/verify.sh --all` is green, and a reload logs only `Reloading configuration...` and `Configuration Loaded` under Hyprland, niri and sway.
- Every "needs a plan" item is decided: built from its plan, or listed under [Deferred](#deferred) and moved to GitHub by the maintainer.
- `scripts/quickshell-io-allowlist.json` lists only the permanent funnels (`BackendManager`'s socket, `FileManager`'s blocking read).
- No singleton over about 800 lines outside the pure helpers and the compositor backends; every file sits in the folder its rule names.
- `archtest` enforces the backend's dependency direction; the shell–daemon method shapes are checked on both sides.
- The root `AGENTS.md` is 12 KB or less; generated docs are built, not committed.
- [The launch gate](#the-launch-gate) is met, and axiom is posted for testers.

## Taking the next step
What an agent does when asked for "the next step", to "continue the roadmap", or to work on a row or phase by number. The answer to "where do I start" is always this file: nothing else needs explaining.

1. **Find the step.** The first [Full order](#full-order) row not `done` (an `on hold` row is skipped). Its work is the backend stage's bullets in [backend/roadmap.md](backend/roadmap.md) (a stage row) or the phase section below (a phase row). A row named by the user wins; so does a parallel-lane item they name.
2. **Check nobody holds it.** `git log -5` and `git status`: uncommitted changes in that row's files mean another agent is on it. Then take the next unblocked item (the parallel lane, or a later row with nothing waiting), or ask.
3. **Pick the batch** ([Rules](#rules)): the row's next items in order (a backend stage's next not-`Done` bullets, or a phase's first steps not marked `Done:`, then its listed issues; entries under [Deferred](#deferred) or [Unconfirmed](#unconfirmed) aren't the row's), as many as share an area within the batch's bounds; a move or anything large goes alone. A "needs a plan" entry is taken through [Items that need a plan](#items-that-need-a-plan) instead of being built straight away. Read the item's issues.md entry, the docs for its area (`docs/dev/README.md` › Where to look), the matching recipe if there is one, and [issues.md](issues.md) for anything else known in those files.
4. **Do it**, item by item: each a commit after `scripts/dev/verify.sh` prints `verify ok`, and `scripts/dev/verify.sh --all` once before the branch is first pushed.
5. **Update the roadmaps in each item's commit:**
   - remove the fixed issues.md entry and its link here;
   - mark a finished phase step `Done:` at its start (as backend/roadmap.md marks its bullets);
   - when a row's last item is done (a deferred item doesn't count; a plan waiting for its decision does), set its Status to `done`, the next row's to `in progress` and the one after to `next` (passing over `on hold` rows), and update [Where things stand](#where-things-stand); a stage row also updates its status in backend/roadmap.md; a phase whose last item is done becomes one line under [Finished phases](#finished-phases) (its record stays in git history);
   - anything learned that changes the order is an edit to [Full order](#full-order) with its reason in the "Why here" cell.
6. **Report** what was done, what the next item is (the user's next "next step"), and anything found and filed in issues.md along the way.

## Items that need a plan
An issues.md entry sized "needs a plan" is a design question before it's work. One that names a backend stage (`(stage 7)`, "Fixed by backend stage 7") is designed in that stage instead; every other one goes through this cycle, which never blocks the rest of its row.

1. **Plan.** A fresh agent investigates the entry and writes `docs/dev/plans/<slug>.md` in the format of [plans/README.md](plans/README.md): the problem with evidence, two or three options with their trade-offs, a recommendation, and the small items it splits into. Docs only, one PR, labelled `roadmap` and `needs-decision`; the entry's link here gets `(plan: #<PR>)` in the same PR.
2. **Carry on.** The row's other items go ahead meanwhile. The row can't turn `done` while a plan waits.
3. **The maintainer decides** on the PR: approves it (as written, or after editing it), comments the option chosen, or comments `defer`.
4. **Approved:** the PR is merged with its plan marked decided, and in the same PR the entry is replaced by the plan's small items, each an ordinary issues.md entry linked in the same phase where the old one was. From there they're built like any other item, and the plan file is deleted with the last of them.
5. **Deferred:** the PR is closed, and the entry's link moves to [Deferred](#deferred), which blocks no row. The maintainer moves deferred entries to GitHub over time.

## Running it unattended
The cycle the `roadmap-autopilot` skill runs, one batch (one PR) per iteration, driven by `/loop /roadmap-autopilot` in a session of its own (auto mode, so git and gh don't stop it for permission). It works in a scratch `git worktree` of its own (detached at `origin/main`, `scripts/generate.sh` run once), never in the live checkout, where the maintainer develops meanwhile (maintainer, 2026-10-29: "move all development to a scratch worktree and keep my live repo unaffected"). So the live shell never runs a batch before it merges. With `--dry-run` it only reports the batch it would take.

**The leader orchestrates; fresh agents read code.** The session running the loop is the leader. It holds enough to judge and steer: the Full order, the picked item's phase section and issues.md entry, the brief it writes, the agents' reports, and the gates' short outputs. It never reads source files or diffs itself (`git diff --stat` and the PR body are its view of a change); anything that needs code read goes to an agent. So each batch adds about a screenful to the leader's context, and every agent that reads code starts clean. Everything that must outlive the session is in the repo and on GitHub (statuses, issues.md, PR labels), so a new leader picks up where the last left off.

**Bounds.** A leader does at most three batches, then stops and asks for a fresh session even mid-row, and every row starts in a fresh session (the pause after a row ends the loop). Agents answer in the report shape asked for: a report that runs long is read for its fields, not reread. A failing gate's output is read as `tail` / `grep`, never whole.

1. **Preflight** (leader). In the worktree, `git status` clean (anything uncommitted means someone else is working there: stop; the live checkout's state is the maintainer's), then `git fetch` and `git switch --detach origin/main`. The maintainer also answers in PR comments, after a merge too: read the comments on the recent `roadmap` PRs (`gh pr view <n> --json comments`) and write any answer into its issues.md entry, quoted. An open PR labelled `roadmap` (`gh pr list --label roadmap`) is resumed at the step it reached instead of starting a new batch, unless it's a plan waiting for its decision, which never holds up the row ([Items that need a plan](#items-that-need-a-plan) step 2). One labelled `needs-decision` waits for the maintainer: if it's a plan with a decision on it (an approval, a chosen option, or `defer`), finish [Items that need a plan](#items-that-need-a-plan) step 4 or 5 for it first; any other one blocks its row until the maintainer answers.
2. **Pick** (leader) the batch with [Taking the next step](#taking-the-next-step) steps 1–3, reading only the Full order, that phase's section (or the stage's bullets in [backend/roadmap.md](backend/roadmap.md)) and the items' issues.md entries; a batch is never wider than one row. A "needs a plan" item gets a plan PR ([Items that need a plan](#items-that-need-a-plan) step 1, by a fresh agent with a brief like step 3's) and the leader moves on to the row's next item; when only plans waiting for decisions are left in the row, stop and report them. An item that needs a decision or a forbidden action ends the batch before it (the items before it still go); when it's the first, stop and report instead of starting. That's an item that needs a maintainer decision (a changed default, whether a migration is worth it, a behaviour trade-off), or waits on a row that isn't `done`. An item that can only be built or confirmed in the live environment (a live action `AGENTS.md` › Never forbids, or a fix only the maintainer's session shows) never holds anything up (maintainer, 2026-10-29: "mark accordingly in the roadmap and don't let it hold everything up - I can get to that later"): it's built as far as tests and nested runs take it, or skipped, and listed in [live-checks.md](live-checks.md); the batch and the row go on. An issues.md entry marked PLAUSIBLE, or one whose cause isn't traced in the code or shown, is skipped and stays logged (one an agent's review or audit found has its link moved to [Unconfirmed](#unconfirmed), maintainer, 2026-11-05: "just leave plausible code reviewed only found bugs in a new list to get to eventually (i.e not human submitted"; a human-submitted one stays in its phase): only code style, clear problems and breaks, and traceable bugs get fixes (maintainer, 2026-11-05: "clear code style and problems / breaks get fixes, and tracable bugs. Anything marked plausible will not receive any updates to the code or make it into a kerge").
3. **Brief** (leader), ten to fifteen lines plus two or three per item: the row and the items in order; each issues.md entry's title and its **Where**/**What**; what done looks like (the behaviour, and the entry removed with its link here); the docs to start from (`docs/dev/README.md` › Where to look, the recipe if one fits); the branch name `roadmap/<row>-<slug>`; and the stop conditions above, so the agent stops rather than guesses. A maintainer decision the item rests on is quoted word for word from roadmap.md or issues.md, with no step of the leader's own on how to build it (2026-10-26: a brief that added "so set the schema minimum to 5000" to a quoted decision broke saved configs), and a decision that seems to clash with its entry's title is a stop, not a reading. Every brief says: never `sudo`, `pkexec`, `su` or anything prompting for a password; a test needing root runs in a user namespace (`unshare -rm`), and what can't is skipped and reported (maintainer, 2026-10-30: "tell claude to stop asking for admin rights"). The brief also quotes [Rules](#rules)' Delete before adding and the rare-path cap (about 150 lines), so the agent stops there rather than building on.
4. **Implement** (a fresh `general-purpose` agent, given the brief): branch in the worktree from `origin/main`, never pushing it; then per item: implement, `scripts/dev/verify.sh` until `verify ok`, and commit it (row 20: a cluster is the item, committed one commit per file group, [Phase 11](#phase-11-audits-clear-out-and-hardening) step 2.6) with [Taking the next step](#taking-the-next-step) step 5 (statuses, `Done:` marks, issues.md removals) and the attribution trailer. An item it has to stop on is left out (reset to the last item's commit) and reported; the committed ones go on. The live session runs the maintainer's checkout, so a change rests on its tests, nested runs and the review; what only the live session can show is reported under **Not verifiable live**. It reports in at most 250 words: **Commits** (sha and item, one line each), **Changed** (one line per file group), **Verified** (the `verify ok` line, the tests run), **Not verifiable live**, **Filed** (issues.md titles added), **Stopped** (why, if it did).
5. **Gate** (leader): the branch is at the last commit's sha, `git status` is clean, `git diff --stat origin/main...HEAD` touches the batch's area plus `docs/dev/roadmap.md` / `docs/dev/issues.md`, the closed entries' headings are gone from issues.md, and the batch is within the size gate: `git diff --shortstat origin/main...HEAD -- . ':!**/*_test.go' ':!tests/' ':!docs/'` at about 800 changed lines or fewer, unless its commits are pure moves. An oversized batch isn't sent back to be cut: it stops, and the leader reports it with a proposed split. A failed gate goes back to the same agent once (by `SendMessage`, with the failing lines); a second failure stops.
6. **Review** (a second fresh `general-purpose` agent, so the review isn't anchored on the implementer's reasoning), on the local branch before anything is pushed: runs the `review-branch` skill with the batch's intent and `--fix`, commits its fixes after `verify ok` (one commit per round, never pushing), and reports in at most 200 words: findings fixed (by severity), **Questions**, unfixed **Blockers**, the new sha. Each round that fixed a Blocker or Major gets another, by a fresh agent, up to five rounds (maintainer, 2026-10-30: "up the Maxx to 5", "as long as there is a major fix it needs another review"); a round that fixed only minors ends it. Before that next round, if `origin/main` moved past the branch's base, the leader merges it in (`git merge origin/main`, conflicts by an agent, `verify ok`), so the round reviews the branch on today's main (maintainer, 2026-11-05: "after review round 1 ( before launching a second review round for either if necessary merge moved main in)"). Row 19's audit batches (three systems each, audited in parallel in worktrees of their own and combined into one branch before this step) get one review round: a round there that fixed a Blocker or Major opens the PR labelled `needs-decision` rather than starting another (maintainer, 2026-10-30: "let 5 finish but cap at one round. Implement accordingly to keep it cheaper as described"). A question with no product stake (how far a technical fix reaches) the leader decides, comments its reason on the PR and carries on (maintainer, 2026-10-29: "I don't care, as long as it is smartly implemented for the stack"). A product question (a changed default, a trade-off users notice, a migration, a takeover), a Blocker it couldn't fix, or a fifth round that still fixed a Blocker or Major (so no such fix merges unreviewed): push and open the PR as step 7 does, labelled `needs-decision` too, comment the findings on it, and stop.
7. **PR** (leader): `scripts/dev/verify.sh --all > <scratch>/verify.log; tail -3` ends in `all checks passed` (every CI check, so CI only confirms; a plain `verify.sh` checks only uncommitted changes, so on the committed branch it prints `nothing changed since HEAD`), then `git push -u origin <branch>` once (the guard passes only a named branch) and `gh pr create --label roadmap`; the body lists the row, each item with its commit and the issues.md entries it closed, and the reports' Verified and Not verifiable live.
8. **CI** (leader): `gh pr checks <n> --watch`. A failure goes to a fresh agent with the failing job's log tail (`gh run view --log-failed | tail -60`) to fix, run `verify.sh --all` and push once, at most twice; then stop with the PR open.
9. **Merge** (leader): first `git switch --detach` in the worktree (`--delete-branch` deletes the local branch, and with it a worktree holding it), then `gh pr merge <n> --squash --delete-branch` as a command of its own (a compound command doesn't match its allow rule), then `git fetch` and `git switch --detach origin/main` there (the live checkout is left alone). The squash message keeps each item's commit message as a bullet. A merged item whose report has a **Not verifiable live** that matters gets a line in [live-checks.md](live-checks.md) in the next batch.
10. **After** (leader): rebuild and republish the maintainer's roadmap page, which lives outside the repo; the leader's memory names its builder and URL. Its statuses come from this file and backend/roadmap.md, so it's a build and a publish, never hand edits. Do this after every merge and at every stop. Stop the loop and report if [Ready for the autopilot](#ready-for-the-autopilot) is empty (maintainer, 2026-11-06: "have the autopilot stop itself when everything is done"), if this merge set a Full order row to `done` (the pause between rows, so the maintainer looks before the next one starts) or this was the session's third batch; otherwise schedule the next iteration. A report says what merged (PR links), where it stopped and why, and what the next batch is.

Never, besides `AGENTS.md` › Never: open a PR of roadmap.md or issues.md edits alone (a plan PR aside: an answer or a moved entry goes in the next batch's first commit), merge a PR without the `roadmap` label, put two rows or more than four items in one PR (row 20: more than one cluster), push before the review, skip the review or CI, or retry a stop condition. A wallpaper-only screenshot means the session locked while idle: stop and ask the user to unlock.

## Ready for the autopilot
The maintainer (2026-11-06): "right now, everything deferred or hold that it small and has a traced fix move to ready and waiting for the autopilot. After all of that is done the autopilot will stop. (i.e. unconfirmed, weird vaguely described ui problems from developer notes, and plans done stay)". So the loop takes only the entries listed here, grouped by area so a batch stays in one; when this list is empty it stops the loop and reports, whatever row 20 still holds. It opens no plan PR and no `needs-decision` PR: an entry that turns out to need a choice or isn't as traced is skipped and its link moved back where it came from.

Empty: every entry moved here on 2026-11-06 was fixed, or moved back where it came from.

## Live checks
Every check that waits for the maintainer's own session (a merged fix to confirm live, an item only the live environment can build, code no real hardware has run yet) is in [live-checks.md](live-checks.md). None of it holds up a row.

## Finished phases
One line each (row, outcome, PRs where recorded); the full record is in git history.
- **Phase 0: decisions and quick wins** (row 2): generated docs no longer committed, topics fed by a setting floored at 1 ms (`topics.MinInterval`), `TailscaleManager` moved to `apps/`; the takeover fix and idle went to backend stages 7 and 2. Left to the maintainer: `git gc` locally.
- **Phase 1: integrity** (row 3, the last with backend stage 7): every entry fixed; the hand-fix gap with no takeovers kept is [Deferred](#deferred).
- **Phase 2: finish stage 2** (row 1): backend stage 2, with the hypridle autostart default dropped (step v78) and the D-Bus match rules' escaping.
- **Phase 3: QML structure** (row 5): services' folders reworded, feature pieces moved out of `reusable/`, `ShellManager` and `EdgeMenuManager` split, `LauncherConfigBrowser`, `ScreenEdgeManager` and `DeadlineTicker` extracted; the `KeybindManager` split went with backend stage 7.
- **Phase 4: backend structure and contract** (row 4): `archtest`, one floor for interval topics, the shell–daemon contract check, strict param decoding, clearer package names.
- **Phase 5: the allowlist** (rows 5–12): backend stages 3–7 plus the `execDetached` quick wins; `SchemaValidation` trimmed to previews and the QML compositor renderers deleted.
- **Phase 6: compositor parity** (row 13): every sway, SwayFX, Hyprland and all-compositor entry fixed; niri's entries [deferred](#deferred) (maintainer, 2026-10-29).
- **Phase 8: a clean log** (row 14): a reload and normal use log only the two reload lines; the last entries went through [Ready for the autopilot](#ready-for-the-autopilot).
- **Phase 10: custom JSON widgets** (row 17): a script's output (Waybar's JSON as the preset) drawn as a bar widget, popout and module from one definition, with its editor page, Waybar import and presets ([plans/custom-json-widgets.md](plans/custom-json-widgets.md)); its "done when" (5–10 popular Waybar scripts) is a [live check](#live-checks).

## Open phases

### Phase 7: fit, geometry and performance
Nothing runs off a screen or clips at 1080p, and pages stay fast as their data grows. Take the 1080p entries as one pass in a nested compositor with a 1080p output.

- [Text clips on 1080p screens](issues.md#text-clips-on-1080p-screens)
- [A popout taller than the screen runs off it](issues.md#a-popout-taller-than-the-screen-runs-off-it)
- [A dropdown in an edge menu card with nothing scrolling gets two rows](issues.md#a-dropdown-in-an-edge-menu-card-with-nothing-scrolling-gets-two-rows). *Not as traced* (row 20's autopilot): see the entry.
- [A model of size -1 when the overlay grid resizes](issues.md#a-model-of-size--1-when-the-overlay-grid-resizes)
- [Compact cards still build their full layout](issues.md#compact-cards-still-build-their-full-layout)
- [The keybinds page on a small monitor with large binds](issues.md#the-keybinds-page-on-a-small-monitor-with-large-binds) (with the 1080p pass)
- [Modules inside borders aren't sized evenly](issues.md#modules-inside-borders-arent-sized-evenly)

### Phase 9: docs, tooling and process
Last, so the docs describe the final shape (after [Phase 11](#phase-11-audits-clear-out-and-hardening); the post for testers follows it).

Steps: trim the root `AGENTS.md` to its rules (mechanics move to the `docs/dev` pages it points at); fold `docs/dev/core/config-v2.md` into `schema-annotations.md` and `config-manager.md` once stage 7 finishes v2; the maintainer moves the [Deferred](#deferred) entries to GitHub; a PR-size note in `CONTRIBUTING.md` (a batch per PR, an item per commit, moves apart from logic); the maintainer prepares the photos and videos for the post (it blocks the post, not the row).

### Phase 11: audits, clear-out and hardening
The guardrails tightened first, then every system audited in full, every open entry fixed or deliberately deferred, then a frozen stretch of daily use, before posting on the sway and niri wikis for testers (decided 2026-10-27). Nothing new is built in this phase.

Steps:
0. Done (row 18): the guardrails audited (#220) and tightened in 13 batches: CI and `check_all.sh` agree, verify.sh, the guard, flaky and root-only Go tests, break-it tests for PAM, the greeter installer and the takeovers, ratchets, tests of the checks, a sampled mutation run, checks for what got past them, speed, and the agent rules (AGENTS.md 25.1 → 11.9 KB). Records: `.claude/reviews/guardrails.md`.
1. Done (row 19): every system audited with the `review-system` skill (`--full --record`, `--deep` where needed) in 16 batches, each with a deletion pass; the findings are in issues.md, linked below. The size before it is under [Size](#size).
2. **Clear out issues.md** (row 20): every open entry is fixed, or the maintainer defers it (to [Deferred](#deferred), then GitHub, listed as a known issue in the post); rare paths get the smallest fix or stay logged. A "needs a plan" entry goes through [Items that need a plan](#items-that-need-a-plan). The maintainer's idea (2026-10-31): "My thought is do every single minor on a single PR for the entire system. Then for majors do 3-6 depending on how they interact and what is kinda related." The plan built on it (approved 2026-10-31: "write it as described"), for about 228 open entries now and 400–500 after the audits, so about 25 minor and deletion PRs plus 40–60 major clusters:
   1. **Triage first.** Before any fix, a cheap pass per area (one agent each) reads the entries, merges duplicates across systems, and writes the PR list into this step: the clusters, their entries and their order. The loop then takes the next cluster; the maintainer can reorder or veto clusters before work starts. The list: [plans/clear-out.md](plans/clear-out.md) (triage done 2026-11-01; questions answered 2026-11-01; no reorder or veto, maintainer, 2026-11-01: "Start as written (Recommended)").
   2. **Clusters by shared code, not strictly by system.** Majors that span systems (e.g. "Images decoded at full size", in modules, popouts and the bar) are one cluster wherever they were filed.
   3. **Per area: Blockers, then Majors, then minors.** Blockers alone or in pairs; Majors 3–6 per PR by how they interact; minors last, one PR per system (small related systems combined: theming with theme integrations, the launcher with its providers, the greeter with security), so a sweep isn't churned by the major fixes on the same files.
   4. **Deletion findings get a PR of their own per area**, cheap to review, and may go first: they shrink what the other fixes touch.
   5. **Product questions up front.** Entries with open maintainer questions are gathered into one list, answered in one sitting before their cluster starts, rather than stopping the loop one at a time.
   6. **Batch rules for row 20.** A cluster counts as one item (in place of the four-item cap), committed one commit per file group rather than per entry. The ~800-line size gate stays; a sweep over it splits by file group.

   Then an incremental `review-system` pass of every system (it rereads only what changed since its last review), and again, until a pass finds nothing above minor.
3. **Harden, frozen** (row 21; the maintainer's, so the autopilot stops before it): 1–2 weeks of daily use under sway and niri. Only fixes land: each new finding is fixed at once or becomes a known issue. Also: a first run from nothing (`install.sh` and the AUR packages for a fresh user, onboarding without a config.json, importing saved configs), and the Waybar scripts from Phase 10 again.

Found by the audits:
- [The border's stroke row is left unfilled where two pill bars meet at its corner, unbacked](issues.md#the-borders-stroke-row-is-left-unfilled-where-two-pill-bars-meet-at-its-corner-unbacked)
- [A detached dock and toasts don't slide in from under the bars](issues.md#a-detached-dock-and-toasts-dont-slide-in-from-under-the-bars)
- [Tailscale's state is polled where it could be pushed](issues.md#tailscales-state-is-polled-where-it-could-be-pushed)

Found along the way:
- [A remap runs at startup, from the layout before the config loaded](issues.md#a-remap-runs-at-startup-from-the-layout-before-the-config-loaded) (investigating Hyprland starting on workspace 10)
- [TestDiscoverCalDAV failed once under verify.sh --all](issues.md#testdiscovercaldav-failed-once-under-verifysh---all) (reviewing the guard's leading `cd`, config-05)
- [TestLogindLockAndSleep failed once under verify.sh](issues.md#testlogindlockandsleep-failed-once-under-verifysh) (the same)
- [A push of a named branch can land on main through git's push config](issues.md#a-push-of-a-named-branch-can-land-on-main-through-gits-push-config) (reviewing the guard's gh and push allowlists)
- [The daemon's other own commands still start outside command.Children](issues.md#the-daemons-other-own-commands-still-start-outside-commandchildren) (moving the daemon's own commands to command.Run)
- [A daemon re-exec during a crawl leaves the crawl child a zombie](issues.md#a-daemon-re-exec-during-a-crawl-leaves-the-crawl-child-a-zombie) (building the launcher's file search)
- [A watched folder that keeps changing is read again in the daemon every 500 ms](issues.md#a-watched-folder-that-keeps-changing-is-read-again-in-the-daemon-every-500-ms) (reviewing the launcher's file search)
- [axiom config validate checks the install's config with the binary's schema under dev mode](issues.md#axiom-config-validate-checks-the-installs-config-with-the-binarys-schema-under-dev-mode) (fixing the daemon's config watch)
- [A hover-opened held edge menu closes before the pointer crosses from its edge to its box](issues.md#a-hover-opened-held-edge-menu-closes-before-the-pointer-crosses-from-its-edge-to-its-box) (reviewing the dock gaps batch)
- [rpc.md doesn't mark the drives methods shell only](issues.md#rpcmd-doesnt-mark-the-drives-methods-shell-only) (moving Bluetooth to the daemon)
- [TestNotifySend failed once under verify.sh](issues.md#testnotifysend-failed-once-under-verifysh) (the same)
- [The screen-share picker repeats the shared prompt's modal frame](issues.md#the-screen-share-picker-repeats-the-shared-prompts-modal-frame) (lifting polkit's window into the shared prompt)
- [A drive card's "open" on a locked volume asks in a menu nobody opened](issues.md#a-drive-cards-open-on-a-locked-volume-asks-in-a-menu-nobody-opened) (reviewing the Bluetooth daemon branch)
- [guard.py doesn't judge qs ipc call](issues.md#guardpy-doesnt-judge-qs-ipc-call) (the same)
- [guard.py judges daemon calls and the radio only by argv](issues.md#guardpy-judges-daemon-calls-and-the-radio-only-by-argv) (the same)
- [A VPN secret request held when the shell leaves waits for NetworkManager's timeout](issues.md#a-vpn-secret-request-held-when-the-shell-leaves-waits-for-networkmanagers-timeout) (the same)
- [Making a note or folder creates a linked notes folder that doesn't exist](issues.md#making-a-note-or-folder-creates-a-linked-notes-folder-that-doesnt-exist) (fixing the notes folder entries)
- [The OSD's hover strip opens an empty bars slot when every bar is left out](issues.md#the-osds-hover-strip-opens-an-empty-bars-slot-when-every-bar-is-left-out) (reviewing the OSD engine branch)
- [An OSD on a screen that isn't the target opens its parts while shut and then stays open](issues.md#an-osd-on-a-screen-that-isnt-the-target-opens-its-parts-while-shut-and-then-stays-open) (the same)
- [An OSD tile pops in on its own easing curve](issues.md#an-osd-tile-pops-in-on-its-own-easing-curve) (the same)
- [The OSD's drive tooltip names the last drive an event came from, even one removed](issues.md#the-osds-drive-tooltip-names-the-last-drive-an-event-came-from-even-one-removed) (the same)
- [The OSD's System volume bar stays enabled with no audio sink](issues.md#the-osds-system-volume-bar-stays-enabled-with-no-audio-sink) (the same)
- [The OSD's Wi-Fi Connected card goes blank when the network drops while it's out](issues.md#the-osds-wi-fi-connected-card-goes-blank-when-the-network-drops-while-its-out) (the same)
- [An OSD showing only Now playing opens an empty card from its hover strip or Show button when nothing plays](issues.md#an-osd-showing-only-now-playing-opens-an-empty-card-from-its-hover-strip-or-show-button-when-nothing-plays) (the same)
- [A type library's search matches the "Other" heading of every ungrouped type](issues.md#a-type-librarys-search-matches-the-other-heading-of-every-ungrouped-type) (the same)

#### The launch gate
Posting for testers waits for all of these:
- issues.md has nothing open a tester can reach in normal use under sway or niri; what's deferred is on GitHub and listed in the post as known issues;
- a reload logs only the two reload lines under Hyprland, niri and sway;
- `scripts/dev/verify.sh --all` is green;
- the last audit pass found nothing above minor;
- the code is smaller than before the audits ([Size](#size)): QML and Go lines (tests apart) went down, or each system that grew says why;
- the hardening weeks ended with no fix pending.

#### Size
Lines of code (tests, generated files and docs apart) for QML, Go and scripts, recorded with their commit before step 1, after step 2 and at the launch gate, with the shortstat command used, so each reading compares like with like.

Each reading is the `insertions` of a shortstat against the empty tree, so it needs no checkout (`C` is the commit read; `--name-only` in place of `--shortstat` lists the files counted):

```sh
E=$(git hash-object -t tree /dev/null)
git diff --shortstat $E $C -- '*.qml' ':!tests/'                                    # QML
git diff --shortstat $E $C -- '*.go' ':!*_test.go' ':!*/testdata/*' ':!*test/*' \
    ':!backend/internal/testkit/' ':!*/zz_generated_*'                              # Go
git diff --shortstat $E $C -- '*.sh' '*.py' '.githooks/pre-commit' ':!tests/'       # scripts
```

Tests are `tests/`, `*_test.go`, `testdata/` and the Go test helper packages (`testkit`, `dbustest`, `logindtest`, `wiretest`); the only committed generated code is `zz_generated_*.go` (the other generated files are JSON or never committed: [testing](testing.md#the-checks)). Lines include comments and blank lines.

| Reading | Commit | QML | Go | Scripts |
|---|---|---|---|---|
| Before step 1 | `64038c2` | 103,991 (684 files) | 51,927 (215 files) | 7,512 (37 files) |

### Phase 12: memory footprint
The shell's RSS at rest and after use, measured rather than guessed: about 840 MB at rest and over 1 GB after use on one monitor (2026-10-27), almost all of it C++ heap and per-window renderer state, not JS.

Done (row 9): measuring ([memory](core/memory.md): a reading script and `bench_overlay.sh --mem`, with a baseline), and the shell's THP opt-out (maintainer, 2026-10-27: "yes, opt the shell out of THP"): 110–125 MB less at rest and after use.

- [Nineteen windows stay mapped on one monitor](issues.md#nineteen-windows-stay-mapped-on-one-monitor)

### Phase 13: the maintainer's notes
Bugs and small features from the maintainer's own use, filed from their notes on 2026-10-28 (compositor-specific ones are in Phase 6 or its [deferred](#deferred) niri entries, fit ones in [Phase 7](#phase-7-fit-geometry-and-performance)). Each feature step follows its recipe (`setting`, `settings-card`, …); the plans go through [Items that need a plan](#items-that-need-a-plan).

Done (row 16 and since): niri's own overview and window switcher (`WorkspaceOverlay.compositorOverview`, `WindowSwitcher.compositorSwitcher`), `Overlay.moduleBorders`, a test notification, caffeine on a timer, Markets ([markets](features/markets.md)), the notifications revamp ([notifications](features/notifications.md)), the overlay and popouts no longer closing each other (#211), the window switcher's blur and key release on sway and niri (#212), low levels kept in their rounded troughs, a Caps Lock warning in password fields (#270), the OSD's statuses (#272), input sources ([input sources](features/input-sources.md)), Full Bluetooth (maintainer, 2026-11-06; the `bluetooth-daemon` branch: the daemon owns Bluetooth and is its pairing agent, one shared prompt for every password, PIN or confirmation request, the OSD's Bluetooth card and low battery warnings, device actions, discoverable, rfkill unblock and peripheral batteries; [Networking and Bluetooth](features/networking-bluetooth.md), [Prompts](features/prompts.md)) and file search in the launcher (maintainer, 2026-11-08: "~ prefix + few in main", "Path browsing, Recent files, Image thumbnails", "Open / reveal / copy"; the `file-search` branch: the daemon's own index, crawled by an idle-priority child, `~` mode, the best files in the main search, browsing, recent files and thumbnails; [File search](features/file-search.md)).

Found meanwhile:
- [Submenus don't always get their blur backing](issues.md#submenus-dont-always-get-their-blur-backing)
- [A greeter-only module validates on any page](issues.md#a-greeter-only-module-validates-on-any-page) (back from Ready for the autopilot, 2026-11-06: rejecting it can stop an existing config from loading; whether a migration removes misplaced modules first is a decision)
- [BlurManager.paused and WallpaperManager.rotationHeld read undefined on a reload](issues.md#blurmanagerpaused-and-wallpapermanagerrotationheld-read-undefined-on-a-reload)
- [A theme can't be generated from an avif or jxl wallpaper](issues.md#a-theme-cant-be-generated-from-an-avif-or-jxl-wallpaper) (a choice: a Go decoder dependency, or the shell handing over the image Qt decoded)
- [Peripherals only UPower sees aren't in the Battery widget or module](issues.md#peripherals-only-upower-sees-arent-in-the-battery-widget-or-module) (Full Bluetooth)
- [Ctrl+C on a file row copies its path, not the file](issues.md#ctrlc-on-a-file-row-copies-its-path-not-the-file) (file search, left out of v1)
- [Rows re-ranked under the selection while the file index builds](issues.md#rows-re-ranked-under-the-selection-while-the-file-index-builds) (reviewing the file search)
- [appLauncher files has no keybind action](issues.md#applauncher-files-has-no-keybind-action) (reviewing the file search; the maintainer's call)

Needs a plan:
- [The chat has no slash commands to control it](issues.md#the-chat-has-no-slash-commands-to-control-it)
- [Video wallpapers](issues.md#video-wallpapers) (an idea from the wallpaper transitions branch)
- [A pill bar stacked inside another pill bar grows its pills out of nothing](issues.md#a-pill-bar-stacked-inside-another-pill-bar-grows-its-pills-out-of-nothing)
- [Quick actions can't hold custom toggles or commands](issues.md#quick-actions-cant-hold-custom-toggles-or-commands) (set aside from the unified-actions branch, 2026-11-06)
- [File search crawls what .gitignore leaves out](issues.md#file-search-crawls-what-gitignore-leaves-out) (file search, left out of v1)
- [File search matches names only, not what files hold](issues.md#file-search-matches-names-only-not-what-files-hold) (file search: full-text search, deferred from v1)

Waiting for the maintainer (moved here 2026-10-29 so they don't block the row; the maintainer: "they may be vague and require testing. If so, mark it, push it to the end of the phase so it doesn't block and I will handle all the questions then"):
- [Setting names that still confuse](issues.md#setting-names-that-still-confuse). *Needs the maintainer:* the note ("still confusing option names in settings") names no settings, so which ones read wrong is theirs to list.
- [The monitor editor shows changes nobody made](issues.md#the-monitor-editor-shows-changes-nobody-made). *Needs testing:* in nested niri a saved profile for what's connected opens the page with nothing unsaved (the draft only changes through an edit or `_detect` adding a profile or a monitor the daemon's match doesn't list); on which compositor, and after what (opening the page, an Apply, a hotplug, a reload), does it show?
- [Typing in modules on the overlay and the desktop](issues.md#typing-in-modules-on-the-overlay-and-the-desktop). *Needs testing:* nothing in the code keeps the keyboard from an overlay module (the overlay asks for it on demand like the edge menus, exclusively under a grab with no native one, the newest grab since #193, and no handler above the modules takes keys), and only a real click into a field shows it, which the agents may not simulate. On which compositor does it happen, in which module, and does the field show a cursor with the keys going nowhere, or not take the click? On the desktop: is the click that ends the typing on a window (where it gives the keyboard back by design, [desktop](features/desktop.md) › Input), on the bare desktop beside the module, or inside the module itself? (Under niri's focus following the mouse, it's the deferred [A window takes the keyboard from a desktop module on niri](issues.md#a-window-takes-the-keyboard-from-a-desktop-module-on-niri).)
- [A hot corner can't close what covers it](issues.md#a-hot-corner-cant-close-what-covers-it). *Not as traced* (row 20's autopilot): decided, but keeping the corner over Overlay-layer surfaces on niri and sway needs a way to stack it that the entry doesn't trace (see the entry).

## Deferred
Entries decided against doing now: a plan the maintainer deferred ([Items that need a plan](#items-that-need-a-plan) step 5), or an entry they put off by hand. They block no row; the maintainer moves them to GitHub, and an entry leaves this list and issues.md together.

Extremely rare paths, put after real gaps (2026-10-26):
- [Leaving managed, the runtime layer can go on before the given-back config reloads](issues.md#leaving-managed-the-runtime-layer-can-go-on-before-the-given-back-config-reloads) (transient: corrected after the reload)

Deferred by the maintainer (2026-10-27):
- [Readers read files through a service](issues.md#readers-read-files-through-a-service)

Accepted by the maintainer (2026-10-28, #163): the hand-fix gap with no takeovers kept
- [With no takeovers kept, a broken config.json can still release the compositor's config](issues.md#with-no-takeovers-kept-a-broken-configjson-can-still-release-the-compositors-config)

Deferred by the maintainer (2026-10-29, Phase 6's niri entries: "defer all six niri items and continue"):
- [A bar popout's stroke flashes off its fill switching content on niri](issues.md#a-bar-popouts-stroke-flashes-off-its-fill-switching-content-on-niri)
- [Quickshell's wlr screencopy crashes the shell on niri](issues.md#quickshells-wlr-screencopy-crashes-the-shell-on-niri)
- [niri reports no position for a tiled window, nor other apps' layers](issues.md#niri-reports-no-position-for-a-tiled-window-nor-other-apps-layers)
- [Shift+Enter on an emoji doesn't type it on niri](issues.md#shiftenter-on-an-emoji-doesnt-type-it-on-niri)
- [A window takes the keyboard from a desktop module on niri](issues.md#a-window-takes-the-keyboard-from-a-desktop-module-on-niri)

Deferred by the maintainer (2026-10-29: "defer hyprland default workspace"; needs their reproduction):
- [Hyprland's default workspace doesn't highlight its first window](issues.md#hyprlands-default-workspace-doesnt-highlight-its-first-window)

Deferred by the maintainer (2026-10-29, Phase 13 step 2's gaps half: "defer for now, still unsure"):
- [The overlay's gaps can't be adjusted](issues.md#the-overlays-gaps-cant-be-adjusted)

Deferred by the maintainer (2026-10-29, plan #197: "defer"):
- [Surfaces touch a dead screen after the outputs go away](issues.md#surfaces-touch-a-dead-screen-after-the-outputs-go-away)

Deferred by the maintainer (2026-10-29: "move what is necessary to deferred"; Quickshell's to fix, #202):
- [Quickshell's I3 socket warns on every reload](issues.md#quickshells-i3-socket-warns-on-every-reload)

Deferred by the maintainer (2026-10-30, small gaps users notice at once: "log everything except notif sound … Build them into roadmap in the correct spot but deferred and issues (all should need a plan)"; Phase 13 features, each through [Items that need a plan](#items-that-need-a-plan) once taken up; notification sounds are the maintainer's own system sounds plan):
- [No keyboard backlight control](issues.md#no-keyboard-backlight-control)

Deferred by the maintainer (2026-10-31, the integrated menu's growing zone: "put this on hold - note that growing modules kinda needs a re-work or removal"):
- [An integrated top or bottom menu's zone follows its growing modules](issues.md#an-integrated-top-or-bottom-menus-zone-follows-its-growing-modules)

Deferred by the maintainer (2026-11-01, the clear-out's questions: side-edge submenus "defer - This takes quite a bit of thought to make consistent without an option."; the pill bar's frame lag "defer"; lock screen notification settings "defer"; Windows zone names, on leaving it logged, "agree"):
- [A side edge's submenus always open away from the edge](issues.md#a-side-edges-submenus-always-open-away-from-the-edge)
- [A pill bar's end reach trails a sliding popout's wall](issues.md#a-pill-bars-end-reach-trails-a-sliding-popouts-wall)
- [The lock screen has no settings for allowing or viewing notifications](issues.md#the-lock-screen-has-no-settings-for-allowing-or-viewing-notifications) (needs a plan once taken up)
- [Calendar times in a Windows zone name with no VTIMEZONE read as local time](issues.md#calendar-times-in-a-windows-zone-name-with-no-vtimezone-read-as-local-time)

Deferred by the maintainer (2026-11-06, answering the short decisions: "defer"):
- ["Colour the text by state" does nothing on a bar whose widgets have no fill](issues.md#colour-the-text-by-state-does-nothing-on-a-bar-whose-widgets-have-no-fill)
- [A menu at the screen-size cap can still lose a bar's depth](issues.md#a-menu-at-the-screen-size-cap-can-still-lose-a-bars-depth)
- [On Hyprland a click back in an older popout closes it with the newer one](issues.md#on-hyprland-a-click-back-in-an-older-popout-closes-it-with-the-newer-one)

## Unconfirmed
Bugs an agent's review or audit found and marked PLAUSIBLE: no code is written for one until it's confirmed (shown on screen or in a log, or traced in the code), and then its link moves back to its phase. They block no row; they're to get to eventually. PLAUSIBLE entries a human submitted (the maintainer's notes) stay in their phase, still not built until confirmed. The maintainer (2026-11-05): "just leave plausible code reviewed only found bugs in a new list to get to eventually (i.e not human submitted".

- [Eject may leave a USB stick powered on](issues.md#eject-may-leave-a-usb-stick-powered-on)
- [EdgePlacement logs a binding loop on _layout](issues.md#edgeplacement-logs-a-binding-loop-on-_layout)
- [Eight modules' full layouts need more room than their fullMin sizes, even inside the padding](issues.md#eight-modules-full-layouts-need-more-room-than-their-fullmin-sizes-even-inside-the-padding) (PLAUSIBLE in its exact px)
- [A stale exec-if check can block a widget after its exec-if changed](issues.md#a-stale-exec-if-check-can-block-a-widget-after-its-exec-if-changed)
- [The dock's menu and drag state outlive the icons they point at](issues.md#the-docks-menu-and-drag-state-outlive-the-icons-they-point-at)
- [A dock beside another edge's reserving dock is laid out as if that dock weren't there](issues.md#a-dock-beside-another-edges-reserving-dock-is-laid-out-as-if-that-dock-werent-there)
- [A pomodoro, timer or caffeine end due during a suspend fires up to an hour after waking](issues.md#a-pomodoro-timer-or-caffeine-end-due-during-a-suspend-fires-up-to-an-hour-after-waking)
- [An image sent without text to Anthropic carries a whitespace-only text block](issues.md#an-image-sent-without-text-to-anthropic-carries-a-whitespace-only-text-block)
- [Stop is ignored while chat.send still looks up the key](issues.md#stop-is-ignored-while-chatsend-still-looks-up-the-key)
- [The panel's relative times go stale while Tailscale's state stays the same](issues.md#the-panels-relative-times-go-stale-while-tailscales-state-stays-the-same)
- [A custom element sees another kind's element as its slot changes kind](issues.md#a-custom-element-sees-another-kinds-element-as-its-slot-changes-kind)
- [A headset's low-battery card gives way to Audio switching to that headset](issues.md#a-headsets-low-battery-card-gives-way-to-audio-switching-to-that-headset)
