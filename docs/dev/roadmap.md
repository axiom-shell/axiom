# Cleanup roadmap

> **Files:** this file, [issues.md](issues.md)
> **Config:** none
> **Related:** [Moving the service layer to the axiom binary](backend/roadmap.md), [Known issues](issues.md), [Developer docs](README.md)

The phased plan for getting the repository into an excellent, clean state: correct on its rarely taken paths, organized so each file has one job and an obvious home, equal on every compositor, quiet in its log, and documented without excess. It turns [issues.md](issues.md) into an order of work: every entry there is linked from the phase that resolves it.

It runs alongside [the backend roadmap](backend/roadmap.md), which moves the services' side effects into the axiom binary and is likely to land first. That roadmap owns the migration; this one never restates its stages, only points at them and lists what waits for them.

### Rules
- **One batch, one PR; one item, one commit.** A batch is one to four items of the same row that sit in the same area, about 800 changed lines at most, so a review still reads it whole. Each item is its own commit ending with `scripts/dev/verify.sh` printing `verify ok`, and a move is a commit of its own that changes no behaviour (its diff reviews as a rename). Batching is what keeps CI's fixed cost (a run per push) per batch, not per item.
- **Delete before adding.** A fix first looks for what to remove: a mechanism made unnecessary, a duplicate, a special case the general path already covers. Between two fixes that work, the smaller one wins, and a fix that makes the code shorter is the best kind. Each PR body states its net lines (QML, Go, scripts; tests and docs apart).
- **A rare path gets the smallest fix, or stays logged** (decided 2026-10-26, after #107 and #108 spent about 840 lines holding the compositor mode while config.json doesn't load, and opened three new entries doing it). A fix for a path a user rarely takes that grows past about 150 lines (tests apart) stops and becomes a plan ([Items that need a plan](#items-that-need-a-plan)), or the entry stays open. Never a stopgap that a later stage then has to delete.
- **The batch size is a gate, not a guide.** Over about 800 changed lines (moves, generated files and tests apart), the batch is split before review, never reviewed whole.
- **A bug that got past the checks adds a check.** When a mechanical check could have caught it, the fix adds that check (or a ratchet), or its PR says why none could. So the guardrails grow from what actually went wrong, and [Phase 11](#phase-11-audits-clear-out-and-hardening) step 0 revamps them rather than starting them.
- **A decision is settled before it's built.** An item resting on a choice the maintainer hasn't made, or might change, stops for the decision first. #116 built a topic floor and #120 removed it the next day.
- **A fix removes its entry from issues.md and its link here** in the same change; a phase is done when its list is empty. A new issues.md entry gets a link in the phase that will fix it.
- **Waits for a backend stage** means the item touches code that stage deletes or rewrites: it's done in that stage's change or after it, never before (no polishing code about to go). Items without one can run at any time, in parallel with the backend roadmap.
- Phases are grouped by kind, not run in number order: [Full order](#full-order) interleaves them with the backend stages. Three rules set it: moves land in quiet windows between stages (they collide with everything); enforcement (archtest, the contract check) lands before the stages that add packages; and nothing polishes code a stage will replace.

### Done means
- `scripts/dev/verify.sh --all` is green, and a reload logs only `Reloading configuration...` and `Configuration Loaded` under Hyprland, niri and sway.
- Every "needs a plan" item is decided: built from its plan, or listed under [Deferred](#deferred) and moved to GitHub by the maintainer.
- `scripts/quickshell-io-allowlist.json` lists only the permanent funnels (`BackendManager`'s socket, `FileManager`'s blocking read).
- No singleton over about 800 lines outside the pure helpers and the compositor backends; every file sits in the folder its rule names.
- `archtest` enforces the backend's dependency direction; the shell–daemon method shapes are checked on both sides.
- The root `AGENTS.md` is 12 KB or less; generated docs are built, not committed.
- [The launch gate](#the-launch-gate) is met, and axiom is posted for testers.

### Alignment with the backend roadmap

| Phase | Waits for (backend stage) | Folds into a stage |
|---|---|---|
| 0. Decisions and quick wins | none | none |
| 1. Integrity | none | the config save path → stage 7 |
| 2. Finish stage 2 | is stage 2 | clipboard, night light |
| 3. QML structure | none | services a stage empties are folded in that stage; ChatProvidersCard → stage 5, the `KeybindManager` split → stage 7 |
| 4. Backend structure and contract | none (lands before stage 7, so its switch to path ops is checked) | none |
| 5. The allowlist | stages 3–7 | is those stages |
| 6. Compositor parity | stage 7 (one compositor writer left); runtime-only bugs: none | none |
| 7. Fit, geometry, performance | the chat lists → stage 5 | none |
| 8. A clean log | stage 6 for the socket warnings; the rest: none | none |
| 9. Docs, tooling, process | `config-v2.md` → stage 7 | none |
| 10. Custom JSON widgets | stage 3b (streamed commands, JSON) | none |
| 11. Audits, clear-out and hardening | every row before it | none |
| 12. Memory footprint | none | the chat cache → stage 5 |
| 13. The maintainer's notes | none | none |

### Full order
Both roadmaps as one sequence. A row starts when the one above it has merged; the parallel lane fills the gaps at any time. **Status** is `done`, `in progress` (normally one row), `next` (the row after it), `later`, or `on hold` (skipped for now by the maintainer; it blocks no later row); it's kept current by [Taking the next step](#taking-the-next-step), so the first row neither `done` nor `on hold` is always where work resumes.

| # | Status | Work | Why here |
|---|---|---|---|
| 1 | done | Backend stage 2: night light, then clipboard (and [Phase 2](#phase-2-finish-stage-2)) | In progress; finish it before anything else churns the same files. |
| 2 | done | [Phase 0](#phase-0-decisions-and-quick-wins): stop committing generated docs | Right after stage 2 merges, so it doesn't collide with that work's regenerated docs; every later diff shrinks. |
| 3 | done | [Phase 1](#phase-1-integrity), except the entries stage 7 fixes | Data and session safety first; touches nothing a stage deletes. The binds-child segfault was taken first, because its flaky test failed CI on unrelated PRs. |
| 4 | done | [Phase 4](#phase-4-backend-structure-and-contract) | archtest and the contract check land before stages 3 to 6 add packages and before stage 7 rewrites saves, so both are checked as they're written. Two contract items were added after the row's first pass (strict param decoding, and the check failing on calls it can't read), so the check stops growing a shape at a time. |
| 5 | done | [Phase 3](#phase-3-qml-structure)'s moves and splits (not `KeybindManager`), and [Phase 5](#phase-5-the-allowlist)'s `execDetached` quick wins | One quiet window for every move, while the backend roadmap sits between stages. |
| 6 | done | Backend stage 3: brightness | Small; a first stage under the new checks. |
| 7 | done | [Backend stage 3b](backend/roadmap.md): exec (polled and streamed commands, JSON) | Right after brightness, another small stage under the new checks; ahead of stage 6 because the planned custom JSON widgets build on it, and stages 4 and 5 don't touch `CommandManager`. |
| 8 | done | Backend stage 4: scripts | The largest stage (theming, calendar, hookup, self-update, greeter installer). |
| 9 | done | [Phase 12](#phase-12-memory-footprint) step 0 and the shell's THP opt-out ([memory](core/memory.md) › Transparent huge pages) | Small and the largest likely win; its numbers order the rest of the phase, and it touches nothing stage 5 does. |
| 10 | done | Backend stage 5: HTTP | Resolves `ChatProvidersCard` (Phase 5) and unblocks the chat lists (Phase 7). |
| 11 | done | Backend stage 6: the funnels | Changes the compositor sockets behind several log warnings. |
| 12 | done | Backend stage 7: the config path, with the `KeybindManager` split | Closes the takeover leak, the save order and what a config.json that doesn't load still breaks; a thin `compositor.inputs` changes what `KeybindManager` reads, so it's split once, on the new shape. |
| 13 | done | [Phase 6](#phase-6-compositor-parity) | After stage 7 only Go writes compositor configs, so a sway or niri fix lands once, not in both renderers. |
| 14 | done | [Phase 8](#phase-8-a-clean-log) | After stage 6, the socket warnings are gone or real. |
| 15 | done | Backend stage 8: the last scripts (`pick_path.py`, `bug_info.sh`) | Small, with nothing waiting on it; after stage 7 so it doesn't collide with the config path, and before the audits so they cover it. |
| 16 | on hold | [Phase 13](#phase-13-the-maintainers-notes): the maintainer's notes | Bugs and small features from the maintainer's own use; after the parity and log rows (some are compositor-specific, and those land there), before Phase 10 so the last feature and the audits are built on them. On hold (maintainer, 2026-10-29: "put maintainers notes on hold (mark it to be skipped for now), and continue forward on Audits, clear-out, and hardening"). |
| 17 | done | [Phase 10](#phase-10-custom-json-widgets): custom JSON widgets, with their editor page | The last feature before testers: sway and niri users mostly come from Waybar, and this runs their custom scripts. On stage 3b's streamed commands; after the cleanup rows, so it's built on the final structure, and before the audits, so they cover it. |
| 18 | done | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 0: audit and tighten the guardrails (checks, tests, CI, agent rules) | The architecture is final once stage 7 and Phase 10 are in, so stricter checks aren't rewritten by a later stage; before the system audits, so the audits, the clear-out and the hardening all run under them. |
| 19 | in progress | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 1: a full audit of every system | Nothing left to build, so every finding is about the code testers will run. |
| 20 | next | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 2: clear out issues.md, then audit again | Fixes after the audits, so the list isn't refilled behind them; the second pass catches what the fixes broke. |
| 21 | later | [Phase 11](#phase-11-audits-clear-out-and-hardening) step 3: 1–2 weeks of hardening, frozen | The maintainer drives sway and niri daily; only fixes land. |
| 22 | later | [Phase 9](#phase-9-docs-tooling-and-process), then post for testers | Last, so the docs describe the final shape; the post follows [the launch gate](#the-launch-gate). |

**Parallel lane** (any time, between rows): [Phase 7](#phase-7-fit-geometry-and-performance); [Phase 12](#phase-12-memory-footprint)'s other entries, before row 13 (Phase 6), so the parity pass checks the windows they change; parity bugs outside the compositor writer (nested niri freezing); log warnings no stage touches (the notification avatar, missing app icons, singleton properties on reload).

**Binaries** (parallel lane, run by its own session on `binaries/*` branches; maintainer, 2026-10-27: "Rolling CI build (Recommended)"; tags: "Download, build fallback (Recommended)"; greeter main: "Allow via CI build (Recommended)"): every clone takes the official binary built from the commit it checks out ([packaging](packaging.md) › Edge builds), `go` only as the fallback.
- done: the edge prerelease (`.github/workflows/edge.yml`) and the shared `release`, `release/fetch` packages (#144, #145); the greeter's `main` channel through edge (#147); self-update downloading the binary (#148); install.sh downloading before it builds. (The tags channel already has binaries: v1.1.12's release published them.)

### Taking the next step
What an agent does when asked for "the next step", to "continue the roadmap", or to work on a row or phase by number. The answer to "where do I start" is always this file: nothing else needs explaining.

1. **Find the step.** The first [Full order](#full-order) row not `done` (an `on hold` row is skipped). Its work is the backend stage's bullets in [backend/roadmap.md](backend/roadmap.md) (a stage row) or the phase section below (a phase row). A row named by the user wins; so does a parallel-lane item they name.
2. **Check nobody holds it.** `git log -5` and `git status`: uncommitted changes in that row's files mean another agent is on it. Then take the next unblocked item (the parallel lane, or a later row with nothing waiting), or ask.
3. **Pick the batch** ([Rules](#rules)): the row's next items in order (a backend stage's next not-`Done` bullets, or a phase's first steps not marked `Done:`, then its listed issues), as many as share an area within the batch's bounds; a move or anything large goes alone. A "needs a plan" entry is taken through [Items that need a plan](#items-that-need-a-plan) instead of being built straight away. Read the item's issues.md entry, the docs for its area (`docs/dev/README.md` › Where to look), the matching recipe if there is one, and [issues.md](issues.md) for anything else known in those files.
4. **Do it**, item by item: each a commit after `scripts/dev/verify.sh` prints `verify ok`, and `scripts/dev/verify.sh --all` once before the branch is first pushed.
5. **Update the roadmaps in each item's commit:**
   - remove the fixed issues.md entry and its link here;
   - mark a finished phase step `Done:` at its start (as backend/roadmap.md marks its bullets);
   - when a row's last item is done (a deferred item doesn't count; a plan waiting for its decision does), set its Status to `done`, the next row's to `in progress` and the one after to `next` (passing over `on hold` rows); a stage row also updates its status in backend/roadmap.md;
   - anything learned that changes the order is an edit to [Full order](#full-order) with its reason in the "Why here" cell.
6. **Report** what was done, what the next item is (the user's next "next step"), and anything found and filed in issues.md along the way.

### Items that need a plan
An issues.md entry sized "needs a plan" is a design question before it's work. One that names a backend stage (`(stage 7)`, "Fixed by backend stage 7") is designed in that stage instead; every other one goes through this cycle, which never blocks the rest of its row.

1. **Plan.** A fresh agent investigates the entry and writes `docs/dev/plans/<slug>.md` in the format of [plans/README.md](plans/README.md): the problem with evidence, two or three options with their trade-offs, a recommendation, and the small items it splits into. Docs only, one PR, labelled `roadmap` and `needs-decision`; the entry's link here gets `(plan: #<PR>)` in the same PR.
2. **Carry on.** The row's other items go ahead meanwhile. The row can't turn `done` while a plan waits.
3. **The maintainer decides** on the PR: approves it (as written, or after editing it), comments the option chosen, or comments `defer`.
4. **Approved:** the PR is merged with its plan marked decided, and in the same PR the entry is replaced by the plan's small items, each an ordinary issues.md entry linked in the same phase where the old one was. From there they're built like any other item, and the plan file is deleted with the last of them.
5. **Deferred:** the PR is closed, and the entry's link moves to [Deferred](#deferred), which blocks no row. The maintainer moves deferred entries to GitHub over time.

### Running it unattended
The cycle the `roadmap-autopilot` skill runs, one batch (one PR) per iteration, driven by `/loop /roadmap-autopilot` in a session of its own (auto mode, so git and gh don't stop it for permission). It works in a scratch `git worktree` of its own (detached at `origin/main`, `scripts/generate.sh` run once), never in the live checkout, where the maintainer develops meanwhile (maintainer, 2026-10-29: "move all development to a scratch worktree and keep my live repo unaffected"). So the live shell never runs a batch before it merges. With `--dry-run` it only reports the batch it would take.

**The leader orchestrates; fresh agents read code.** The session running the loop is the leader. It holds enough to judge and steer: the Full order, the picked item's phase section and issues.md entry, the brief it writes, the agents' reports, and the gates' short outputs. It never reads source files or diffs itself (`git diff --stat` and the PR body are its view of a change); anything that needs code read goes to an agent. So each batch adds about a screenful to the leader's context, and every agent that reads code starts clean. Everything that must outlive the session is in the repo and on GitHub (statuses, issues.md, PR labels), so a new leader picks up where the last left off.

**Bounds.** A leader does at most three batches, then stops and asks for a fresh session even mid-row, and every row starts in a fresh session (the pause after a row ends the loop). Agents answer in the report shape asked for: a report that runs long is read for its fields, not reread. A failing gate's output is read as `tail` / `grep`, never whole.

1. **Preflight** (leader). In the worktree, `git status` clean (anything uncommitted means someone else is working there: stop; the live checkout's state is the maintainer's), then `git fetch` and `git switch --detach origin/main`. The maintainer also answers in PR comments, after a merge too: read the comments on the recent `roadmap` PRs (`gh pr view <n> --json comments`) and write any answer into its issues.md entry, quoted. An open PR labelled `roadmap` (`gh pr list --label roadmap`) is resumed at the step it reached instead of starting a new batch, unless it's a plan waiting for its decision, which never holds up the row ([Items that need a plan](#items-that-need-a-plan) step 2). One labelled `needs-decision` waits for the maintainer: if it's a plan with a decision on it (an approval, a chosen option, or `defer`), finish [Items that need a plan](#items-that-need-a-plan) step 4 or 5 for it first; any other one blocks its row until the maintainer answers.
2. **Pick** (leader) the batch with [Taking the next step](#taking-the-next-step) steps 1–3, reading only the Full order, that phase's section (or the stage's bullets in [backend/roadmap.md](backend/roadmap.md)) and the items' issues.md entries; a batch is never wider than one row. A "needs a plan" item gets a plan PR ([Items that need a plan](#items-that-need-a-plan) step 1, by a fresh agent with a brief like step 3's) and the leader moves on to the row's next item; when only plans waiting for decisions are left in the row, stop and report them. An item that needs a decision or a forbidden action ends the batch before it (the items before it still go); when it's the first, stop and report instead of starting. That's an item that needs a maintainer decision (a changed default, whether a migration is worth it, a behaviour trade-off), or waits on a row that isn't `done`. An item that can only be built or confirmed in the live environment (a live action `AGENTS.md` › Never forbids, or a fix only the maintainer's session shows) never holds anything up (maintainer, 2026-10-29: "mark accordingly in the roadmap and don't let it hold everything up - I can get to that later"): it's built as far as tests and nested runs take it, or skipped, and listed under [Live checks](#live-checks); the batch and the row go on.
3. **Brief** (leader), ten to fifteen lines plus two or three per item: the row and the items in order; each issues.md entry's title and its **Where**/**What**; what done looks like (the behaviour, and the entry removed with its link here); the docs to start from (`docs/dev/README.md` › Where to look, the recipe if one fits); the branch name `roadmap/<row>-<slug>`; and the stop conditions above, so the agent stops rather than guesses. A maintainer decision the item rests on is quoted word for word from roadmap.md or issues.md, with no step of the leader's own on how to build it (2026-10-26: a brief that added "so set the schema minimum to 5000" to a quoted decision broke saved configs), and a decision that seems to clash with its entry's title is a stop, not a reading. Every brief says: never `sudo`, `pkexec`, `su` or anything prompting for a password; a test needing root runs in a user namespace (`unshare -rm`), and what can't is skipped and reported (maintainer, 2026-10-30: "tell claude to stop asking for admin rights"). The brief also quotes [Rules](#rules)' Delete before adding and the rare-path cap (about 150 lines), so the agent stops there rather than building on.
4. **Implement** (a fresh `general-purpose` agent, given the brief): branch in the worktree from `origin/main`, never pushing it; then per item: implement, `scripts/dev/verify.sh` until `verify ok`, and commit it with [Taking the next step](#taking-the-next-step) step 5 (statuses, `Done:` marks, issues.md removals) and the attribution trailer. An item it has to stop on is left out (reset to the last item's commit) and reported; the committed ones go on. The live session runs the maintainer's checkout, so a change rests on its tests, nested runs and the review; what only the live session can show is reported under **Not verifiable live**. It reports in at most 250 words: **Commits** (sha and item, one line each), **Changed** (one line per file group), **Verified** (the `verify ok` line, the tests run), **Not verifiable live**, **Filed** (issues.md titles added), **Stopped** (why, if it did).
5. **Gate** (leader): the branch is at the last commit's sha, `git status` is clean, `git diff --stat origin/main...HEAD` touches the batch's area plus `docs/dev/roadmap.md` / `docs/dev/issues.md`, the closed entries' headings are gone from issues.md, and the batch is within the size gate: `git diff --shortstat origin/main...HEAD -- . ':!**/*_test.go' ':!tests/' ':!docs/'` at about 800 changed lines or fewer, unless its commits are pure moves. An oversized batch isn't sent back to be cut: it stops, and the leader reports it with a proposed split. A failed gate goes back to the same agent once (by `SendMessage`, with the failing lines); a second failure stops.
6. **Review** (a second fresh `general-purpose` agent, so the review isn't anchored on the implementer's reasoning), on the local branch before anything is pushed: runs the `review-branch` skill with the batch's intent and `--fix`, commits its fixes after `verify ok` (one commit per round, never pushing), and reports in at most 200 words: findings fixed (by severity), **Questions**, unfixed **Blockers**, the new sha. Each round that fixed a Blocker or Major gets another, by a fresh agent, up to five rounds (maintainer, 2026-10-30: "up the Maxx to 5", "as long as there is a major fix it needs another review"); a round that fixed only minors ends it. Row 19's audit batches get one review round: a round there that fixed a Blocker or Major opens the PR labelled `needs-decision` rather than starting another (maintainer, 2026-10-30: "let 5 finish but cap at one round. Implement accordingly to keep it cheaper as described"). A question with no product stake (how far a technical fix reaches) the leader decides, comments its reason on the PR and carries on (maintainer, 2026-10-29: "I don't care, as long as it is smartly implemented for the stack"). A product question (a changed default, a trade-off users notice, a migration, a takeover), a Blocker it couldn't fix, or a fifth round that still fixed a Blocker or Major (so no such fix merges unreviewed): push and open the PR as step 7 does, labelled `needs-decision` too, comment the findings on it, and stop.
7. **PR** (leader): `scripts/dev/verify.sh --all > <scratch>/verify.log; tail -3` ends in `all checks passed` (every CI check, so CI only confirms; a plain `verify.sh` checks only uncommitted changes, so on the committed branch it prints `nothing changed since HEAD`), then `git push -u origin HEAD` once and `gh pr create --label roadmap`; the body lists the row, each item with its commit and the issues.md entries it closed, and the reports' Verified and Not verifiable live.
8. **CI** (leader): `gh pr checks <n> --watch`. A failure goes to a fresh agent with the failing job's log tail (`gh run view --log-failed | tail -60`) to fix, run `verify.sh --all` and push once, at most twice; then stop with the PR open.
9. **Merge** (leader): first `git switch --detach` in the worktree (`--delete-branch` deletes the local branch, and with it a worktree holding it), then `gh pr merge <n> --squash --delete-branch` as a command of its own (a compound command doesn't match its allow rule), then `git fetch` and `git switch --detach origin/main` there (the live checkout is left alone). The squash message keeps each item's commit message as a bullet. A merged item whose report has a **Not verifiable live** that matters gets a line under [Live checks](#live-checks) in the next batch.
10. **After** (leader): rebuild and republish the maintainer's roadmap page, which lives outside the repo; the leader's memory names its builder and URL. Its statuses come from this file and backend/roadmap.md, so it's a build and a publish, never hand edits. Do this after every merge and at every stop. Stop the loop and report if this merge set a Full order row to `done` (the pause between rows, so the maintainer looks before the next one starts) or this was the session's third batch; otherwise schedule the next iteration. A report says what merged (PR links), where it stopped and why, and what the next batch is.

Never, besides `AGENTS.md` › Never: open a PR of roadmap.md or issues.md edits alone (a plan PR aside: an answer or a moved entry goes in the next batch's first commit), merge a PR without the `roadmap` label, put two rows or more than four items in one PR, push before the review, skip the review or CI, or retry a stop condition. A wallpaper-only screenshot means the session locked while idle: stop and ask the user to unlock.

### Live checks
What waits for the maintainer's own session (see [Running it unattended](#running-it-unattended) › Pick): a merged fix to confirm live, or an item only the live environment can build. None of it holds up a row; a confirmed check is deleted, a failed one becomes an issues.md entry.

- On sway and on Hyprland, show a few notifications, detached and attached, and check each toast blurs behind (the first after launch too): they're blur-backed shapes now, no longer popups of a 1x1 layer window (notifications revamp).
- Confirm the missing app icon fallback in the launcher and dock with an icon theme lacking `applications-system-symbolic` (#196).
- Lock once and check `scripts/log.sh` shows no `[ModuleGrid] … overlaps another` (#198).
- Once axiom runs a binary built with #200 (its qs command line has `--log-rules`), click into a desktop Notes module and back to a window, and check `scripts/log.sh` shows no `Trying to disable` from `qt.qpa.wayland.textinput`, under niri, sway and Hyprland. Before the fix niri logged 205 of them (`Trying to disable … but 0x0 is focused`, 2026-10-29), so the path reproduces there (#200).
- Once the shell runs #201, with `Polkit.enabled` on, restart axiom and reload a few times, and check `scripts/log.sh --all` shows no `[PolkitManager] Could not register as the polkit agent` and Settings → Authentication prompts says running.
- Once the shell runs row 14's re-exec fix, with axiom in dev mode, save a Go file while a note is being saved or the theme applied, and check `scripts/log.sh` shows no `the connection to axiom closed` from `[FileManager]`, `ThemeManager` or `MediaManager`, and `axiom daemon logs` no `checkupdates failed (-1)`.
- Once axiom runs a build with Phase 10 (row 17), set up 5–10 popular Waybar custom scripts (`~/waybar-test-scripts`: media, updates, weather, crypto, VPN, …) from the Custom widgets page alone, through the Import from Waybar box or the presets, and check each runs unchanged on a bar and as a module, under niri, sway and Hyprland (Phase 10's "done when").
- On Hyprland 0.57 with `Input` pointer settings on and acceleration left at `default`, check Hyprland reports no config error for `input.accel_profile` (#238).
- Once axiom runs a binary built with row 15 (stage 8), pick a file from Settings (a wallpaper or a path setting) under each compositor and check the portal's picker opens and its choice lands, then with the portal stopped check zenity or kdialog opens instead; and run `axiom bug-info` under Hyprland, niri and sway and check its Compositor and monitor lines.
- Once the shell runs the lock-survives-reload fix, let the idle lock come up, save a loaded QML file, then unlock with the password: the lock screen stays up throughout, `scripts/log.sh --all` shows no `Session lock object was destroyed without unlocking`, and the next save after unlocking reloads. Nested niri, sway and Hyprland showed it with a test unlock hook; the real idle lock and PAM only the live session can.
- Once axiom runs a binary built with row 16's greeter progress fix, update the login screen for real and check the card reads "Installing now..." after the password, then that it's up to date, and that the "Login screen update" notification is gone.
- Once the shell runs #230, check app and window icons in the dock, launcher, workspace widgets, workspace overview and switcher (AppIconManager; a window class's icon is cached until desktop entries change).
- Once axiom runs a binary with the VPN controls, connect a real OpenVPN with `networkmanager-openvpn` installed that asks for a password: the field shows in its row, a wrong password reads "Wrong user name or password", and the right one connects. Also check `nm-applet` running beside it still gets its turn after Cancel.

### Phase 0: decisions and quick wins
Decided (2026-10-26):
- Done: **Generated docs are no longer committed.** `docs/dev/generated/` and `docs/dev/config/` go in `.gitignore` (`git rm --cached`), `scripts/generate.sh` builds them like the schema JSON, CI generates them instead of failing when stale, the pre-commit hook stops adding them, and `AGENTS.md` › Checks and `.gitignore`'s comment say so. About 290 files and 12k lines leave the tree and every PR's diff.
- **The shell's `takeover: true` is fixed by backend stage 7**, with no stopgap before it: saves become path ops, only a takeover card's op carries `takeover`, live edits go through `ConfigManager.setPreview`, and config writes are applied in the order sent.
- **Idle is the daemon's** (done in stage 2, on its own D-Bus client); hypridle is no longer a dependency.
- Done: **Topics fed by a setting have no real floor** (decided again 2026-10-26: "1 ms (no real floor)", replacing the 250 ms floor, itself replacing the floor read from the schema): every `topics.Source` whose interval comes from a setting has `topics.MinInterval` (1 ms) as its floor, so each setting's schema `minimum` is the real limit (Tailscale's stays at 1 s), and a test keeps every interval setting's `minimum` at or above it. No migration.
- Done: **`TailscaleManager` moves to `services/apps/`** (moved with the Tailscale revamp; the rest of Phase 3 step 1 stays).

Quick wins: run `git gc` locally (most of a clone's `.git` is loose objects; packed history is about 18 MB).

### Phase 1: integrity
The config, the takeover and the session must never be damaged by a rarely taken path. The shell's save path itself is stage 7's (rewritten there), so its entries are linked here and fixed there. So is everything that starts from a config.json that doesn't load (decided 2026-10-26): rare, and handled with the other config problems when stage 7 rewrites that path, not patched before it.

Done: every entry is fixed, the last with backend stage 7; the hand-fix gap with no takeovers kept is [Deferred](#deferred).

- [A shared file older than v71 resets niri's hot corner](issues.md#a-shared-file-older-than-v71-resets-niris-hot-corner)

### Phase 2: finish stage 2
Done: [backend stage 2](backend/roadmap.md) (Wayland), with its own entries: the hypridle autostart default (dropped, and from saved configs by the v78 step) and the D-Bus match rules' escaping.

### Phase 3: QML structure
Each file has one job and sits where its folder's rule says. Moves and splits keep each service's public API, so widgets don't change; a service a backend stage empties is folded in that stage instead.

Steps, roughly in this order (moves first, each its own PR):
1. Done: Reword `services/AGENTS.md` › Folders (`system/`: the machine and the desktop basics every user has; `apps/`: optional features and integrations with outside tools or services); `DailySchedule` to `core/`; `ShellManager` to `ui/`; document the non-singleton parts.
2. Done: Move the reusable pieces holding feature logic: `BaseWidget` / `IconTextWidget` to `bar/widgets/base/`, `CodeLine` to `content/parts/`, `PipewireVolumeBar` to `surfaces/osd/`; `StyledToolTip` stays, named in AGENTS.md › Layout.
3. Done: Split `ShellManager` by concern (`SurfaceManager`, `SessionManager`) and `EdgeMenuManager` into its runtime and its editor (`EdgeMenuEditor`); extract `LauncherCommands`' `/config` browser (`LauncherConfigBrowser`); give the bars' and edge menus' reserved zones one owner (`ScreenEdgeManager`). The `KeybindManager` split, into its reader, a `KeybindEditor` and page state, stays with backend stage 7.
4. Done: A shared ticker part for Stopwatch and Pomodoro (`DeadlineTicker`); `valueAt` into a methods helper with a test row (`Utils.valueAt`, `SchemaLayout.defaultAt`).

Resolves:

### Phase 4: backend structure and contract
The binary's rules are enforced by its tests, and the shell–daemon contract is checked by shape, not just by name. The contract check lands before stage 7, so the switch to path ops is checked as it happens.

Done: extend `archtest` (dependency direction, no `init()` or package state, every package classified); one floor (`topics.MinInterval`, 1 ms since 2026-10-26: each setting's schema minimum is the limit) for every topic fed by an interval setting; the contract check (the daemon's registry dumps its method, push and topic shapes, `rpc.md` shows them, and `gen_docs.py` checks literal params, helper calls under `// rpc:` and first-level result and push reads in inline callbacks against them; installs skip it with `generate.sh --no-docs`); fold `saved.everything` into `share`; settle `tree` against `schema/yamlsrc` (`tree` is its disk side, both package docs say so); clearer package names (`system` is `sysmon`, `lock` is `lockscreen`, apart from `fsx.Lock`); strict param decoding (`rpc.DecodeStrict`, topic requests too); the call rule in protocol.md, with `gen_docs.py` failing on a call it can't read unless marked `// rpc: unchecked (<reason>)`.

Resolves:
- [A fast chat reply can drop the shell's connection](issues.md#a-fast-chat-reply-can-drop-the-shells-connection)
- [A dev build during a branch switch re-execs onto the defaults](issues.md#a-dev-build-during-a-branch-switch-re-execs-onto-the-defaults)

### Phase 5: the allowlist
[Backend stages 3–7](backend/roadmap.md) are this phase (the `CommandManager` funnel is stage 3b, ahead of stage 6); nothing here restates them.
- Done: **The `execDetached` quick wins.** The files on the allowlist only for `Quickshell.execDetached` (`GreetdManager`, `LockManager`, `LauncherManager`, `CompositorConfigManager`) switched to `CommandManager.runDetached`, which now also takes an argv, shrinking the list early.

Stage 7 also retires the code that exists twice: `SchemaValidation` against Go's pipeline, and the QML compositor renderers (`HyprLua`, `NiriConf`, `SwayConf`, `CompositorLayer`) against `compositor/render`. Both done: `SchemaValidation` keeps only what previews use, and the four renderers are gone.

Resolved by a stage:
- [Setting an awww wallpaper never starts awww's daemon](issues.md#setting-an-awww-wallpaper-never-starts-awwws-daemon) (closed by awww's removal; maintainer: "awww is scheduled for remove in favor of axioms own animations")

### Phase 6: compositor parity
Every feature works the same under each compositor, or says why not. It follows backend stage 7, when only Go writes compositor configs; bugs outside the writer (crashes, freezes, reload glitches) can go any time. sway is the largest cluster: take it as one pass in a nested sway (`scripts/dev/nested.sh sway`).

Done: every entry is fixed: sway and SwayFX, then Hyprland's and every compositor's (the last with row 13: workspace blocks numbered over the saved monitor profiles, and the scrolling layout's borrowed workspaces, which Hyprland hands back on replug). niri's entries are [deferred](#deferred) (maintainer, 2026-10-29).

### Phase 7: fit, geometry and performance
Nothing runs off a screen or clips at 1080p, and pages stay fast as their data grows. Take the 1080p entries as one pass in a nested compositor with a 1080p output.

- [Text clips on 1080p screens](issues.md#text-clips-on-1080p-screens)
- [An edge menu can be bigger than its screen](issues.md#an-edge-menu-can-be-bigger-than-its-screen)
- [A popout taller than the screen runs off it](issues.md#a-popout-taller-than-the-screen-runs-off-it)
- [A dropdown in an edge menu card with nothing scrolling gets two rows](issues.md#a-dropdown-in-an-edge-menu-card-with-nothing-scrolling-gets-two-rows)
- [A side edge's submenus always open away from the edge](issues.md#a-side-edges-submenus-always-open-away-from-the-edge)
- [A pill bar's end reach trails a sliding popout's wall](issues.md#a-pill-bars-end-reach-trails-a-sliding-popouts-wall)
- [WorkspaceStrip's Grid briefly has more items than cells](issues.md#workspacestrips-grid-briefly-has-more-items-than-cells)
- [A model of size -1 when the overlay grid resizes](issues.md#a-model-of-size--1-when-the-overlay-grid-resizes)
- [Compact cards still build their full layout](issues.md#compact-cards-still-build-their-full-layout)
- [Unbounded lists still built in full](issues.md#unbounded-lists-still-built-in-full) (the chat lists wait for stage 5)
- [The keybinds page on a small monitor with large binds](issues.md#the-keybinds-page-on-a-small-monitor-with-large-binds) (with the 1080p pass)
- [The system stats widget changes width with its digits](issues.md#the-system-stats-widget-changes-width-with-its-digits)
- [Modules inside borders aren't sized evenly](issues.md#modules-inside-borders-arent-sized-evenly)
- [High module padding clips edge menu modules](issues.md#high-module-padding-clips-edge-menu-modules)
- [An edge popout doesn't size itself consistently](issues.md#an-edge-popout-doesnt-size-itself-consistently)

### Phase 8: a clean log
A reload, and a session's normal use, log nothing but the two reload lines.

- [Bar widget hosts settle after they're gone](issues.md#bar-widget-hosts-settle-after-theyre-gone)
- [The shell's hello can be refused across a dev re-exec](issues.md#the-shells-hello-can-be-refused-across-a-dev-re-exec)
- [A custom Ring element logs an undefined `inside` on load](issues.md#a-custom-ring-element-logs-an-undefined-inside-on-load)
- [The Layouts canvas logs null reads as it's torn down](issues.md#the-layouts-canvas-logs-null-reads-as-its-torn-down)
- [Keybind sections log null reads as they're torn down](issues.md#keybind-sections-log-null-reads-as-theyre-torn-down)
- [A custom layout's element rect reads an undefined place](issues.md#a-custom-layouts-element-rect-reads-an-undefined-place)
- [Read-only daemon calls fail across a dev re-exec](issues.md#read-only-daemon-calls-fail-across-a-dev-re-exec)

### Phase 9: docs, tooling and process
Last, so the docs describe the final shape (after [Phase 11](#phase-11-audits-clear-out-and-hardening); the post for testers follows it).

Steps: trim the root `AGENTS.md` to its rules (mechanics move to the `docs/dev` pages it points at); fold `docs/dev/core/config-v2.md` into `schema-annotations.md` and `config-manager.md` once stage 7 finishes v2; the maintainer moves the [Deferred](#deferred) entries to GitHub; a PR-size note in `CONTRIBUTING.md` (a batch per PR, an item per commit, moves apart from logic); the maintainer prepares the photos and videos for the post (it blocks the post, not the row).

Resolves:
- [The schema root's description contradicts the annotations doc](issues.md#the-schema-roots-description-contradicts-the-annotations-doc)
- [A protocol bump in dev mode leaves the installed CLI on the old protocol](issues.md#a-protocol-bump-in-dev-mode-leaves-the-installed-cli-on-the-old-protocol)
- [The calendar doc's Files header leaves out its page](issues.md#the-calendar-docs-files-header-leaves-out-its-page)
- [AGENTS.md's funnel rule doesn't name FileManager.write and watch](issues.md#agentsmds-funnel-rule-doesnt-name-filemanagerwrite-and-watch)
- [install.sh still installs the rest of a feature whose COPR was declined](issues.md#installsh-still-installs-the-rest-of-a-feature-whose-copr-was-declined)

### Phase 10: custom JSON widgets
The last feature before posting for testers (decided 2026-10-27), the editor page included. Point a definition at a script; its output (Waybar's `return-type: json` as the preset) is drawn by a small library of styles, as a bar widget, its popout, a desktop, overlay or edge menu module and a lockscreen module, all from one definition, so the script runs once for all of them. Waits for [backend stage 3b](backend/roadmap.md) (streamed commands, JSON parsed in Go).

The plan is [plans/custom-json-widgets.md](plans/custom-json-widgets.md) (decided 2026-10-29: the bar widget draws one style; the module is a fixed set of elements on a fine grid, 16 sub-cells per card, laid out proportionally; CommandOutput folds in). Its items are the steps, one PR each, built on the branch `implementModuleEditor`:

Steps:
1. Done: **The plan.**
2. Done: **Data:** `CommandManager` keeps `exitCode` / `error` / `at`; the pure helper `CustomWidgetData` and its test.
3. Done: **Definitions:** the `CustomWidgets` section, the `customWidgets` `x-options` source, `CustomWidgetsManager`, and its IPC target (`axiom ipc customWidgets refresh`).
4. Done: **The module:** the element pieces, the proportional renderer, the `CustomWidget` module type (also the popout; lockscreen opt-in), per-definition module library entries. Never the greeter; no actions on the lockscreen.
5. Done: **The bar widget:** the `Custom` widget type and its styles, per-definition bar library entries.
6. Done: **Editor, part 1:** the tool page, its editor manager, the definitions list, the Source card and the Bar tab.
7. Done: **Editor, part 2:** the Module tab (the fine-grid canvas on `GridEditor`).
8. Done: **Waybar import and presets.**
9. Done: **Fold CommandOutput**, the feature's doc, and its system in `.claude/skills/review-system/systems.md`, so [Phase 11](#phase-11-audits-clear-out-and-hardening) audits it with the rest.

Done when 5–10 popular Waybar custom scripts run unchanged through the Waybar preset, and each can be set up from the editor page alone: a [live check](#live-checks), so it doesn't hold the row.

### Phase 11: audits, clear-out and hardening
The guardrails tightened first, then every system audited in full, every open entry fixed or deliberately deferred, then a frozen stretch of daily use, before posting on the sway and niri wikis for testers (decided 2026-10-27). Nothing new is built in this phase.

Steps:
0. **Audit and tighten the guardrails** (row 18), the checks being a system like any other. First `.claude/skills/review-system/systems.md` gets a `guardrails` system (the `scripts/check_*` scripts, `scripts/dev/verify.sh`, `scripts/generate.sh`, the CI workflows in `.github/workflows/`, `.claude/hooks/guard.py`, the test runners and helpers, `AGENTS.md` and the skills), audited with `--full --record`. Then, as ordinary batches:
   - **An inventory:** each check, what it catches, how often it failed in CI's history and what it costs. One that never caught anything is justified or deleted.
   - **What got past them:** the bug classes in issues.md and the fix history a mechanical check could have caught (the oversized rare-path fixes, live values as Repeater models, …); each one that recurred becomes a check.
   - **Ratchets:** every baseline only shrinks (the qmllint baseline, the allowlist, files over the size limits, deferred entries), and CI fails on growth.
   - **Test quality over count:** the flaky tests fixed (they're linked below), tests that can't fail found, and a sampled mutation run on the critical Go packages (the store's takeovers, the lock screen, the greeter installer, migrations): a mutant that survives is a missing test.
   - **Security paths:** every rule in `AGENTS.md` › Never has its case in `tests/scripts/test_guard.py`, and PAM, the greeter installer and the takeovers each have a test that tries to break them.
   - **Speed:** `scripts/dev/verify.sh` and CI stay fast enough that nobody routes around them.
   - **The agent rules:** `AGENTS.md`, the skills and [Running it unattended](#running-it-unattended) checked against what went wrong in the rows before; rules nothing broke are trimmed (with Phase 9's 12 KB target).
   Asked (maintainer, 2026-10-29): "for the next branch, there should be an audit of the CI tests, and their guardrails (as well as scripts used in repo (i.e. gen docs, check variable usage, etc)), and those should be hardened", and "Next loop, do a quick inventory and pre-split what makes sense between all the entire repo guardrail hardening for PRs before starting the first review". Done: the audit (#220) and the inventory (the table in `.claude/reviews/guardrails.md` › Inventory). The rest of step 0 is these **Batches**, taken in order (one PR each, under [Rules](#rules)):
   1. Done: **CI and check_all.sh agree** (CI workflow, check_all.sh, check_go.sh, check_i18n.py): The check order is kept in three places, check_go.sh passes stale generated code except under --ci, CI can't fail on stale translation files, CI checks dependencies only when a PR touches Go.
   2. Done: **verify.sh** (verify.sh, the autopilot's gate): verify.sh skips the checks a deletion or a check's own change needs, Running it unattended's gate can't get `verify ok` on a committed branch.
   3. Done: **The guard** (`.claude/hooks/guard.py`, its tests, the deny list): The guard misses compound commands, wrapper options and writes onto config.json, The permission deny list names a config path that's gone; then each AGENTS.md › Never rule gets a compound-form case beside its plain one.
   4. Done: **Flaky Go tests** (backend tests): Go tests wait with their own short bounds that a loaded CI runner overruns, A binds test fails with pthread_create failed in CI, A compositor manager test misses its takeover prompt under load, A self-update test once took the build path for a release.
   5. Done: **Go tests as a user, and the security paths** (CI's go job, backend tests): CI's Go tests run as root, so the unwritable-file tests never run there, TestWatch sees a push for the package's own write under CI load; then break-it tests for PAM (only its success unlocks, never IPC: `test_scripts.py` › `OnlyPamUnlocks`), the greeter installer (a hostile archive lands nothing outside the copy) and the takeovers (no load or import, and no op around the key, changes one).
   6. Done: **gen_docs and the ratchets** (gen_docs.py, check_qmllint.py, check_structure.py): gen_docs.py doesn't see readers of ConfigManager.live, so 372 settings show as unread (its unused-setting and unused-member checks fail now, over `scripts/config-usage-baseline.json`), The qmllint baseline doesn't shrink when warnings are fixed, and a size ratchet: singletons over 800 lines (outside the pure helpers and compositor backends) fail; none is over today, so it has no baseline.
   7. Done: **Checks that can fail** (`tests/scripts/`, `tests/`): Most check scripts have no tests of their own (one fixture per rule: `test_scripts.py` › `CheckStructure`, `CheckI18n`, `CheckQmllint`, `CheckPackages`, `CheckDocs`), Small tooling leftovers (`tst_IconResolver`, with the helper made pure and its Quickshell lookups in `AppIconManager`; the PKGBUILDs stay two files, as AUR packages stand alone; i18n.md reread).
   8. Done: **A sampled mutation run** (backend): the store's takeovers, the lock screen, the greeter installer and migrations; each surviving mutant is filed as a missing test, then fixed in batches appended here. 873 mutants; the takeover, lock and installer survivors got tests (survivors 128 → 83), the rest equivalent or filed as batches 12 and 13 (`.claude/reviews/guardrails.md` › Mutation run).
   9. Done: **What got past them** (check_structure.py): the bug classes in issues.md and the fix history a mechanical check could have caught, as checks: Repeater models and `acquire()` requests from live values, and the AGENTS.md rules no check holds yet (animation literals, `Qt.formatDateTime`, `Quickshell.screens`, polling Timers in UI); one rule a commit. Four checks landed: a Repeater model or `acquire()` request reading a polled service's member (the calendar page's and idle card's models key by count now), a `duration:` in ms not marked `// behaviour timing:`, `Qt.formatDateTime` and `Quickshell.screens` outside General (the uses that must stay, screenshot file names and windows that must exist with no monitor, marked `// allowed: <reason>` on their line). Left: polling Timers in UI (none in `components/` or `shell/` today; a `Process` there is already refused by the allowlist).
   10. Done: **Speed** (CI workflow, verify.sh): `scripts/generate.sh` takes 28–43 s in each of CI's four jobs (go job 3.4 min end to end); share or cache it, and measure verify.sh on a typical change. Neither shared nor cached (the repository allows local actions only, so no `actions/cache` or artifacts): almost all of it was compiling the binary, which only the reference docs need, so `syncassets` writes the tree's schema too and the `qt` and `scripts` jobs pass `--no-docs` (their generate 41 s and 27 s in CI, 5 s and 2 s cold locally against ~12 s); the `go` job (compile and tests) is unchanged. verify.sh ran generate.sh twice on a Go or schema change and waited 3 s for a reload that had already happened: a one-line QML edit 15 → 11 s, a schema edit 42 → 27 s, a Go edit 32 → 27 s (`.claude/reviews/guardrails.md` › Inventory). Once the repository allowed `actions/cache`, a follow-up PR cached Go's build and module caches across runs in the `checks` and `go` jobs (keyed on the Go version and `backend/go.sum`, so a run saves only when that changes; PR runs restore what the go job's weekly run on main saved; tests still `-count=1`).
   11. Done: **The agent rules** (AGENTS.md, skills, [Running it unattended](#running-it-unattended)): checked against what went wrong in rows 1–18; rules nothing broke are trimmed (with Phase 9's 12 KB target). Last, so it describes the checks as they end up. AGENTS.md 25.1 → 11.9 KB: its mechanics moved to the docs it points at (the Where to look table, layout and naming to `docs/dev/README.md`, what each check catches to `testing.md` › The checks), rules a check holds kept as a line naming it, the Never list whole; Running it unattended gained what broke in its runs (preflight in the worktree and the PR comments read, decisions quoted verbatim, no elevation, technical questions decided by the leader, detach before the merge, no roadmap-only PRs); the review lenses stop re-checking what `check_structure` holds.
   12. Done: **Migration mutants** (`migrate/steps`, `migrate/convert`; tests only): every listed survivor killed by a test (`TestConvertShapes`, `TestConvertNotesItsChanges`, `TestV81FoldsCommandOutput`), each checked by hand; the ties and two deletes a re-set key makes redundant are equivalent (`.claude/reviews/guardrails.md` › Mutation run).
   13. Done: **Failure-path mutants** (store, greeter installer; tests only): every listed survivor a test can reach killed, each checked by hand (a dead field deleted); the rest equivalent or root-only (`.claude/reviews/guardrails.md` › Mutation run).
1. **Audit every system** (row 19) with the `review-system` skill: `--full --record` (findings land in issues.md, linked from this phase under Found by the audits). From batch 6 on, one system per batch, with `--deep` only where the maintainer or a prior finding calls for it (maintainer, 2026-10-30: "let 5 finish but cap at one round. Implement accordingly to keep it cheaper as described"). Every system `scope.py --list` names, plus the custom widgets, plus every `feature:<name>` doc that no system covers; the modules' sizing and the popouts nobody has touched in a while get a close look (maintainer's notes, 2026-10-28: "check modules, their sizing, and minor improvements to popouts that havn't been touched in awhile"). Audits only file; nothing is fixed in this step. Each audit also runs a **deletion pass**, its findings filed like any other: what in the system can go or shrink (dead members, mechanisms nothing needs since a stage moved their work, duplicates of a shared piece, special cases the general path covers, options nobody would miss), each with its line count. Before the first audit, record the repository's size under [Size](#size) below. Done (batch 3): `scope.py --orphans` lists no file: each file it listed went into a system's Docs or Extra, or a new system (`daemon`, `dbus-wayland`, `config-pipeline`) where none fit (on 2026-10-30 it listed 195 files, about 30k lines, 108 of them Go). Then compositor, hyprland and niri were audited with `--full` again, before the remaining systems: the first batch's scopes missed the Go code of folders named in doc headers (`scope.py` dropped them; it expands them now: 8085 → 19885, 11118 → 21062 and 4448 → 4673 lines) (maintainer, 2026-10-30: "Expand + re-audit (c): Expand folders everywhere, and re-run full audits of compositor and hyprland (and niri if its scope grew) in the next audit batch, since batch 1 missed that Go code."). Done (batch 4): sway, `--full --deep` (its first review since stage 7 moved its config writing into Go), compositor-parity and blur, `--full --deep` (first reviews of both). Done (batch 5): popouts, `--full --deep` (its close look went to the panels with no substantive change since the history began on 2026-10-24: NowPlaying, SystemGraphs, Updates, WorkspaceStrips, WorkspaceGrid, WeatherForecast, Pomodoro and the tray parts); bar and bar-widgets, `--full --deep` (first reviews of both; the bar widgets' sizing got the close look).
2. **Clear out issues.md** (row 20): every open entry, highest severity first, as ordinary batches. Each is fixed, or the maintainer defers it (to [Deferred](#deferred), then GitHub, listed as a known issue in the post); rare paths get the smallest fix or stay logged. The deletion findings go first in each system's batches (deleting first shrinks everything the fixes then touch). A "needs a plan" entry goes through [Items that need a plan](#items-that-need-a-plan). Then an incremental `review-system` pass of every system (it rereads only what changed since its last review), and again, until a pass finds nothing above minor.
3. **Harden, frozen** (row 21; the maintainer's, so the autopilot stops before it): 1–2 weeks of daily use under sway and niri. Only fixes land: each new finding is fixed at once or becomes a known issue. Also: a first run from nothing (`install.sh` and the AUR packages for a fresh user, onboarding without a config.json, importing saved configs), and the Waybar scripts from Phase 10 again.

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

Found while porting the scripts (backend stage 4):
- [Calendar times in a Windows zone name with no VTIMEZONE read as local time](issues.md#calendar-times-in-a-windows-zone-name-with-no-vtimezone-read-as-local-time)

Found while retiring the `qs ipc` fallback (backend stage 6):
- [A word passed to an int IPC parameter is 0](issues.md#a-word-passed-to-an-int-ipc-parameter-is-0)

Found while closing the config path (backend stage 7):
- [After a refused save, a draft's edits show unsaved but not live](issues.md#after-a-refused-save-a-drafts-edits-show-unsaved-but-not-live)

Found while adding niri's own overview (row 16):
- [An open-only workspace overview bind calls a function that doesn't exist](issues.md#an-open-only-workspace-overview-bind-calls-a-function-that-doesnt-exist)

Found while fixing the lock screen surviving a reload:
- [Nested Hyprland acknowledges a lock too late for axiom lock](issues.md#nested-hyprland-acknowledges-a-lock-too-late-for-axiom-lock)

Found while investigating Hyprland starting on workspace 10:
- [A remap runs at startup, from the layout before the config loaded](issues.md#a-remap-runs-at-startup-from-the-layout-before-the-config-loaded)
- [A monitor a profile names by description gets the next block until its description arrives](issues.md#a-monitor-a-profile-names-by-description-gets-the-next-block-until-its-description-arrives)

Found by the audits:
- [Three reader members nothing reads](issues.md#three-reader-members-nothing-reads)
- [The guard reads the branch from the session's folder, not a `cd` before the push](issues.md#the-guard-reads-the-branch-from-the-sessions-folder-not-a-cd-before-the-push)
- [The daemon picks a compositor the shell may not run under](issues.md#the-daemon-picks-a-compositor-the-shell-may-not-run-under)
- [The Translucency card reads the window look's blur object as a switch](issues.md#the-translucency-card-reads-the-window-looks-blur-object-as-a-switch)
- [A failed cursor theme call keeps the theme's own name all session](issues.md#a-failed-cursor-theme-call-keeps-the-themes-own-name-all-session)
- [Backends keep stubs for calls the facade gates](issues.md#backends-keep-stubs-for-calls-the-facade-gates)
- [Small shrinks in the compositor layer](issues.md#small-shrinks-in-the-compositor-layer)
- [A trial monitor Apply that turns a monitor off drops its Keep/Revert](issues.md#a-trial-monitor-apply-that-turns-a-monitor-off-drops-its-keeprevert)
- [A shell reload during a trial monitor Apply loses the way back](issues.md#a-shell-reload-during-a-trial-monitor-apply-loses-the-way-back)
- [Restoring a saved keybind preset marks every bind new, and Revert deletes it](issues.md#restoring-a-saved-keybind-preset-marks-every-bind-new-and-revert-deletes-it)
- [The Keybinds page goes stale after a detached-mode Save](issues.md#the-keybinds-page-goes-stale-after-a-detached-mode-save)
- [The bind merge deletes an hl.bind inside a helper, losing binds it never read](issues.md#the-bind-merge-deletes-an-hlbind-inside-a-helper-losing-binds-it-never-read)
- [The bind merge removes an hl.unbind whether or not its bind went](issues.md#the-bind-merge-removes-an-hlunbind-whether-or-not-its-bind-went)
- [A failed monitor profile apply is never retried for the same outputs](issues.md#a-failed-monitor-profile-apply-is-never-retried-for-the-same-outputs)
- [One refused line stops the rest of a Hyprland eval](issues.md#one-refused-line-stops-the-rest-of-a-hyprland-eval)
- [A user/ file with a dot in its name never loads](issues.md#a-user-file-with-a-dot-in-its-name-never-loads)
- [A moved raw bind with a Lua keyword key compiles to nothing](issues.md#a-moved-raw-bind-with-a-lua-keyword-key-compiles-to-nothing)
- [A failed options read sets Hyprland's gaps to 0](issues.md#a-failed-options-read-sets-hyprlands-gaps-to-0)
- [A workspace slide throws when animations go off between its legs](issues.md#a-workspace-slide-throws-when-animations-go-off-between-its-legs)
- [Direct Hyprland dispatches can overtake queued Lua](issues.md#direct-hyprland-dispatches-can-overtake-queued-lua)
- [Recording two keys within 30 s can end the second recording early on Hyprland](issues.md#recording-two-keys-within-30-s-can-end-the-second-recording-early-on-hyprland)
- [Two keybind reference paths drop a key's binds](issues.md#two-keybind-reference-paths-drop-a-keys-binds)
- [The monitor prompt's padding is a bare 18 px, and check_sizes misses it](issues.md#the-monitor-prompts-padding-is-a-bare-18-px-and-check_sizes-misses-it)
- [HyprlandManager keeps members only it reads](issues.md#hyprlandmanager-keeps-members-only-it-reads)
- [A bind description's section is parsed three ways](issues.md#a-bind-descriptions-section-is-parsed-three-ways)
- [KeybindManager keeps tables the methods helpers already hold](issues.md#keybindmanager-keeps-tables-the-methods-helpers-already-hold)
- [The workspace strips repeat ActiveStrip's loader](issues.md#the-workspace-strips-repeat-activestrips-loader)
- [The managed file's catch-all monitor line is copied into M.monitors](issues.md#the-managed-files-catch-all-monitor-line-is-copied-into-mmonitors)
- [Hyprland's exit command is kept in two packages](issues.md#hyprlands-exit-command-is-kept-in-two-packages)
- [noteReload counts every compositor reload a second time](issues.md#notereload-counts-every-compositor-reload-a-second-time)
- [The Hyprland Go code keeps dead and doubled helpers](issues.md#the-hyprland-go-code-keeps-dead-and-doubled-helpers)
- [Bind helpers keep JS halves the daemon owns now](issues.md#bind-helpers-keep-js-halves-the-daemon-owns-now)
- [Stale lines in the Hyprland docs and comments](issues.md#stale-lines-in-the-hyprland-docs-and-comments)
- [The unused reader member check counts a member named after its key as used](issues.md#the-unused-reader-member-check-counts-a-member-named-after-its-key-as-used)
- [A user's blur off overrides axiom's blur on niri](issues.md#a-users-blur-off-overrides-axioms-blur-on-niri)
- [niri started on a broken config reads as loaded](issues.md#niri-started-on-a-broken-config-reads-as-loaded)
- [Nothing reads userBindsRead or lastLoadFailed](issues.md#nothing-reads-userbindsread-or-lastloadfailed)
- [The niri writer's runtimeOn and unread-binds guards are dead](issues.md#the-niri-writers-runtimeon-and-unread-binds-guards-are-dead)
- [Three listings of niri's user files](issues.md#three-listings-of-niris-user-files)
- [RunningNested has its own niri socket client](issues.md#runningnested-has-its-own-niri-socket-client)
- [NiriManager queues actions the daemon could order](issues.md#nirimanager-queues-actions-the-daemon-could-order)
- [A second KDL writer in the kdl package](issues.md#a-second-kdl-writer-in-the-kdl-package)
- [A file mode that stops loading keeps the saved monitor profile off](issues.md#a-file-mode-that-stops-loading-keeps-the-saved-monitor-profile-off)
- [Leaving included between sessions leaves the full module loaded](issues.md#leaving-included-between-sessions-leaves-the-full-module-loaded)
- [A failed takeover leaves no layer and no problem](issues.md#a-failed-takeover-leaves-no-layer-and-no-problem)
- [A failed takeover check reuses the last answer and can adopt without approval](issues.md#a-failed-takeover-check-reuses-the-last-answer-and-can-adopt-without-approval)
- [Claim keeps writing a symlinked or git-tracked config that release refuses to give back](issues.md#claim-keeps-writing-a-symlinked-or-git-tracked-config-that-release-refuses-to-give-back)
- [sway's hookup and takeover use ~/.config/sway/config whatever config sway runs](issues.md#sways-hookup-and-takeover-use-configswayconfig-whatever-config-sway-runs)
- [A relative -c is read from the daemon's folder](issues.md#a-relative--c-is-read-from-the-daemons-folder)
- [Gaps to the edges are wider on sway than the setting says](issues.md#gaps-to-the-edges-are-wider-on-sway-than-the-setting-says)
- [A $' or $& in a bind's argument is read as a replacement pattern](issues.md#a--or--in-a-binds-argument-is-read-as-a-replacement-pattern)
- [A niri merge of two binds on one line loses one](issues.md#a-niri-merge-of-two-binds-on-one-line-loses-one)
- [A sway bind using a variable from an include moves as a literal $name](issues.md#a-sway-bind-using-a-variable-from-an-include-moves-as-a-literal-name)
- [A niri spawn of one word with a space moves as a broken shell command](issues.md#a-niri-spawn-of-one-word-with-a-space-moves-as-a-broken-shell-command)
- [A sway line continuing a non-bind line is moved as a bind of its own](issues.md#a-sway-line-continuing-a-non-bind-line-is-moved-as-a-bind-of-its-own)
- [Small shrinks in the compositor manager](issues.md#small-shrinks-in-the-compositor-manager)
- [niri's bind plan is a copy of runtimeLayer.plan](issues.md#niris-bind-plan-is-a-copy-of-runtimelayerplan)
- [Go copies of bind helpers that only the parity replay calls](issues.md#go-copies-of-bind-helpers-that-only-the-parity-replay-calls)
- [sway and niri each fit the shadow to axiom's themselves](issues.md#sway-and-niri-each-fit-the-shadow-to-axioms-themselves)
- [The Hyprland and sway bind merges each skip half of compositor/actions](issues.md#the-hyprland-and-sway-bind-merges-each-skip-half-of-compositoractions)
- [Hyprland's remove deletes whatever hl.bind is on a site's line now](issues.md#hyprlands-remove-deletes-whatever-hlbind-is-on-a-sites-line-now)
- [A claim comments out axiom's start inside a long string, breaking the script](issues.md#a-claim-comments-out-axioms-start-inside-a-long-string-breaking-the-script)
- [An unknown IPC function word merges as a toggle](issues.md#an-unknown-ipc-function-word-merges-as-a-toggle)
- [The overview stays open with nothing shown after its monitor goes away](issues.md#the-overview-stays-open-with-nothing-shown-after-its-monitor-goes-away)
- [Wide active is hidden in the perMonitor layout but still applies there](issues.md#wide-active-is-hidden-in-the-permonitor-layout-but-still-applies-there)
- [A combo lookup says nothing holds a key the search or chips hide, and offers to bind it](issues.md#a-combo-lookup-says-nothing-holds-a-key-the-search-or-chips-hide-and-offers-to-bind-it)
- [The bind inspector's typed label and argument miss Save](issues.md#the-bind-inspectors-typed-label-and-argument-miss-save)
- [Picking a key in the key map under an edit search selects a bind the list doesn't show](issues.md#picking-a-key-in-the-key-map-under-an-edit-search-selects-a-bind-the-list-doesnt-show)
- [Renaming a saved preset after switching presets renames the wrong one](issues.md#renaming-a-saved-preset-after-switching-presets-renames-the-wrong-one)
- [The reference's sections and both chip rows are built while hidden](issues.md#the-references-sections-and-both-chip-rows-are-built-while-hidden)
- [In the standard layout, a switch past `count` slides through an unrelated workspace](issues.md#in-the-standard-layout-a-switch-past-count-slides-through-an-unrelated-workspace)
- [Where the compositor can't mirror, a profile's mirror can't be turned off or its monitor placed](issues.md#where-the-compositor-cant-mirror-a-profiles-mirror-cant-be-turned-off-or-its-monitor-placed)
- [The workspace strips' panel property is never read](issues.md#the-workspace-strips-panel-property-is-never-read)
- [Three copies of the wheel-notch accumulator](issues.md#three-copies-of-the-wheel-notch-accumulator)
- [The key map and the keyboard reference each carry the same modifier chips and legend](issues.md#the-key-map-and-the-keyboard-reference-each-carry-the-same-modifier-chips-and-legend)
- [A reference section's folded count re-derives BindRows.byModifiers' grouping](issues.md#a-reference-sections-folded-count-re-derives-bindrowsbymodifiers-grouping)
- [PresetSheet defers its re-choose a tick for a config that updates at once](issues.md#presetsheet-defers-its-re-choose-a-tick-for-a-config-that-updates-at-once)
- [The bind list's flag icons carry tooltip strings nothing shows](issues.md#the-bind-lists-flag-icons-carry-tooltip-strings-nothing-shows)
- [A reference section's title is worked out twice](issues.md#a-reference-sections-title-is-worked-out-twice)
- [niri's confirming quit moves in as an instant log out](issues.md#niris-confirming-quit-moves-in-as-an-instant-log-out)
- [After a sway reload, gapsOut and SwayFX's per-window blur and shadows stay off until the look changes](issues.md#after-a-sway-reload-gapsout-and-swayfxs-per-window-blur-and-shadows-stay-off-until-the-look-changes)
- [A sway title-bar mouse bind moves in as a whole-window bind](issues.md#a-sway-title-bar-mouse-bind-moves-in-as-a-whole-window-bind)
- [A sway exec chained with ; or , moves in as one shell command](issues.md#a-sway-exec-chained-with--or--moves-in-as-one-shell-command)
- [A sway include path with a space breaks after a takeover](issues.md#a-sway-include-path-with-a-space-breaks-after-a-takeover)
- [A sway output rule by description misses a monitor with no serial](issues.md#a-sway-output-rule-by-description-misses-a-monitor-with-no-serial)
- [Managed mode's monitor-conflict check misses quoted and block output lines](issues.md#managed-modes-monitor-conflict-check-misses-quoted-and-block-output-lines)
- [The detached layer's unbind list can drift from what sway holds](issues.md#the-detached-layers-unbind-list-can-drift-from-what-sway-holds)
- [Small shrinks in SwayManager](issues.md#small-shrinks-in-swaymanager)
- [Sway and niri each forward withMainBinds to the daemon](issues.md#sway-and-niri-each-forward-withmainbinds-to-the-daemon)
- [SwayConfigBinds keeps its own copy of sway's $variables](issues.md#swayconfigbinds-keeps-its-own-copy-of-sways-variables)
- [Small shrinks in the sway writer and IPC](issues.md#small-shrinks-in-the-sway-writer-and-ipc)
- [The sway extract's input-device case and isSwayFlag repeat the general rule](issues.md#the-sway-extracts-input-device-case-and-isswayflag-repeat-the-general-rule)
- [binds and takeover each keep their own isFile and git check](issues.md#binds-and-takeover-each-keep-their-own-isfile-and-git-check)
- [niri's overview drop moves a window's whole column and switches workspace](issues.md#niris-overview-drop-moves-a-windows-whole-column-and-switches-workspace)
- [sway's named workspaces all share workspace id -1](issues.md#sways-named-workspaces-all-share-workspace-id--1)
- [sway lists disabled outputs as outputs](issues.md#sway-lists-disabled-outputs-as-outputs)
- [niri doesn't send windowFocused for a window that opens focused](issues.md#niri-doesnt-send-windowfocused-for-a-window-that-opens-focused)
- [sway's merge moves workspace binds as raw sway commands](issues.md#sways-merge-moves-workspace-binds-as-raw-sway-commands)
- ["Fire on release" is offered on niri and silently dropped](issues.md#fire-on-release-is-offered-on-niri-and-silently-dropped)
- [The Monitors page's Apply misses a niri-spelled monitor on Hyprland and sway](issues.md#the-monitors-pages-apply-misses-a-niri-spelled-monitor-on-hyprland-and-sway)
- [Three settings stay editable on niri though its writer drops them](issues.md#three-settings-stay-editable-on-niri-though-its-writer-drops-them)
- [Mouse speed, acceleration and left-handed reach the touchpad only on Hyprland](issues.md#mouse-speed-acceleration-and-left-handed-reach-the-touchpad-only-on-hyprland)
- [sway and niri build output details and descriptions twice](issues.md#sway-and-niri-build-output-details-and-descriptions-twice)
- [The bind merge lists user/ files three times, once per compositor](issues.md#the-bind-merge-lists-user-files-three-times-once-per-compositor)
- [sway's and niri's merges build a moved bind the same way twice](issues.md#sways-and-niris-merges-build-a-moved-bind-the-same-way-twice)
- [The merge keeps key and variable tables render already has](issues.md#the-merge-keeps-key-and-variable-tables-render-already-has)
- [A backed toast's blur fill is at the surface opacity twice](issues.md#a-backed-toasts-blur-fill-is-at-the-surface-opacity-twice)
- [A keepFill opening leaves an unfilled row in an unbacked translucent pill](issues.md#a-keepfill-opening-leaves-an-unfilled-row-in-an-unbacked-translucent-pill)
- [The editable dropdown's list fills translucent over the overlay](issues.md#the-editable-dropdowns-list-fills-translucent-over-the-overlay)
- [SlideAnimation's fade, easing and container aliases are dead](issues.md#slideanimations-fade-easing-and-container-aliases-are-dead)
- [The blur window builds stand-ins and copies it never uses](issues.md#the-blur-window-builds-stand-ins-and-copies-it-never-uses)
- [BlurBacking spells out four near-identical blur windows](issues.md#blurbacking-spells-out-four-near-identical-blur-windows)
- [The border frame's path is built three times](issues.md#the-border-frames-path-is-built-three-times)
- [Small shrinks in the blur system](issues.md#small-shrinks-in-the-blur-system)
- [Edge and floating popouts never close when their focus grab clears](issues.md#edge-and-floating-popouts-never-close-when-their-focus-grab-clears)
- [An open edge popout's layer and namespace still follow its edge's bar](issues.md#an-open-edge-popouts-layer-and-namespace-still-follow-its-edges-bar)
- [EdgePopout works out its attach edge and slide distance itself](issues.md#edgepopout-works-out-its-attach-edge-and-slide-distance-itself)
- [A large corner radius folds a pill's or shallow box's outline back on itself](issues.md#a-large-corner-radius-folds-a-pills-or-shallow-boxs-outline-back-on-itself)
- [A tray submenu longer than the screen runs off it](issues.md#a-tray-submenu-longer-than-the-screen-runs-off-it)
- [The Updates popout's package list is frozen at opening](issues.md#the-updates-popouts-package-list-is-frozen-at-opening)
- [NowPlaying builds its strip layout and a second transport hidden in every mode](issues.md#nowplaying-builds-its-strip-layout-and-a-second-transport-hidden-in-every-mode)
- [popout_matrix.py crashes on the current config and nothing runs it](issues.md#popout_matrixpy-crashes-on-the-current-config-and-nothing-runs-it)
- [PopoutWrapperBase's aboutToDismiss signal has no listener](issues.md#popoutwrapperbases-abouttodismiss-signal-has-no-listener)
- [Three EdgePopout members nothing reads](issues.md#three-edgepopout-members-nothing-reads)
- [PopoutGeometry handles a phase and a submenu pair the registry never produces](issues.md#popoutgeometry-handles-a-phase-and-a-submenu-pair-the-registry-never-produces)
- [PillBarJoin's available repeats what joined already says](issues.md#pillbarjoins-available-repeats-what-joined-already-says)
- [Geometry members nothing reads](issues.md#geometry-members-nothing-reads)
- [SurfaceContext.layout's pill and merged results have no test row](issues.md#surfacecontextlayouts-pill-and-merged-results-have-no-test-row)
- [The tray menu's isVertical and barConfig are never read](issues.md#the-tray-menus-isvertical-and-barconfig-are-never-read)
- [Both tray menu lists override the same width cap](issues.md#both-tray-menu-lists-override-the-same-width-cap)
- [The tray menu draws its own separator](issues.md#the-tray-menu-draws-its-own-separator)
- [The two workspace popouts share 28 lines of payload and colour properties](issues.md#the-two-workspace-popouts-share-28-lines-of-payload-and-colour-properties)
- [Small improvements to WorkspaceGrid](issues.md#small-improvements-to-workspacegrid)
- [The dock's footprint assumes fillets at both ends](issues.md#the-docks-footprint-assumes-fillets-at-both-ends)
- [Nothing listens to the bar's layoutUpdated any more](issues.md#nothing-listens-to-the-bars-layoutupdated-any-more)
- [A bar made while the bar editor is open may never report to it](issues.md#a-bar-made-while-the-bar-editor-is-open-may-never-report-to-it)
- [A second bar on an edge is invisible to the screen-edge answers, and New bar makes one](issues.md#a-second-bar-on-an-edge-is-invisible-to-the-screen-edge-answers-and-new-bar-makes-one)
- [Plugging in or unplugging a monitor remakes the bar that stays](issues.md#plugging-in-or-unplugging-a-monitor-remakes-the-bar-that-stays)
- [Removing or copying another bar moves the editor's selection to a different bar](issues.md#removing-or-copying-another-bar-moves-the-editors-selection-to-a-different-bar)
- [A corner piece's pull-out re-derives a bar's reserve and misses its clamp](issues.md#a-corner-pieces-pull-out-re-derives-a-bars-reserve-and-misses-its-clamp)
- [The pill merge in BarContainer repeats BarLayout's, untested](issues.md#the-pill-merge-in-barcontainer-repeats-barlayouts-untested)
- [StandaloneBar only wraps BarPanel's BarContainer](issues.md#standalonebar-only-wraps-barpanels-barcontainer)
- [BarContainer._withEntry rebuilds Utils.withEntry](issues.md#barcontainer_withentry-rebuilds-utilswithentry)
- [enrichBarConfig hands out two fields nothing reads and keeps three dead fallbacks](issues.md#enrichbarconfig-hands-out-two-fields-nothing-reads-and-keeps-three-dead-fallbacks)
- [A bar's reserve trim is worked out again by callers holding the enriched bar](issues.md#a-bars-reserve-trim-is-worked-out-again-by-callers-holding-the-enriched-bar)
- [Missing test rows for two helper decisions](issues.md#missing-test-rows-for-two-helper-decisions)
- [An overlay misses a transparent bar's inner accent line](issues.md#an-overlay-misses-a-transparent-bars-inner-accent-line)
- [WindowLookConfig rebuilds BarStyle.look](issues.md#windowlookconfig-rebuilds-barstylelook)
- [Ticking labels without steadyDigits resize the bar under a proportional font](issues.md#ticking-labels-without-steadydigits-resize-the-bar-under-a-proportional-font)
- [Media squeezed to its minimum in the fill style shows the meter, not its icon](issues.md#media-squeezed-to-its-minimum-in-the-fill-style-shows-the-meter-not-its-icon)
- [The Workspaces widget's measured length glides when the active cell widens](issues.md#the-workspaces-widgets-measured-length-glides-when-the-active-cell-widens)
- [A custom clock format without spaces spills past a vertical bar](issues.md#a-custom-clock-format-without-spaces-spills-past-a-vertical-bar)
- [Tray icons keep their pixel size on a bar thinner than them](issues.md#tray-icons-keep-their-pixel-size-on-a-bar-thinner-than-them)
- [Some bar widget sizes are fixed pixels, not the bar's](issues.md#some-bar-widget-sizes-are-fixed-pixels-not-the-bars)
- [SystemStats' used memory clips on a vertical bar](issues.md#systemstats-used-memory-clips-on-a-vertical-bar)
- [The stacked style clips on a thin bar](issues.md#the-stacked-style-clips-on-a-thin-bar)
- [BaseWidget's background box and panel-size defaults are dead](issues.md#basewidgets-background-box-and-panel-size-defaults-are-dead)
- [SystemStats works out ValueStyleWidget's style fallbacks again](issues.md#systemstats-works-out-valuestylewidgets-style-fallbacks-again)
- [The workspace switchers find a workspace by id with hand-written loops](issues.md#the-workspace-switchers-find-a-workspace-by-id-with-hand-written-loops)

Found while reworking the onboarder:
- [The onboarder's Integrations page names Hyprland's tools everywhere](issues.md#the-onboarders-integrations-page-names-hyprlands-tools-everywhere)
- [The onboarder's Integrations page is too long for one step](issues.md#the-onboarders-integrations-page-is-too-long-for-one-step)
- [The Look page offers Hyprland's wallpapers under any compositor](issues.md#the-look-page-offers-hyprlands-wallpapers-under-any-compositor)

### Phase 12: memory footprint
The shell's RSS at rest and after use, measured rather than guessed: about 840 MB at rest and over 1 GB after use on one monitor (2026-10-27), almost all of it C++ heap and per-window renderer state, not JS.

0. **Done:** **Measure** (row 9; [memory](core/memory.md)): a memory reading script (RSS, Private_Dirty, AnonHugePages, the JS heap, render threads) and a `--mem` option for `scripts/dev/bench_overlay.sh` (the reading after each open/close cycle), run in a nested session, with a baseline recorded in a doc. Every entry below is judged by it.

- **Done:** the shell's heap never shrinking after a spike (row 9; maintainer, 2026-10-27: "yes, opt the shell out of THP"): qs runs with transparent huge pages off, 110–125 MB less at rest and after use; the daemon and what it launches keep them ([memory](core/memory.md) › Transparent huge pages).
- [Nineteen windows stay mapped on one monitor](issues.md#nineteen-windows-stay-mapped-on-one-monitor)
- [Images decoded at full size or more than once](issues.md#images-decoded-at-full-size-or-more-than-once)

### Phase 13: the maintainer's notes
Bugs and small features from the maintainer's own use, filed from their notes on 2026-10-28 (compositor-specific ones are in [Phase 6](#phase-6-compositor-parity), fit ones in [Phase 7](#phase-7-fit-geometry-and-performance)). Each feature step follows its recipe (`setting`, `settings-card`, …); the plans go through [Items that need a plan](#items-that-need-a-plan).

Steps:
1. **Done:** **niri's own overview** (row 16): a setting to open niri's built-in overview in place of axiom's workspace overview, on by default where it's offered. It's gated on a `supports.*` capability, never the compositor's name. The maintainer: "simply a button option to use niris builtin instead". Also: "note this also should disable the default bind on niri (in both cases, force users through axioms bind)"; on detached mode: "detatched mode shouldn't disable binds at all. Logic remains if they have alt tab set in aciom, but niris default / set in config will just be there as well"; on the overview bind (2026-10-29): "Managed only (Recommended) — Managed mode comments Mod+O out when it adopts the config, as it does other moved binds. Included mode is treated like detached: it never edits the user's file, so niri's bind stays alongside axiom's." `WorkspaceOverlay.compositorOverview` (`supports.overview`) routes everything that opens axiom's overview to niri's; managed mode's adopt merge moves niri's `toggle-overview` bind into axiom as its overview bind (commented out in the user's file), detached and included leave niri's binds alone.
2. **Done:** **Module borders on the overlay** (row 16): a setting, `Overlay.moduleBorders` (on by default, one for every page like `Overlay.moduleScale`), turns the overlay's module card boxes off; the modules keep their padding. Edge menus, the desktop, the lock screen and the greeter already had their layout's `moduleBorders`. The gaps half of the maintainer's note is deferred (Overlay gaps).
3. **Done:** **A test notification** (row 16): the notifications settings get a button that shows one, as the OSD and dock settings do, for easy editing. The section's `x-intro` (`NotificationsPreview`) has a Show button sending one through `NotificationManager.sendNotification`; it toasts with the settings as edited.
4. **Done:** **niri's own window switcher** (row 16): a setting, `WindowSwitcher.compositorSwitcher` (`supports.compositorSwitcher`, on by default where it's offered), has axiom's config writer bind the switch windows keys to niri's own switcher (`recent-windows`, which drops niri's default switcher keys) in included and managed mode. The maintainer: "while you are implementing the niri setting and logic a second setting should also use niri alt tab as acioms (same logic, replaces everything and is default on niri)" and "note this also should disable the default bind on niri (in both cases, force users through axioms bind)"; on detached mode: "detatched mode shouldn't disable binds at all. Logic remains if they have alt tab set in aciom, but niris default / set in config will just be there as well"; on the switcher (2026-10-29): "Writer binds niri's action (Recommended) — When the setting is on, axiom's config writer binds Alt+Tab straight to niri's own switcher action instead of axiom's IPC (included and managed mode only). In detached mode the setting does nothing, and the user's own niri binds handle alt-tab." With no switcher bind of axiom's (2026-10-29): "default to off for window switcher if not bind set. Everything goes through aciom", "on managed mode", "sounds good. (i.e. in managed, if the user doesn't have a window switcher / overlay bind, there is no bind for it). Binds are exactly representative of what there is.": managed writes the switcher's binds empty (the setting off too), so niri's default keys are gone; included leaves them.
5. **Done:** **Caffeine on a timer** (from the waiting list): caffeine (the idle inhibitor) can be turned on for a set time and turns itself off after it. The maintainer (2026-10-29): "decision for caffeine on a timer: works similarity to stopwatch current implementation. Popout shows presets (default 30min, 1hr, 4hr) that start with a timer. Presets are settable in module settings." and "ensure timer starting and selecting and whatnot is a re-used component (i.e. so caffeine and stopwatches look identical)" The IdleInhibitor widget gets its own popout (`content/Caffeine`, on by default for new widgets) with a `CountdownTimer` (`content/parts/`, the one-off timer's start, presets, ring and controls, now shared with `content/Stopwatch`) over the widget's `presets` (30m, 1h, 4h); `IdleManager` keeps the timer in a `DeadlineTicker` that ends caffeine at its end, and the widget, quick action and `/caffeine` show the time left.
6. **Built-in stock and crypto trackers** (added 2026-10-29): a bar widget and a module (overlay, desktop, edge menu) for watched symbols, built in rather than through a custom widget script: prices polled by the daemon as a topic (`acquire`/`release`, the interval from config), the symbols and their order in a config section, each with its change, a sparkline of the day and the up/down colour; a ticker on the bar as the custom widget's ticker style does. Needs a plan first ([Items that need a plan](#items-that-need-a-plan)): the data sources (a free stock API and a crypto one, or one for both), API keys through `SecretsManager`, rate limits and caching, and market hours.
7. **Done:** **Notifications revamp** (added 2026-10-30, the maintainer's own request while row 16 is on hold): toasts placed like the OSD, dock and launcher, attached or detached; motion; clicks, withdrawals and matching; interactivity; settings. The maintainer: "when close to a bar and popping out from the border, it wraps a floating bar identically to how the menu does … if a popout is open it would have to appear below and animate to it's correct spot when the popout closes). Pill, standard and transparent bars also need to be taken into account"; attached, "The whole stack, one box"; "when attatched to the right edge, they should slide in and out towards the edge as well. Detatched should probably go to the closest edge (actual edge, disregarding bars)"; a lower toast leaving: "Tuck behind and fade"; clicks: "Run action, then focus app"; app control: "One 'Follow apps' setting"; extras: "Inline reply + action icons, DND schedule, Per-app rules"; sounds wait for a later axiom-sounds PR. `ToastStack`/`ToastItem` on `methods/ToastMotion`, ranked under every popout (`PopoutGeometry`; the maintainer on collisions: "Yield, then come back") (steps v83, v84), `NotificationMatch`, `NotificationReply`, `Notifications.dnd` and `Notifications.apps` ([notifications](features/notifications.md)).

- **Done:** **Overlay and popouts close or break each other** (row 16; plan #211, the maintainer: "close on outside click currently has the exact desired behaviour. Bar and interactive module clicking does not close it, only where the blur backing would be. Close all popouts and menus (except integrated, since they move the overlay) when the overlay is opened."): the overlay closes only on a real click (its empty background, or a screen's backdrop without a native grab: `FocusGrab.clickedOutside`), never on its grab ending (a polkit prompt closing, another surface's grab), and opening it closes the bar popouts and floating edge menus on its screen (`PopoutManager.closeOn`).

- **Done:** **Low levels spill out of their rounded troughs** (row 16; the maintainer: "anything with a bar with corner radius that extends to fill a container (the two I directly notice are the custom module pill style mode (with the colored fill that fills the module based on percentage), and the osd bars, there may be more though), has a problem of when appearing (i.e. 0-10 ish percentage), since it has a small width, the corner radius doesn't get fully fleshed out, causing a rectangle look (which spills out of its "trough"'s corner radius.)) Fix this"): a fill shorter than twice its radius had its radius clamped. A bar widget's `backgroundLevel` is now the background's own shape seen through a `ClippingRectangle` window with a rounded leading edge (`WidgetBackground`), `StyledVolumeBar`'s trough (the OSD's bars) clips its fill, and the Disks and Claude usage modules' meters are `LevelMeter`s (never shorter than their rounded ends), as the custom widgets' already were.
Found meanwhile:
- [Submenus don't always get their blur backing](issues.md#submenus-dont-always-get-their-blur-backing)
- [A greeter-only module validates on any page](issues.md#a-greeter-only-module-validates-on-any-page)
- [Opening a hover-closing edge menu by IPC closes it at once](issues.md#opening-a-hover-closing-edge-menu-by-ipc-closes-it-at-once)
- [config.json replaced by rename isn't always read by the live daemon](issues.md#configjson-replaced-by-rename-isnt-always-read-by-the-live-daemon)
- [BlurManager.paused reads undefined on a reload](issues.md#blurmanagerpaused-reads-undefined-on-a-reload)

Needs a plan:
- [The window switcher's blur and release on sway and niri](issues.md#the-window-switchers-blur-and-release-on-sway-and-niri)

Waiting for the maintainer (moved here 2026-10-29 so they don't block the row; the maintainer: "they may be vague and require testing. If so, mark it, push it to the end of the phase so it doesn't block and I will handle all the questions then"):
- [Setting names that still confuse](issues.md#setting-names-that-still-confuse). *Needs the maintainer:* the note ("still confusing option names in settings") names no settings, so which ones read wrong is theirs to list.
- [The monitor editor shows changes nobody made](issues.md#the-monitor-editor-shows-changes-nobody-made). *Needs testing:* in nested niri a saved profile for what's connected opens the page with nothing unsaved (the draft only changes through an edit or `_detect` adding a profile or a monitor the daemon's match doesn't list); on which compositor, and after what (opening the page, an Apply, a hotplug, a reload), does it show?
- [Typing in modules on the overlay and the desktop](issues.md#typing-in-modules-on-the-overlay-and-the-desktop). *Needs testing:* nothing in the code keeps the keyboard from an overlay module (the overlay asks for it on demand like the edge menus, exclusively under a grab with no native one, the newest grab since #193, and no handler above the modules takes keys), and only a real click into a field shows it, which the agents may not simulate. On which compositor does it happen, in which module, and does the field show a cursor with the keys going nowhere, or not take the click? On the desktop: is the click that ends the typing on a window (where it gives the keyboard back by design, [desktop](features/desktop.md) › Input), on the bare desktop beside the module, or inside the module itself? (Under niri's focus following the mouse, it's the deferred [A window takes the keyboard from a desktop module on niri](issues.md#a-window-takes-the-keyboard-from-a-desktop-module-on-niri).)
- [A hot corner can't close what covers it](issues.md#a-hot-corner-cant-close-what-covers-it). *Needs the maintainer:* should a corner stay live over Overlay-layer surfaces (the workspace overview, a full-screen page), so it can close what it opened, as niri's own corner does?
- [A VPN's password request can go unseen](issues.md#a-vpns-password-request-can-go-unseen). *Needs the maintainer:* which surface shows a request no open row shows (open the VPN popout, a notification, or decline so nm-applet asks).
- [Close on outside click differs on Hyprland since the overlay ignores its grab ending](issues.md#close-on-outside-click-differs-on-hyprland-since-the-overlay-ignores-its-grab-ending). *Needs the maintainer:* should a click outside the overlay's window (another monitor, the screen border, a floating bar's gap) close it, as it still does on sway and niri, or not, as now on Hyprland?

### Deferred
Entries decided against doing now: a plan the maintainer deferred ([Items that need a plan](#items-that-need-a-plan) step 5), or an entry they put off by hand. They block no row; the maintainer moves them to GitHub, and an entry leaves this list and issues.md together.

Extremely rare paths, put after real gaps (2026-10-26):
- [Leaving managed, the runtime layer can go on before the given-back config reloads](issues.md#leaving-managed-the-runtime-layer-can-go-on-before-the-given-back-config-reloads) (transient: corrected after the reload)
- [Saving a profile that names a new monitor can move other monitors' blocks](issues.md#saving-a-profile-that-names-a-new-monitor-can-move-other-monitors-blocks) (found in row 13's review)

Deferred by the maintainer (2026-10-27):
- [Readers read files through a service](issues.md#readers-read-files-through-a-service)
- [The daemon's own commands are left zombies across a re-exec](issues.md#the-daemons-own-commands-are-left-zombies-across-a-re-exec)

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
- [No caps lock warning when typing a password](issues.md#no-caps-lock-warning-when-typing-a-password)
- [Removable drives aren't handled](issues.md#removable-drives-arent-handled)
- [Bluetooth pairing that asks for a PIN or a passkey](issues.md#bluetooth-pairing-that-asks-for-a-pin-or-a-passkey)
- [No OSD for caps lock or the keyboard layout](issues.md#no-osd-for-caps-lock-or-the-keyboard-layout)
- [No keyboard backlight control](issues.md#no-keyboard-backlight-control)
