# Cleanup roadmap

> **Files:** this file, [issues.md](issues.md)
> **Config:** none
> **Related:** [Moving the service layer to the axiom binary](backend/roadmap.md), [Known issues](issues.md), [Developer docs](README.md)

The phased plan for getting the repository into an excellent, clean state: correct on its rarely taken paths, organized so each file has one job and an obvious home, equal on every compositor, quiet in its log, and documented without excess. It turns [issues.md](issues.md) into an order of work: every entry there is linked from the phase that resolves it.

It runs alongside [the backend roadmap](backend/roadmap.md), which moves the services' side effects into the axiom binary and is likely to land first. That roadmap owns the migration; this one never restates its stages, only points at them and lists what waits for them.

### Rules
- **One item, one PR**, moves separate from logic changes (a move PR changes no behaviour, so its diff reviews as a rename). Each ends with `scripts/dev/verify.sh` printing `verify ok`.
- **A fix removes its entry from issues.md and its link here** in the same change; a phase is done when its list is empty. A new issues.md entry gets a link in the phase that will fix it.
- **Waits for a backend stage** means the item touches code that stage deletes or rewrites: it's done in that stage's change or after it, never before (no polishing code about to go). Items without one can run at any time, in parallel with the backend roadmap.
- Phases are grouped by kind, not run in number order: [Full order](#full-order) interleaves them with the backend stages. Three rules set it: moves land in quiet windows between stages (they collide with everything); enforcement (archtest, the contract check) lands before the stages that add packages; and nothing polishes code a stage will replace.

### Done means
- `scripts/dev/verify.sh --all` is green, and a reload logs only `Reloading configuration...` and `Configuration Loaded` under Hyprland, niri and sway.
- issues.md holds only "needs a plan" entries, each moved to GitHub by the maintainer.
- `scripts/quickshell-io-allowlist.json` lists only the permanent funnels (`BackendManager`'s socket, `FileManager`'s blocking read).
- No singleton over about 800 lines outside the pure helpers and the compositor backends; every file sits in the folder its rule names.
- `archtest` enforces the backend's dependency direction; the shell–daemon method shapes are checked on both sides.
- The root `AGENTS.md` is 12 KB or less; generated docs are built, not committed.

### Alignment with the backend roadmap

| Phase | Waits for (backend stage) | Folds into a stage |
|---|---|---|
| 0. Decisions and quick wins | none | none |
| 1. Integrity | none | the config save path → stage 7 |
| 2. Finish stage 2 | is stage 2 | clipboard, night light |
| 3. QML structure | ChatProvidersCard → stage 5; the `KeybindManager` split → stage 7 | services a stage empties are folded in that stage |
| 4. Backend structure and contract | none (lands before stage 7, so its switch to path ops is checked) | none |
| 5. The allowlist | stages 3–7 | is those stages |
| 6. Compositor parity | stage 7 (one compositor writer left); runtime-only bugs: none | none |
| 7. Fit, geometry, performance | the chat lists → stage 5 | none |
| 8. A clean log | stage 6 for the socket warnings; the rest: none | none |
| 9. Docs, tooling, process | `config-v2.md` → stage 7 | none |

### Full order
Both roadmaps as one sequence. A row starts when the one above it has merged; the parallel lane fills the gaps at any time. **Status** is `done`, `in progress` (normally one row), `next` (the row after it) or `later`; it's kept current by [Taking the next step](#taking-the-next-step), so the first row not `done` is always where work resumes.

| # | Status | Work | Why here |
|---|---|---|---|
| 1 | done | Backend stage 2: night light, then clipboard (and [Phase 2](#phase-2-finish-stage-2)) | In progress; finish it before anything else churns the same files. |
| 2 | in progress | [Phase 0](#phase-0-decisions-and-quick-wins): stop committing generated docs | Right after stage 2 merges, so it doesn't collide with that work's regenerated docs; every later diff shrinks. |
| 3 | next | [Phase 1](#phase-1-integrity), except the two save-path entries (stage 7's) | Data and session safety first; touches nothing a stage deletes. |
| 4 | later | [Phase 4](#phase-4-backend-structure-and-contract) | archtest and the contract check land before stages 3 to 6 add packages and before stage 7 rewrites saves, so both are checked as they're written. |
| 5 | later | [Phase 3](#phase-3-qml-structure)'s moves and splits (not `KeybindManager`), and [Phase 5](#phase-5-the-allowlist)'s `execDetached` quick wins | One quiet window for every move, while the backend roadmap sits between stages. |
| 6 | later | Backend stage 3: brightness | Small; a first stage under the new checks. |
| 7 | later | Backend stage 4: scripts | The largest stage (theming, calendar, hookup, self-update, greeter installer). |
| 8 | later | Backend stage 5: HTTP | Unblocks `ChatProvidersCard` and the chat lists (Phases 3 and 7). |
| 9 | later | Backend stage 6: the funnels | Changes the compositor sockets behind several log warnings. |
| 10 | later | Backend stage 7: the config path, with the `KeybindManager` split | Closes the takeover leak and the save order; a thin `compositor.inputs` changes what `KeybindManager` reads, so it's split once, on the new shape. |
| 11 | later | [Phase 6](#phase-6-compositor-parity) | After stage 7 only Go writes compositor configs, so a sway or niri fix lands once, not in both renderers. |
| 12 | later | [Phase 8](#phase-8-a-clean-log) | After stage 6, the socket warnings are gone or real. |
| 13 | later | [Phase 9](#phase-9-docs-tooling-and-process) | Last, so the docs describe the final shape. |

**Parallel lane** (any time, between rows): [Phase 7](#phase-7-fit-geometry-and-performance); parity bugs outside the compositor writer (the niri screencopy crash, the red screen after a reload while locked, nested niri freezing); log warnings no stage touches (the notification avatar, missing app icons, `BlurManager.paused`).

### Taking the next step
What an agent does when asked for "the next step", to "continue the roadmap", or to work on a row or phase by number. The answer to "where do I start" is always this file: nothing else needs explaining.

1. **Find the step.** The first [Full order](#full-order) row not `done`. Its work is the backend stage's bullets in [backend/roadmap.md](backend/roadmap.md) (a stage row) or the phase section below (a phase row). A row named by the user wins; so does a parallel-lane item they name.
2. **Check nobody holds it.** `git log -5` and `git status`: uncommitted changes in that row's files mean another agent is on it. Then take the next unblocked item (the parallel lane, or a later row with nothing waiting), or ask.
3. **Pick one item.** One PR: a backend stage's next not-`Done` bullet, or a phase's first step not marked `Done:` and then its listed issues in order. Read the item's issues.md entry, the docs for its area (`AGENTS.md` › Where to look), the matching recipe if there is one, and [issues.md](issues.md) for anything else known in those files.
4. **Do it**, and run `scripts/dev/verify.sh` until `verify ok`.
5. **Update the roadmaps in the same change:**
   - remove the fixed issues.md entry and its link here;
   - mark a finished phase step `Done:` at its start (as backend/roadmap.md marks its bullets);
   - when a row's last item is done, set its Status to `done`, the next row's to `in progress` and the one after to `next`; a stage row also updates its status in backend/roadmap.md;
   - anything learned that changes the order is an edit to [Full order](#full-order) with its reason in the "Why here" cell.
6. **Report** what was done, what the next item is (the user's next "next step"), and anything found and filed in issues.md along the way.

### Running it unattended
The cycle the `roadmap-autopilot` skill runs, one item per iteration, driven by `/loop /roadmap-autopilot` in a session of its own (auto mode, so git and gh don't stop it for permission). It works in the live checkout, so the desktop reloads as branches change; nothing else may be working in this checkout meanwhile. With `--dry-run` it only reports the item it would take.

1. **Preflight.** On `main`, `git status` clean (anything uncommitted means someone else is working here: stop), `git pull --ff-only`. An open PR labelled `roadmap` (`gh pr list --label roadmap`) is resumed at the step it reached instead of starting a new item; one labelled `needs-decision` waits for the user and blocks its row.
2. **Pick** with [Taking the next step](#taking-the-next-step) steps 1–3. Stop and report instead of starting when the item is "needs a plan", needs a maintainer decision (a changed default, whether a migration is worth it, a behaviour trade-off), needs a live action `AGENTS.md` › Never forbids (takeovers, the greeter, the real lock, idle on the live config, restarting axiom), or waits on a row that isn't `done`.
3. **Branch** `roadmap/<row>-<slug>` from `main`. A checkout replaces files' inodes, so force a QML reload ([testing](testing.md) › Reloads and logs) and wait for `Configuration Loaded` in `scripts/log.sh`.
4. **Implement**: the area's docs and recipe, `scripts/dev/verify.sh` until `verify ok`, then [Taking the next step](#taking-the-next-step) step 5 (statuses, `Done:` marks, issues.md removals) in the same commit, ending with the attribution trailer. What the live session can't show (Go code: the running binary isn't rebuilt; a schema change: the daemon reads the schema at its start) rests on its tests, and the PR says so.
5. **PR**: `git push -u origin HEAD`, `gh pr create --label roadmap`; the body names the Full order row and item, links the issues.md entries it closes, and says what was verified and what couldn't be live.
6. **Review**: a fresh `general-purpose` subagent (so the review isn't anchored on the implementer's reasoning) runs the `review-branch` skill with the PR's intent and `--fix`. Commit its fixes, verify, push. At most two rounds, until no Blocker or Major finding is left. Questions, or a Blocker it couldn't fix: label the PR `needs-decision`, comment the findings on it, and stop.
7. **CI**: `gh pr checks <n> --watch`. A failure is fixed and pushed, at most twice; then stop with the PR open.
8. **Merge**: `gh pr merge <n> --squash --delete-branch`, `git checkout main`, `git pull --ff-only`, force a reload, and read `scripts/log.sh`: a new warning becomes an issues.md entry (with its roadmap link) in the next item.
9. **After**: refresh the roadmap page if one is kept (the maintainer's, outside the repo). If this merge set a Full order row to `done`, stop the loop and report the row (the pause between rows, so the maintainer looks before the next one starts); otherwise schedule the next iteration.

Never, besides `AGENTS.md` › Never: merge a PR without the `roadmap` label, put two items in one PR, skip the review or CI, or retry a stop condition. A wallpaper-only screenshot means the session locked while idle: stop and ask the user to unlock.

### Phase 0: decisions and quick wins
Decided (2026-10-26):
- **Generated docs are no longer committed.** `docs/dev/generated/` and `docs/dev/config/` go in `.gitignore` (`git rm --cached`), `scripts/generate.sh` builds them like the schema JSON, CI generates them instead of failing when stale, the pre-commit hook stops adding them, and `AGENTS.md` › Checks and `.gitignore`'s comment say so. About 290 files and 12k lines leave the tree and every PR's diff.
- **The shell's `takeover: true` is fixed by backend stage 7**, with no stopgap before it: saves become path ops, only a takeover card's op carries `takeover`, live edits go through `ConfigManager.setPreview`, and config writes are applied in the order sent.
- **Idle is the daemon's** (done in stage 2, on its own D-Bus client); hypridle is no longer a dependency.
- **Tailscale's floor comes from the schema**: the topic reads the `interval` setting's `minimum` rather than a constant, so no migration.
- **`TailscaleManager` moves to `services/apps/`** (Phase 3).

Quick wins: run `git gc` locally (most of a clone's `.git` is loose objects; packed history is about 18 MB).

### Phase 1: integrity
The config, the takeover and the session must never be damaged by a rarely taken path. The shell's save path itself is stage 7's (rewritten there), so its two entries are linked here and fixed there.

Fixed in this phase:
- [A missing embedded schema counts as this binary's](issues.md#a-missing-embedded-schema-counts-as-this-binarys)
- [BackendManager's listeners and reconnect are fragile](issues.md#backendmanagers-listeners-and-reconnect-are-fragile)
- [An outside edit of config.json can release a managed compositor config](issues.md#an-outside-edit-of-configjson-can-release-a-managed-compositor-config)
- [Any change of the mode to managed approves the takeover](issues.md#any-change-of-the-mode-to-managed-approves-the-takeover)
- [Unreadable sway config means axiom binds over the user's keys](issues.md#unreadable-sway-config-means-axiom-binds-over-the-users-keys)
- [Leaving managed, the runtime layer can go on before the given-back config reloads](issues.md#leaving-managed-the-runtime-layer-can-go-on-before-the-given-back-config-reloads)
- [`axiom lock` fails with no screen connected](issues.md#axiom-lock-fails-with-no-screen-connected)
- [Some backend security checks have no tests](issues.md#some-backend-security-checks-have-no-tests)
- [The greeter's environment is a denylist](issues.md#the-greeters-environment-is-a-denylist)
- [Small backend error and robustness gaps](issues.md#small-backend-error-and-robustness-gaps)
- [Schema build gaps](issues.md#schema-build-gaps)
- [The binds child sometimes segfaults instead of running out of memory](issues.md#the-binds-child-sometimes-segfaults-instead-of-running-out-of-memory)

Fixed by backend stage 7 (add the bullets there if missing):
- [Shell saves carry unsaved settings and every takeover](issues.md#shell-saves-carry-unsaved-settings-and-every-takeover)
- [Config saves can land out of order](issues.md#config-saves-can-land-out-of-order)

### Phase 2: finish stage 2
Done: [backend stage 2](backend/roadmap.md) (Wayland), with its own entries: the hypridle autostart default (dropped, and from saved configs by the v78 step) and the D-Bus match rules' escaping.

### Phase 3: QML structure
Each file has one job and sits where its folder's rule says. Moves and splits keep each service's public API, so widgets don't change; a service a backend stage empties is folded in that stage instead.

Steps, roughly in this order (moves first, each its own PR):
1. Move `TailscaleManager` to `services/apps/` and reword `services/AGENTS.md` › Folders (`system/`: the machine and the desktop basics every user has; `apps/`: optional features and integrations with outside tools or services); `DailySchedule` to `core/`; `ShellManager` to `ui/`; document the non-singleton parts.
2. Move the reusable pieces holding feature logic to `components/bar/` or `content/parts/`.
3. Split `ShellManager` by concern and `EdgeMenuManager` into its runtime and its editor (the `KeybindManager` split, into its reader, a `KeybindEditor` and page state, goes with backend stage 7); extract `LauncherCommands`' `/config` browser; give the bars' and edge menus' reserved zones one owner.
4. A shared ticker part for Stopwatch and Pomodoro; `valueAt` into a methods helper with a test row.

Resolves:
- [Service folders hold misplaced and undocumented files](issues.md#service-folders-hold-misplaced-and-undocumented-files)
- [Shared pieces holding feature logic](issues.md#shared-pieces-holding-feature-logic)
- [Singletons doing several jobs](issues.md#singletons-doing-several-jobs)
- [Readers read files through a service](issues.md#readers-read-files-through-a-service)
- [Repeated plumbing](issues.md#repeated-plumbing)
- [`Bar` reader holds the edges enum and breaks reader naming](issues.md#bar-reader-holds-the-edges-enum-and-breaks-reader-naming)
- [The window shadow's offset is always 0 but still passed through every writer](issues.md#the-window-shadows-offset-is-always-0-but-still-passed-through-every-writer)
- [The onboarding's Compositor page names Hyprland](issues.md#the-onboardings-compositor-page-names-hyprland)
- [ChatProvidersCard runs its own requests](issues.md#chatproviderscard-runs-its-own-requests) (waits for stage 5: `ChatRequest` moves to the daemon)

### Phase 4: backend structure and contract
The binary's rules are enforced by its tests, and the shell–daemon contract is checked by shape, not just by name. The contract check lands before stage 7, so the switch to path ops is checked as it happens.

Steps: generate method shapes into `rpc.md` and check QML call sites against them; extend `archtest` (dependency direction, no `init()` or package state, every package classified); fold `saved.everything` into `share`; settle `tree` against `schema/yamlsrc`; clearer package names (`system`, and `lock` against `fsx.Lock`); the Tailscale floor from the schema.

Resolves:
- [The shell–daemon contract is checked by name only](issues.md#the-shelldaemon-contract-is-checked-by-name-only)
- [archtest checks only the pure packages](issues.md#archtest-checks-only-the-pure-packages)
- [Backend packages with thin or no tests](issues.md#backend-packages-with-thin-or-no-tests)
- [backend/AGENTS.md's dependency table is incomplete](issues.md#backendagentsmds-dependency-table-is-incomplete)
- [Tailscale's poll interval allows values below axiom's 5 s floor](issues.md#tailscales-poll-interval-allows-values-below-axioms-5-s-floor)
- [The shell's socket warns when the daemon re-execs](issues.md#the-shells-socket-warns-when-the-daemon-re-execs)

### Phase 5: the allowlist
[Backend stages 3–7](backend/roadmap.md) are this phase; nothing here restates them. Before them, the files on the allowlist only for `Quickshell.execDetached` can switch to `CommandManager.runDetached` at any time (`GreetdManager`, `LockManager`, `LauncherManager`, `ShellManager`, `CompositorConfigManager`), shrinking the list early. Stage 7 also retires the code that exists twice: `SchemaValidation` against Go's pipeline, and the QML compositor renderers (`HyprLua`, `NiriConf`, `SwayConf`, `CompositorLayer`) against `compositor/render`.

Resolved by a stage:
- [Self-update and the greeter installer assume git](issues.md#self-update-and-the-greeter-installer-assume-git) (stage 4)

### Phase 6: compositor parity
Every feature works the same under each compositor, or says why not. It follows backend stage 7, when only Go writes compositor configs; bugs outside the writer (crashes, freezes, reload glitches) can go any time. sway is the largest cluster: take it as one pass in a nested sway (`scripts/dev/nested.sh sway`).

sway and SwayFX:
- [The greeter on sway can't use a cursor theme's companion](issues.md#the-greeter-on-sway-cant-use-a-cursor-themes-companion)
- [SwayFX remaps the chrome on a fresh qs start](issues.md#swayfx-remaps-the-chrome-on-a-fresh-qs-start)
- [The blur window's Top/Overlay switch may land over the bars on SwayFX](issues.md#the-blur-windows-topoverlay-switch-may-land-over-the-bars-on-swayfx)
- [The takeover makes only some of sway's relative includes absolute](issues.md#the-takeover-makes-only-some-of-sways-relative-includes-absolute)
- [Turning sway's window opacity off reloads sway](issues.md#turning-sways-window-opacity-off-reloads-sway)
- [SwayFX's corner radius reaches only windows opened later](issues.md#swayfxs-corner-radius-reaches-only-windows-opened-later)
- [Changing a setting under sway can flash the screen](issues.md#changing-a-setting-under-sway-can-flash-the-screen)
- [Sway's special workspaces are floating scratchpad windows](issues.md#sways-special-workspaces-are-floating-scratchpad-windows)
- [Overview drops on sway nest split containers](issues.md#overview-drops-on-sway-nest-split-containers)
- [Detached sway keeps the floating modifier after the mouse binds go](issues.md#detached-sway-keeps-the-floating-modifier-after-the-mouse-binds-go)
- [`noWarps` off maps to sway's `mouse_warping output`](issues.md#nowarps-off-maps-to-sways-mouse_warping-output)

niri:
- [A bar popout's stroke flashes off its fill switching content on niri](issues.md#a-bar-popouts-stroke-flashes-off-its-fill-switching-content-on-niri)
- [A hot reload while locked leaves niri's red screen](issues.md#a-hot-reload-while-locked-leaves-niris-red-screen)
- [Quickshell's wlr screencopy crashes the shell on niri](issues.md#quickshells-wlr-screencopy-crashes-the-shell-on-niri)
- [A niri module refused in detached mode is only logged](issues.md#a-niri-module-refused-in-detached-mode-is-only-logged)
- [niri reports no space reserved by bars, nor where tiled windows are](issues.md#niri-reports-no-space-reserved-by-bars-nor-where-tiled-windows-are)
- [niri's flags can't be turned off from axiom](issues.md#niris-flags-cant-be-turned-off-from-axiom)
- [Nested niri freezes while its window is hidden](issues.md#nested-niri-freezes-while-its-window-is-hidden)

Hyprland, and every compositor:
- [The scrolling layout's workspaces don't come back with their monitor](issues.md#the-scrolling-layouts-workspaces-dont-come-back-with-their-monitor)
- [A fullscreen window re-sends the whole live layer](issues.md#a-fullscreen-window-re-sends-the-whole-live-layer)
- [A fullscreen window on one screen pauses the blur on every screen](issues.md#a-fullscreen-window-on-one-screen-pauses-the-blur-on-every-screen)
- [Floating bars sit flush on the border without a backend](issues.md#floating-bars-sit-flush-on-the-border-without-a-backend)
- [Two exclusive-focus surfaces at once without a native grab](issues.md#two-exclusive-focus-surfaces-at-once-without-a-native-grab)

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
- [CommandOutput's figure text loops on its size](issues.md#commandoutputs-figure-text-loops-on-its-size)
- [Compact cards still build their full layout](issues.md#compact-cards-still-build-their-full-layout)
- [Unbounded lists still built in full](issues.md#unbounded-lists-still-built-in-full) (the chat lists wait for stage 5)
- [The community setups' check doesn't take monitor places yet](issues.md#the-community-setups-check-doesnt-take-monitor-places-yet)

### Phase 8: a clean log
A reload, and a session's normal use, log nothing but the two reload lines.

- [A notification's avatar warns when its saved image is gone](issues.md#a-notifications-avatar-warns-when-its-saved-image-is-gone)
- [Surfaces touch a dead screen after the outputs go away](issues.md#surfaces-touch-a-dead-screen-after-the-outputs-go-away)
- [Missing app icons warn in the log](issues.md#missing-app-icons-warn-in-the-log)
- [Text input warnings when the desktop takes the keyboard](issues.md#text-input-warnings-when-the-desktop-takes-the-keyboard)
- [Qt text-input warnings under sway and niri](issues.md#qt-text-input-warnings-under-sway-and-niri)
- [Quickshell's I3 socket warns on every reload](issues.md#quickshells-i3-socket-warns-on-every-reload)
- [`BlurManager.paused` warns on every reload](issues.md#blurmanagerpaused-warns-on-every-reload)

### Phase 9: docs, tooling and process
Last, so the docs describe the final shape.

Steps: trim the root `AGENTS.md` to its rules (mechanics move to the `docs/dev` pages it points at); fold `docs/dev/core/config-v2.md` into `schema-annotations.md` and `config-manager.md` once stage 7 finishes v2; the maintainer moves the remaining "needs a plan" entries to GitHub; a PR-size note in `CONTRIBUTING.md` (moves apart from logic, one item per PR).

Resolves:
- [The check order is kept in three places](issues.md#the-check-order-is-kept-in-three-places)
- [Small tooling leftovers](issues.md#small-tooling-leftovers)
- [The schema root's description contradicts the annotations doc](issues.md#the-schema-roots-description-contradicts-the-annotations-doc)
- [The calendar doc's Files header leaves out its page](issues.md#the-calendar-docs-files-header-leaves-out-its-page)
- [install.sh still installs the rest of a feature whose COPR was declined](issues.md#installsh-still-installs-the-rest-of-a-feature-whose-copr-was-declined)
