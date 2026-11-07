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
- **Waits on the maintainer:** the [Live checks](#live-checks); Phase 13's "Needs a plan" and "Waiting for the maintainer" lists; entries marked as needing a decision or a choice; the [Deferred](#deferred) entries, to move to GitHub. [Unconfirmed](#unconfirmed) entries wait for a confirmation (on screen, in a log or traced), not a decision.

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
2. **Pick** (leader) the batch with [Taking the next step](#taking-the-next-step) steps 1–3, reading only the Full order, that phase's section (or the stage's bullets in [backend/roadmap.md](backend/roadmap.md)) and the items' issues.md entries; a batch is never wider than one row. A "needs a plan" item gets a plan PR ([Items that need a plan](#items-that-need-a-plan) step 1, by a fresh agent with a brief like step 3's) and the leader moves on to the row's next item; when only plans waiting for decisions are left in the row, stop and report them. An item that needs a decision or a forbidden action ends the batch before it (the items before it still go); when it's the first, stop and report instead of starting. That's an item that needs a maintainer decision (a changed default, whether a migration is worth it, a behaviour trade-off), or waits on a row that isn't `done`. An item that can only be built or confirmed in the live environment (a live action `AGENTS.md` › Never forbids, or a fix only the maintainer's session shows) never holds anything up (maintainer, 2026-10-29: "mark accordingly in the roadmap and don't let it hold everything up - I can get to that later"): it's built as far as tests and nested runs take it, or skipped, and listed under [Live checks](#live-checks); the batch and the row go on. An issues.md entry marked PLAUSIBLE, or one whose cause isn't traced in the code or shown, is skipped and stays logged (one an agent's review or audit found has its link moved to [Unconfirmed](#unconfirmed), maintainer, 2026-11-05: "just leave plausible code reviewed only found bugs in a new list to get to eventually (i.e not human submitted"; a human-submitted one stays in its phase): only code style, clear problems and breaks, and traceable bugs get fixes (maintainer, 2026-11-05: "clear code style and problems / breaks get fixes, and tracable bugs. Anything marked plausible will not receive any updates to the code or make it into a kerge").
3. **Brief** (leader), ten to fifteen lines plus two or three per item: the row and the items in order; each issues.md entry's title and its **Where**/**What**; what done looks like (the behaviour, and the entry removed with its link here); the docs to start from (`docs/dev/README.md` › Where to look, the recipe if one fits); the branch name `roadmap/<row>-<slug>`; and the stop conditions above, so the agent stops rather than guesses. A maintainer decision the item rests on is quoted word for word from roadmap.md or issues.md, with no step of the leader's own on how to build it (2026-10-26: a brief that added "so set the schema minimum to 5000" to a quoted decision broke saved configs), and a decision that seems to clash with its entry's title is a stop, not a reading. Every brief says: never `sudo`, `pkexec`, `su` or anything prompting for a password; a test needing root runs in a user namespace (`unshare -rm`), and what can't is skipped and reported (maintainer, 2026-10-30: "tell claude to stop asking for admin rights"). The brief also quotes [Rules](#rules)' Delete before adding and the rare-path cap (about 150 lines), so the agent stops there rather than building on.
4. **Implement** (a fresh `general-purpose` agent, given the brief): branch in the worktree from `origin/main`, never pushing it; then per item: implement, `scripts/dev/verify.sh` until `verify ok`, and commit it (row 20: a cluster is the item, committed one commit per file group, [Phase 11](#phase-11-audits-clear-out-and-hardening) step 2.6) with [Taking the next step](#taking-the-next-step) step 5 (statuses, `Done:` marks, issues.md removals) and the attribution trailer. An item it has to stop on is left out (reset to the last item's commit) and reported; the committed ones go on. The live session runs the maintainer's checkout, so a change rests on its tests, nested runs and the review; what only the live session can show is reported under **Not verifiable live**. It reports in at most 250 words: **Commits** (sha and item, one line each), **Changed** (one line per file group), **Verified** (the `verify ok` line, the tests run), **Not verifiable live**, **Filed** (issues.md titles added), **Stopped** (why, if it did).
5. **Gate** (leader): the branch is at the last commit's sha, `git status` is clean, `git diff --stat origin/main...HEAD` touches the batch's area plus `docs/dev/roadmap.md` / `docs/dev/issues.md`, the closed entries' headings are gone from issues.md, and the batch is within the size gate: `git diff --shortstat origin/main...HEAD -- . ':!**/*_test.go' ':!tests/' ':!docs/'` at about 800 changed lines or fewer, unless its commits are pure moves. An oversized batch isn't sent back to be cut: it stops, and the leader reports it with a proposed split. A failed gate goes back to the same agent once (by `SendMessage`, with the failing lines); a second failure stops.
6. **Review** (a second fresh `general-purpose` agent, so the review isn't anchored on the implementer's reasoning), on the local branch before anything is pushed: runs the `review-branch` skill with the batch's intent and `--fix`, commits its fixes after `verify ok` (one commit per round, never pushing), and reports in at most 200 words: findings fixed (by severity), **Questions**, unfixed **Blockers**, the new sha. Each round that fixed a Blocker or Major gets another, by a fresh agent, up to five rounds (maintainer, 2026-10-30: "up the Maxx to 5", "as long as there is a major fix it needs another review"); a round that fixed only minors ends it. Before that next round, if `origin/main` moved past the branch's base, the leader merges it in (`git merge origin/main`, conflicts by an agent, `verify ok`), so the round reviews the branch on today's main (maintainer, 2026-11-05: "after review round 1 ( before launching a second review round for either if necessary merge moved main in)"). Row 19's audit batches (three systems each, audited in parallel in worktrees of their own and combined into one branch before this step) get one review round: a round there that fixed a Blocker or Major opens the PR labelled `needs-decision` rather than starting another (maintainer, 2026-10-30: "let 5 finish but cap at one round. Implement accordingly to keep it cheaper as described"). A question with no product stake (how far a technical fix reaches) the leader decides, comments its reason on the PR and carries on (maintainer, 2026-10-29: "I don't care, as long as it is smartly implemented for the stack"). A product question (a changed default, a trade-off users notice, a migration, a takeover), a Blocker it couldn't fix, or a fifth round that still fixed a Blocker or Major (so no such fix merges unreviewed): push and open the PR as step 7 does, labelled `needs-decision` too, comment the findings on it, and stop.
7. **PR** (leader): `scripts/dev/verify.sh --all > <scratch>/verify.log; tail -3` ends in `all checks passed` (every CI check, so CI only confirms; a plain `verify.sh` checks only uncommitted changes, so on the committed branch it prints `nothing changed since HEAD`), then `git push -u origin <branch>` once (the guard passes only a named branch) and `gh pr create --label roadmap`; the body lists the row, each item with its commit and the issues.md entries it closed, and the reports' Verified and Not verifiable live.
8. **CI** (leader): `gh pr checks <n> --watch`. A failure goes to a fresh agent with the failing job's log tail (`gh run view --log-failed | tail -60`) to fix, run `verify.sh --all` and push once, at most twice; then stop with the PR open.
9. **Merge** (leader): first `git switch --detach` in the worktree (`--delete-branch` deletes the local branch, and with it a worktree holding it), then `gh pr merge <n> --squash --delete-branch` as a command of its own (a compound command doesn't match its allow rule), then `git fetch` and `git switch --detach origin/main` there (the live checkout is left alone). The squash message keeps each item's commit message as a bullet. A merged item whose report has a **Not verifiable live** that matters gets a line under [Live checks](#live-checks) in the next batch.
10. **After** (leader): rebuild and republish the maintainer's roadmap page, which lives outside the repo; the leader's memory names its builder and URL. Its statuses come from this file and backend/roadmap.md, so it's a build and a publish, never hand edits. Do this after every merge and at every stop. Stop the loop and report if [Ready for the autopilot](#ready-for-the-autopilot) is empty (maintainer, 2026-11-06: "have the autopilot stop itself when everything is done"), if this merge set a Full order row to `done` (the pause between rows, so the maintainer looks before the next one starts) or this was the session's third batch; otherwise schedule the next iteration. A report says what merged (PR links), where it stopped and why, and what the next batch is.

Never, besides `AGENTS.md` › Never: open a PR of roadmap.md or issues.md edits alone (a plan PR aside: an answer or a moved entry goes in the next batch's first commit), merge a PR without the `roadmap` label, put two rows or more than four items in one PR (row 20: more than one cluster), push before the review, skip the review or CI, or retry a stop condition. A wallpaper-only screenshot means the session locked while idle: stop and ask the user to unlock.

## Ready for the autopilot
The maintainer (2026-11-06): "right now, everything deferred or hold that it small and has a traced fix move to ready and waiting for the autopilot. After all of that is done the autopilot will stop. (i.e. unconfirmed, weird vaguely described ui problems from developer notes, and plans done stay)". So the loop takes only the entries listed here, grouped by area so a batch stays in one; when this list is empty it stops the loop and reports, whatever row 20 still holds. It opens no plan PR and no `needs-decision` PR: an entry that turns out to need a choice or isn't as traced is skipped and its link moved back where it came from.

Empty: every entry moved here on 2026-11-06 was fixed, or moved back where it came from.

## Live checks
What waits for the maintainer's own session (see [Running it unattended](#running-it-unattended) › Pick): a merged fix to confirm live, or an item only the live environment can build. None of it holds up a row; a confirmed check is deleted, a failed one becomes an issues.md entry.

**Bar, popouts, edge menus and the overlay:**
- Once the shell runs #279 (StandaloneBar removed), check the bar's blur and the border opening still sit right under a popout on a top, side and floating bar, and that a floating edge menu comes forward when engaged.
- Once the shell runs bar-popouts-02, on Hyprland and niri: a floating edge menu with Close on outside click, and the launcher attached and detached, close on a click on a window, a bar, the screen border and another monitor; a click in the edge menu's submenu (and a tray menu's) leaves it open; a pinned menu stays; with the launcher open, a click on a bar's launcher button closes it without reopening it, and one on a bar button opening the power menu or an edge menu leaves that open; with either open, hovering a bar widget whose popout takes the keyboard (Todo, Calculator, Stopwatch) opens that popout and leaves them open, and once it closes a click outside still closes them (on Hyprland they take their grab back); on Hyprland, with the launcher or the edge menu open under such a popout with its text field focused, a click on a window closes both and the window keeps the keyboard (a click back in the launcher closes both too: [known](issues.md#on-hyprland-a-click-back-in-an-older-popout-closes-it-with-the-newer-one)).
- Once the shell runs the bar rewrite (config v93), under Hyprland, niri and sway: switch a top bar between One bar and A pill per group, with the screen border on and off, and check windows and the widgets don't move; set Auto-hide on a bar and check the edge hover reveal and its slide (blur and shadow follow it), a workspace change and a widget's news showing it, a bar popout and an edge menu holding it, the bar editor holding the selected bar, `axiom ipc bar toggle focused` pinning it (windows make room) and `hide`, a fullscreen window over it, a side bar, and a bar stacked inside another; open an edge popout on a transparent bar's edge with a floating bar on it and check it opens past the floating bar.
- Once the shell runs compositor-20 (row 20), during Hyprland's or SwayFX's compositor-wide blur pause (a fullscreen window on another screen): a pill bar's end merged into another bar's corner shows no unfilled 1px row.
- Once the shell runs the floating popouts pass: on Hyprland, a detached OSD and a floating edge menu (detached) slide in from off the screen under a solid bar, a pill bar and the border, and a bar popout on a transparent bar or a floating bar with no islands from under its bar; with the overlay open they open over it, coming out of the bars' inner side (the frame line), and keep doing so if the overlay closes while they're open; over a fullscreen window the OSD, a floating edge menu opened by its keybind, the attached and detached launcher and the window switcher sit the compositor's outer gap from the screen's edges and slide in from off the screen (toasts use the same gap); under sway and niri, the same boxes come out of the bars' inner side (a floating bar's too), and over a fullscreen window slide in from the screen edge; with blur on and a detached box's or dock's animation set to Fade, under niri no blurred box shows before it fades in, after it fades out, or while a fading dock is hidden.
- Once the shell runs #329 (bar-popouts-03): an open edge popout on a transparent bar's edge keeps its layer and namespace when the bar changes, auto-hides, or the overlay opens (Hyprland).
- On sway, niri and Hyprland with `Overlay.closeOnOutsideClick` on, open the overlay, click another monitor, the screen border and a floating bar's gap (it stays open), then its own background (it closes) (#378).
- With an edge menu that closes on leave, run `axiom edge-menu open <id>` from a bind and check it stays up until the pointer enters and leaves it (#379).
- Open the Calendar popout and start a new event: the popout doesn't grow or flash as the editor opens (#379).

**Dock, launcher and icons:**
- Confirm the missing app icon fallback in the launcher and dock with an icon theme lacking `applications-system-symbolic` (#196).
- Once the shell runs row 20's dock menu (MenuList), right-click a dock icon under sway and Hyprland and check Up/Down, Enter and Escape work in its menu and the app's window gets the keyboard back once it closes (nested niri, its menu opened by a test hook, did).
- Once the shell runs #230, check app and window icons in the dock, launcher, workspace widgets, workspace overview and switcher (AppIconManager; a window class's icon is cached until desktop entries change).
- Once the shell runs #339 (bar-popouts-07), under niri, sway and Hyprland: with a dock and a bar popout open beside it, check the dock's reserved footprint matches its drawn shape (fillets only where it has them) and the popout doesn't overlap it.
- With a held hover or intellihide dock at a distance above 0, check that once the pointer has reached the dock the strip between it and its edge no longer keeps it open or takes clicks, that the strip comes back when the pointer comes in from the trigger again, and that a dock shown by a bind starts without it (#382).

**OSD, toasts and notifications:**
- With the OSD's parts: hover a part while another comes in (`holdStill` puts it past the others, nothing moves), leave and watch each part keep its own time, two ending within 750 ms close together (the card folds in, then the OSD slides away); and a bottom-edge OSD stacks upward.
- On sway and on Hyprland, show a few notifications, detached and attached, and check each toast blurs behind (the first after launch too): they're blur-backed shapes now, no longer popups of a 1x1 layer window (notifications revamp).
- Once the shell runs the OSD's statuses (config v87), pick Caps Lock, Num Lock, Keyboard layout, Microphone and Audio under an OSD's Status icons (the default has them; a custom OSD gets them in Settings → Dock & OSD): toggle Caps Lock and Num Lock, switch the layout, mute the microphone and switch the output in the audio mixer, and check each shows its icon, highlighted, on the focused screen and that a volume key while one shows swaps back to the bars without the OSD moving; that plugging in a headset no longer opens the bars; and that nothing shows in the first moments after a reload. Then on a laptop, the power profile, charger, Wi-Fi, Bluetooth and airplane mode icons (airplane mode's highlight isn't taken by its radios switching), and Now playing on a track change.
- Once the shell runs the OSD's VPN, screen recording, camera and screen sharing statuses, add them to an OSD: bring a NetworkManager VPN or Tailscale up and down from the Vpn widget, then drop it (`nmcli connection down`, or stop tailscaled): coming up shows a card with its name, Connected and its address, a drop the struck-through icon, and switching from one VPN to another one card; start and stop a recording (a click on the lit icon stops it); open a browser's camera test and share a screen in a call: a card names the browser and says what it started, and stopping shows the struck-through icon (confirmed under niri with Vesktop; check Hyprland's and sway's portals too); join a call with the camera and microphone: one card, "Using the camera and microphone"; turn the OSD's Detail cards off: the same changes show as their icons. Join a Wi-Fi network (a card with its name and signal) and, on a laptop, plug in the charger (a card with the level and the time to full). Nothing shows in the first moments after a reload.
- Once axiom runs a binary with the `camera` topic and the shell its PrivacyManager, join a Vesktop call (or any Chromium/Electron app's camera test) with the camera on: the Privacy widget shows the camera with the app's name, and an OSD with the `camera` status shows its card; turning the camera off brings the unlit icon. Meanwhile `camera.get` lists the app (its flatpak id, else its process name).
- Once the shell and binary run platform-03, take a screenshot with an annotator installed and click the notification's Edit in … button (it opens the annotator), and use Settings → Notifications' Show: both toast as before, and `scripts/log.sh` shows no `[NotificationManager] Sending`.
- Once the shell runs compositor-20 (row 20): with blur on and translucency below 100, a toast's tone matches the bar and edge popout beside it, and doesn't jump when the blur pauses or resumes.

**Compositors and input:**
- On Hyprland 0.57 with `Input` pointer settings on and acceleration left at `default`, check Hyprland reports no config error for `input.accel_profile` (#238).
- Once the shell runs #284, under sway and SwayFX reload the config (Super+Shift+C): the bars and popouts keep axiom's outer gaps (gapsOut and each output's reserved space match the look), and windows opened after the reload get axiom's blur and shadows.
- Once axiom runs a build with row 20's compositor-05, start a nested niri in managed mode with a broken `user/*.kdl` (`scripts/dev/nested.sh niri --managed`) and check the Compositor card reports niri couldn't load its config rather than loaded; and with a stale `NIRI_SOCKET` (or `HYPRLAND_INSTANCE_SIGNATURE`) left in the systemd user environment under another compositor, check the shell and `axiom daemon logs` use the compositor running.
- Once axiom runs row 20's compositor-06, under a sway started as `sway -c ~/.config/i3/config` (a scratch copy), check the Compositor page's Add it for me edits that file (not `~/.config/sway/config`) and Managed says it can't switch, naming that file.
- Once the shell runs compositor-12 (row 20), under niri: drop a window from a stacked column onto another column in the overview (only that window moves, the output stays on its workspace), open an app with `clearOnFocus` notifications (they clear when its window opens), and unplug the monitor showing the overview (the next toggle opens it).
- Once the shell runs compositor-13 (row 20): with the window look's defaults on sway, the gap to the screen edges is 6 px (the setting), not 9; on niri, with `blur { off }` in a `user/*.kdl` (managed) or in the user's config (included), axiom's blur still shows; the Translucency card offers "Set the compositor's blur" when the blur comes only from the user's own config; and Hyprland's gaps (and the bars that subtract them) don't drop to 0 through a busy reload.
- Once the shell runs compositor-14 (row 20), under niri: the bind inspector's Fire on release is greyed with "niri can't do this." (on for Restart axiom, and can be turned off there), Blur contrast, Fullscreen opacity and Window dimming are hidden and Focus windows that ask for it greyed with the same note, and Wide active shows in every workspace layout; under Hyprland all of them are editable.
- Once the shell runs compositor-18 (row 20), on a laptop under Hyprland: with the Mouse and Touchpad parts on, give the touchpad its own speed, acceleration and left-handed and check the touchpad takes them while a mouse keeps the Mouse part's (right after login too: Hyprland's first load lists no devices, the daemon's eval sets them), a second speed change applies without a reload, and the touchpad's natural scrolling and tap to click still hold; with the Touchpad part off, the touchpad follows the Mouse part. A nested Hyprland has no touchpad to check this on.
- Once the shell runs the input sources (Phase 13), with fcitx5 running and `Input.keyboard.method.enabled` saved on: add Mozc, Save, and check fcitx5-configtool shows the sources' list, switching from the bar widget, the popout, `axiom ipc inputSources next` and fcitx5's own hotkey all move the compositor's layout and the OSD (no OSD on focusing a window with its own input method).
- Once the shell runs the input sources, in managed mode under Hyprland, niri and sway: turn on the input method, log out and in, and check fcitx5 starts and `XMODIFIERS` / `QT_IM_MODULES` are set in apps; with ibus installed, the same with `Input.keyboard.method.framework` `ibus`.
- Once the shell runs the input sources, with two layouts and the second one in use, lock and unlock with the password (the lock screen's module offers the layouts alone), and lock mid-composition in a Mozc preedit and unlock.
- Once the shell runs the input sources, with `ThemeIntegrations.fcitx5` on and its hookup applied, check the candidate window follows the axiom theme and changes live on a theme switch, and `candidateFont` empty keeps fcitx5's own font.

**Workspaces and monitors:**
- Once the shell runs the workspace grid's centre start, with `Workspaces.layout` `grid` (3 × 3): log in under sway and Hyprland with two monitors and check each starts on its block's centre (5, 14); restart axiom after moving away and check nothing moves; on sway, switch the layout to `perMonitor` and back to `grid` and check every monitor goes to its centre, windows kept on their workspaces. Nested Hyprland (one output) showed the start, a reload leaving workspace 1 alone, and perMonitor → grid going to 5.
- On sway, with a laptop panel that has no serial (or a profile saved under niri for a PNP(…) monitor), Monitors page → Apply changes that monitor, and after a sway reload the panel is set as the profile says (compositor-09).
- Once the shell runs #318, start a trial monitor Apply that turns a monitor off (Hyprland): the Keep/Revert prompt stays, the countdown reverts it and the monitor comes back on; a profile mirror saved under Hyprland can be turned off on the Monitors page under sway and niri; the monitor prompt grabs real clicks.
- Once the shell runs row 20's compositor-11: log in under Hyprland with a 3 × 3 grid and a profile naming the monitor by `desc:`, and check the session starts on the block's centre (5), not in 10–18; if `scripts/log.sh` shows `remapping workspaces` at the start, add its `from`/`to` layouts to [the startup remap entry](issues.md#a-remap-runs-at-startup-from-the-layout-before-the-config-loaded); on sway, disable an output (`swaymsg output <name> disable`) and check `CompositorManager.outputs` no longer lists it and the other monitor's perMonitor workspaces start at 1; with a fullscreen video on a named sway workspace, the dock and toasts stay off it.

**Lock screen, polkit and greeter:**
- Lock once and check `scripts/log.sh` shows no `[ModuleGrid] … overlaps another` (#198).
- Once the shell runs #201, with `Polkit.enabled` on, restart axiom and reload a few times, and check `scripts/log.sh --all` shows no `[PolkitManager] Could not register as the polkit agent` and Settings → Authentication prompts says running.
- Once the shell runs the lock-survives-reload fix, let the idle lock come up, save a loaded QML file, then unlock with the password: the lock screen stays up throughout, `scripts/log.sh --all` shows no `Session lock object was destroyed without unlocking`, and the next save after unlocking reloads. Nested niri, sway and Hyprland showed it with a test unlock hook; the real idle lock and PAM only the live session can.
- Once axiom runs a binary built with row 16's greeter progress fix, update the login screen for real and check the card reads "Installing now..." after the password, then that it's up to date, and that the "Login screen update" notification is gone.
- Once axiom runs a binary built with platform-02, run `axiom lock` under Hyprland and check `axiom daemon logs` has no `the shell didn't confirm the lock: starting it locked` (a nested Hyprland acknowledged the lock after about 5 s; the daemon now waits 10 s more for a shell holding the lock), and whether a real Hyprland is ever that slow.
- Once the greeter runs platform-02, with a bundle setting two keyboard layouts (`us,de`), log out to the login screen under sway and Hyprland: its keyboard layout module switches between both from the start.
- Once the shell runs platform-02, start a shell locked (`axiom lock` confirmed too late, or one restarted while locked), unlock with the password, then save a QML file: the reload doesn't lock again.

**Config and settings:**
- Once the shell runs #287 (config-02), edit config.json by hand, then within a moment change a setting in the shell: the save is refused, the shell shows the hand edit, and the next change saves.
- Once the shell runs #288 (config-03), turn Polkit's "Use axiom's prompt" or Idle's "Handle idle" on in Settings without saving and check nothing starts (no agent swap, hypridle untouched), then Discard; and in the launcher `/config Polkit.enabled` offers only Show in settings.
- After a save axiom refuses (e.g. right after a hand edit of config.json), the editor's edits show live again on the running bars and settings (#293).
- Settings › System (the settings overhaul): the System info card's facts on this machine (its distro logo, GPUs named from pci.ids); Rename… asks through axiom's polkit prompt and the new name shows; Copy system info pastes lines with no hostname. In Date & time, pick another time zone (polkit asks), check the bar clock and the card follow it without a restart, then put it back; turn Set the time automatically off and on again. In General, change your picture (the Account card, the login screen once AccountsService has it, a Greeting module with Picture on the lock screen), and change your password with a wrong current one, a weak new one, then a real one. Pick another browser and terminal under Default apps and check `~/.config/mimeapps.list` / `xdg-terminals.list` changed and the Browser and Terminal keybinds open them (after a managed or included config is written again with `axiom open`), and a notification link and a screenshot open in their defaults.

**Daemon, CLI and dev mode:**
- Once the shell runs row 14's re-exec fix, with axiom in dev mode, save a Go file while a note is being saved or the theme applied, and check `scripts/log.sh` shows no `the connection to axiom closed` from `[FileManager]`, `ThemeManager` or `MediaManager`, and `axiom daemon logs` no `checkupdates failed (-1)`.
- Once axiom runs a binary built with row 15 (stage 8), pick a file from Settings (a wallpaper or a path setting) under each compositor and check the portal's picker opens and its choice lands, then with the portal stopped check zenity or kdialog opens instead; and run `axiom bug-info` under Hyprland, niri and sway and check its Compositor and monitor lines.
- Once axiom runs a binary built with platform-04, in dev mode: `git switch` to an older branch and `git pull` (or touch a Go file) within the build's time; `axiom daemon logs` shows `dev build done, but the source changed meanwhile: building again` and one more build, the image re-exec'd last is the tree's (`axiom config status` loads, no `running on the defaults`). Then switch to a branch whose config version is older than config.json's: the shell keeps showing the config it had, not the defaults.
- Once axiom runs platform-04 in dev mode, bump `protocol` in `qml/config/json/backend.json` and save a Go file: after the re-exec, `axiom ipc …` from a bind and a terminal (the installed `~/.local/bin/axiom`, still on the old protocol) works through the dev build, and the shell's calls work with no QML reload (`scripts/log.sh` shows no `refused the hello`). Put the protocol back after.
- Once axiom runs platform-04 in dev mode, save a QML file and a Go file together a few times (as a rebase does): every re-exec's shell hello is accepted (`scripts/log.sh` shows no `only the shell axiom runs may connect as the shell`, `axiom daemon status` lists the shell).
- Once axiom runs a binary with the newer-client re-exec (platform-04), the stuck case: replace `~/.local/bin/axiom` with a build whose `protocol` is one more (and the tree's `backend.json` too) without re-execing the daemon, then run `axiom ping`: it says hello again after a second and works, `axiom daemon logs` shows `a client speaks a newer protocol: re-executing`, the shell stays up; with the tree's `backend.json` left at the old number, `axiom ping` is refused with `update axiom` and nothing re-execs.

**Devices and network:**
- Removable drives (a USB drive confirmed live, every path): plug in a real LUKS stick (the Locked card's click shows the passphrase field, a right and a wrong passphrase) and a memory card in a card reader (inserting and taking out the card is Connected / Disconnected, and its eject leaves the reader).
- On an NVIDIA machine without an AMD card, once axiom runs the graphs'-history change: show a GPU stat or graph and check it fills from the streamed `nvidia-smi` (`pgrep -c nvidia-smi` is 1 while shown, 0 a few seconds after closing, with no GPU graph configured), and on a laptop with a runtime-PM dGPU that the card stays `suspended` (`power/runtime_status`) with nothing open. If the GPU reads stay missing, nvidia-smi isn't printing each line as it comes when piped: fall back to one-shot queries off the sample path.
- Once axiom runs a binary with the VPN controls, connect a real OpenVPN with `networkmanager-openvpn` installed that asks for a password: the field shows in its row, a wrong password reads "Wrong user name or password", and the right one connects. Also check `nm-applet` running beside it still gets its turn after Cancel.
- With a DDC/CI monitor, press brightness up with the OSD shut: `scripts/log.sh` shows no failed `brightness.get`, the bar doesn't jump back, and the next press steps from the new level (an own set now marks its write before the OSD's refresh runs).

**Apps and services:**
- Once axiom runs a binary built with #200 (its qs command line has `--log-rules`), click into a desktop Notes module and back to a window, and check `scripts/log.sh` shows no `Trying to disable` from `qt.qpa.wayland.textinput`, under niri, sway and Hyprland. Before the fix niri logged 205 of them (`Trying to disable … but 0x0 is focused`, 2026-10-29), so the path reproduces there (#200).
- Once axiom runs a build with Phase 10 (row 17), set up 5–10 popular Waybar custom scripts (`~/waybar-test-scripts`: media, updates, weather, crypto, VPN, …) from the Custom widgets page alone, through the Import from Waybar box or the presets, and check each runs unchanged on a bar and as a module, under niri, sway and Hyprland (Phase 10's "done when").
- Once the shell runs clear-out core-ui-theming-02 (row 20): with two players open, play one then the other and check the Media widget and NowPlaying follow the one playing (and a player picked in NowPlaying stays until another starts); with no Media widget or NowPlaying shown, check the position isn't ticking (a temporary `console.log` in `updatePosition` stays quiet while music plays); with a scheduled theme, set the other mode by hand (dark while light is scheduled) and force a reload: it stays, and goes back only at the next scheduled switch or a fresh start (logout, or the shell restarted); likewise night light and do-not-disturb.
- Once axiom runs a binary built with row 20's features-09, ask a fast provider (Groq, Cerebras, or a local model) for a long reply in the chat: it streams as before, and `axiom daemon logs` shows no `dropping a peer that stopped reading` (the reply's pieces are gathered while the queue to the shell is backlogged; a Go test shows it, not a real shell that stalls).
- Once the shell runs #362, a start or a reload logs no `Property 'fromEntries'` TypeError from MediaManager, and a player already playing at the start is picked.
- Screen sharing ([screen sharing](features/screen-sharing.md)), once axiom runs a build with it: under Hyprland, niri and sway turn on Settings › Screen sharing › Use axiom's picker, Apply the card's line and Restart the portal; share a screen, a window and (Hyprland) a region in Discord and in a browser's screen-share test, and check the picker shows once per share (Discord's repeats answered without it); turn it off and check the portal's own picker is back; with the shell stopped, check sharing still works through the portal's own. Under niri also check the cast ends when the shared window closes, and an app that asked to remember shares again without asking.

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
- [A mirror or a monitor a profile turns off keeps its windows re-homed after](issues.md#a-mirror-or-a-monitor-a-profile-turns-off-keeps-its-windows-re-homed-after) (reviewing the hotplug hardening branch; needs the maintainer's call)
- [A remap runs at startup, from the layout before the config loaded](issues.md#a-remap-runs-at-startup-from-the-layout-before-the-config-loaded) (investigating Hyprland starting on workspace 10)
- [TestDiscoverCalDAV failed once under verify.sh --all](issues.md#testdiscovercaldav-failed-once-under-verifysh---all) (reviewing the guard's leading `cd`, config-05)
- [TestLogindLockAndSleep failed once under verify.sh](issues.md#testlogindlockandsleep-failed-once-under-verifysh) (the same)
- [A push of a named branch can land on main through git's push config](issues.md#a-push-of-a-named-branch-can-land-on-main-through-gits-push-config) (reviewing the guard's gh and push allowlists)
- [The daemon's other own commands still start outside command.Children](issues.md#the-daemons-other-own-commands-still-start-outside-commandchildren) (moving the daemon's own commands to command.Run)
- [axiom config validate checks the install's config with the binary's schema under dev mode](issues.md#axiom-config-validate-checks-the-installs-config-with-the-binarys-schema-under-dev-mode) (fixing the daemon's config watch)
- [A hover-opened held edge menu closes before the pointer crosses from its edge to its box](issues.md#a-hover-opened-held-edge-menu-closes-before-the-pointer-crosses-from-its-edge-to-its-box) (reviewing the dock gaps batch)
- [Making a note or folder creates a linked notes folder that doesn't exist](issues.md#making-a-note-or-folder-creates-a-linked-notes-folder-that-doesnt-exist) (fixing the notes folder entries)

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

Done (row 16 and since): niri's own overview and window switcher (`WorkspaceOverlay.compositorOverview`, `WindowSwitcher.compositorSwitcher`), `Overlay.moduleBorders`, a test notification, caffeine on a timer, Markets ([markets](features/markets.md)), the notifications revamp ([notifications](features/notifications.md)), the overlay and popouts no longer closing each other (#211), the window switcher's blur and key release on sway and niri (#212), low levels kept in their rounded troughs, a Caps Lock warning in password fields (#270), the OSD's statuses (#272) and input sources ([input sources](features/input-sources.md)).

Found meanwhile:
- [Submenus don't always get their blur backing](issues.md#submenus-dont-always-get-their-blur-backing)
- [A greeter-only module validates on any page](issues.md#a-greeter-only-module-validates-on-any-page) (back from Ready for the autopilot, 2026-11-06: rejecting it can stop an existing config from loading; whether a migration removes misplaced modules first is a decision)
- [BlurManager.paused and WallpaperManager.rotationHeld read undefined on a reload](issues.md#blurmanagerpaused-and-wallpapermanagerrotationheld-read-undefined-on-a-reload)
- [A theme can't be generated from an avif or jxl wallpaper](issues.md#a-theme-cant-be-generated-from-an-avif-or-jxl-wallpaper) (a choice: a Go decoder dependency, or the shell handing over the image Qt decoded)

Needs a plan:
- [The chat has no slash commands to control it](issues.md#the-chat-has-no-slash-commands-to-control-it)
- [Video wallpapers](issues.md#video-wallpapers) (an idea from the wallpaper transitions branch)
- [A pill bar stacked inside another pill bar grows its pills out of nothing](issues.md#a-pill-bar-stacked-inside-another-pill-bar-grows-its-pills-out-of-nothing)
- [A bind can't be limited to some compositors](issues.md#a-bind-cant-be-limited-to-some-compositors) (the maintainer's request, 2026-11-02)
- [Quick actions can't hold custom toggles or commands](issues.md#quick-actions-cant-hold-custom-toggles-or-commands) (set aside from the unified-actions branch, 2026-11-06)

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
- [Bluetooth pairing that asks for a PIN or a passkey](issues.md#bluetooth-pairing-that-asks-for-a-pin-or-a-passkey)
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
- [A VPN's password request can go unseen](issues.md#a-vpns-password-request-can-go-unseen)

## Unconfirmed
Bugs an agent's review or audit found and marked PLAUSIBLE: no code is written for one until it's confirmed (shown on screen or in a log, or traced in the code), and then its link moves back to its phase. They block no row; they're to get to eventually. PLAUSIBLE entries a human submitted (the maintainer's notes) stay in their phase, still not built until confirmed. The maintainer (2026-11-05): "just leave plausible code reviewed only found bugs in a new list to get to eventually (i.e not human submitted".

- [Eject may leave a USB stick powered on](issues.md#eject-may-leave-a-usb-stick-powered-on)
- [EdgePlacement logs a binding loop on _layout](issues.md#edgeplacement-logs-a-binding-loop-on-_layout)
- [Eight modules' full layouts need more room than their fullMin sizes, even inside the padding](issues.md#eight-modules-full-layouts-need-more-room-than-their-fullmin-sizes-even-inside-the-padding) (PLAUSIBLE in its exact px)
- [A stale exec-if check can block a widget after its exec-if changed](issues.md#a-stale-exec-if-check-can-block-a-widget-after-its-exec-if-changed)
- [A device's own level arriving late brings the OSD's bars out beside its card](issues.md#a-devices-own-level-arriving-late-brings-the-osds-bars-out-beside-its-card)
- [The dock's menu and drag state outlive the icons they point at](issues.md#the-docks-menu-and-drag-state-outlive-the-icons-they-point-at)
- [A dock beside another edge's reserving dock is laid out as if that dock weren't there](issues.md#a-dock-beside-another-edges-reserving-dock-is-laid-out-as-if-that-dock-werent-there)
- [A pomodoro, timer or caffeine end due during a suspend fires up to an hour after waking](issues.md#a-pomodoro-timer-or-caffeine-end-due-during-a-suspend-fires-up-to-an-hour-after-waking)
- [An image sent without text to Anthropic carries a whitespace-only text block](issues.md#an-image-sent-without-text-to-anthropic-carries-a-whitespace-only-text-block)
- [Stop is ignored while chat.send still looks up the key](issues.md#stop-is-ignored-while-chatsend-still-looks-up-the-key)
- [The panel's relative times go stale while Tailscale's state stays the same](issues.md#the-panels-relative-times-go-stale-while-tailscales-state-stays-the-same)
- [A custom element sees another kind's element as its slot changes kind](issues.md#a-custom-element-sees-another-kinds-element-as-its-slot-changes-kind)
