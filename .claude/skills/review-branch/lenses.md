# Review lenses

What every axiom review shares: how to read, what counts as a finding and how it's proven, its shape, the lead's agents, then the five lenses. `review-branch` walks all five over a diff; `review-system` (`../review-system/lenses.md`) adds its own and reads "the branch" as "the system", where nothing is pre-existing. In deep mode an agent's prompt is "Every reviewer" plus its lens.

## Every reviewer

You review axiom, a Quickshell/QML desktop for Hyprland, sway and niri with a Go daemon. `AGENTS.md` is in your context (CLAUDE.md imports it): never read it, nor any file or doc twice. Read the brief (`brief.md` or `contract.md`) first.

**Reading.** Command output goes to a file in the scratch folder you were given; read only the part you need (`grep`, `tail`, `sed -n`). For code that matters, read the enclosing function (`grep -n` its bounds, `sed -n 'a,bp'`), a whole file only under ~150 lines or at the heart of the matter; callers by `grep -rn '<name>' --include='*.qml' --include='*.go' --include='*.py' --include='*.sh' --include='*.json' . | head -30`. Files loaded by name don't show as imports: bar widget and module `type`, `popoutName`, views, `x-card`/`x-intro`, IPC targets, `x-*` annotations, daemon method names (`// rpc:`), `Qt.createComponent` strings. Docs and local `AGENTS.md`: `grep -n '^##'` for the outline, then the one section; a choice that looks odd may be documented there. Never the generated files (`docs/dev/config/`, `docs/dev/generated/`, `config/i18n/`, `config/json/config.schema.json`, `config/themes/template/`): the schema's source is its YAML under `config/schema/`. Tests and `.json` data by grep, never whole. Stop reading once a finding is proven or ruled out.

**What is a finding.** Something provable from the code: the file and line, a concrete scenario (input, state, compositor, sequence) and what goes wrong. No scenario, no finding. Nothing the checks enforce (`scripts/check_all.sh`: format, lint, structure, sizes, i18n keys, docs paths and members, the shell–daemon method names), no "consider adding a test / comment / error handling" without the failure it prevents, no taste, no restating the code. A cleanup shows the simpler version and why it keeps every behaviour. Five proven findings beat twenty maybes; none is a valid answer.

**Proving it.** Before a finding is written, try to refute it: is the path reachable, handled elsewhere, the "dead" code reached by name, the rule actually stated (quote it), does the simpler version keep every behaviour? Then make every fact in it one a command just showed, never one remembered: `sed -n '<n>p'` the cited line (the number is that line's, not the function's), count lines and calls with `wc -l` / `grep -c` and sum a total from its listed parts, and grep `docs/dev/issues.md` and the other findings for the same function or cause (one finding per cause; two fixes to one function are one finding). What only running the shell can settle is marked PLAUSIBLE with what would settle it, and kept only at Major or above. Don't run the shell, IPC that changes state, or anything `AGENTS.md` › Never forbids; reading logs (`scripts/log.sh`), `scripts/run_tests.sh <Name>`, `go test` and the `check_*` scripts are fine. Change no files unless your caller asked for fixes.

**Severity.** Blocker: wrong behaviour users hit, a regression, a failing check, a safety or security rule broken. Major: a bug on a rarer path, a contract or rule broken that no check catches, design that will bite, any added mechanism a smaller change would do (a new state, cache, retry or hold for a rare path), and code a fix leaves behind that nothing needs any more. Cleanup: other dead code, duplication, a simpler shape. Minor: misleading names, comments or docs, small inconsistencies.

**Shape.** Findings go under `## Blockers`, `## Major`, `## Cleanups`, `## Minor`, each in the shape of a `docs/dev/issues.md` entry, so a recorded one is pasted as is (`scripts/check_docs.py` checks paths and `Name.member`s cited, and the field names and order):

```
### <the claim in a few words: it becomes the entry's title and anchor>
- **Where:** `path:line` (`symbol`), and other places the same way
- **What:** the scenario and what happens instead of what should, with the evidence (quoted code, a grep count, a doc line); "PLAUSIBLE: <what settles it>" when it applies. Fix: <the change, code when short; for a deletion, the lines it removes>.
- **Size:** trivial | small | needs a plan   (the bare words, nothing after them)
- **Found:** YYYY-MM-DD, while reviewing <the branch's purpose | the <system> system>
```

After the findings: `## Pre-existing` (problems outside what you were asked to review: a title and `path:line` each) and `## Checked and fine` (risky things you looked at that hold up). An agent ends its reply with its file's path.

## The lead reviewer

- **One helper agent at most** outside deep mode, for a question that needs a lot of reading ("do all 15 callers still work with X's new meaning?"): the exact question and files, "under 300 words, `path:line` evidence, change no files".
- **Deep mode:** reviewer agents (`general-purpose`), all in one message, each given "Every reviewer", its lens or files, the brief's path and its output file. While they run, do what the skill keeps for you. Then merge by root cause and give the findings to verifier agents, about six each grouped by file, told to refute each (`CONFIRMED` / `PLAUSIBLE` / `REFUTED`, with evidence, changing no files). Under ten agents in all.
- **Before the report**, every finding passes "Proving it" again in your own hands: an agent's line number, count or "nothing else does this" is a claim until you've run the command.

## bugs: correctness

Find code that does the wrong thing; trace every changed path with real values.
- Logic: inverted conditions, wrong operator, off-by-one, `==` vs `===` on mixed types, `||` swallowing a valid `0`/`""`/`false`, a `??` hiding a value that should be there, wrong unit (px vs grid, logical vs physical pixels, ms vs s).
- `undefined`/`null`: a property read before its object exists (Loader not loaded, `screen` null while monitors change, a config section in preview), an array assumed non-empty, a monitor or window that went away.
- QML bindings: an assignment that silently breaks a binding, a binding loop, a value read once in `Component.onCompleted` that should be a binding (or the reverse), a null or changing `Connections` target, a handler with the wrong parameter names, `visible`/`opacity`/`enabled` mixed up, implicit vs explicit size fighting, z/layer order; the traps in `docs/dev/core/qml-pitfalls.md`.
- Lifetimes: a delegate destroyed while a Timer, Process or callback still uses it; `acquire` without `release`; a `Process` toggled while running, parsed before it exits, or given an unexpanded `~`; state a hot reload loses that belongs in `PersistentProperties`; handlers that double-connect across reloads.
- The paths nobody takes daily: monitors added, removed, renamed, rescaled, none, several; startup order (a reader or service used before it's ready, a signal fired before its listener exists); each compositor the code runs under (what `supports` says vs what the code assumes); every setting it reads off, empty, at its minimum and maximum; rapid repeats (open/close/open, two requests in flight); the overlay closed mid-animation, a config reload mid-edit; failure (a command missing, a file unreadable, malformed JSON, a socket gone, a daemon call that errors).
- Scripts and Go: quoting, `set -e` traps, non-atomic writes of watched files, paths with spaces, an unchecked missing command, untrusted JSON read without a shape check, an error dropped or a goroutine leaked.
- The claims in the brief: does each fix remove the cause on every path that reaches it, or a symptom one caller over?

## regressions: what used to work

For each changed function, property, signal, schema key, file name or script interface, find everything that relied on the old behaviour.
- Callers and readers of anything renamed, removed, retyped or given a new meaning, including string-built names, aliases, IPC targets, `docs/usage.md`, tests and scripts.
- Other compositors: a change for one must not change the others; logic that should be gated on `CompositorManager.supports.<key>` and isn't, a key read that no backend sets.
- Config: an old config.json still loads and means the same; a reshaped key needs a format-2 step and its Go test (`docs/recipes/migration.md`); a changed default changes existing users' shells; `x-scope` and `x-takeover` still right for what moved.
- Settings off: blur, animations, border off, bars on each edge, vertical bars, no bar, several monitors, one unplugged.
- Performance: a new binding on a hot path (per frame, sample or window), a Repeater model rebuilt from live values, polling that no longer stops, a new window per screen.
- A removed test or weakened assertion: is what it covered still covered?

## cleanup: dead, repeated and over-built code

The code should end smaller and plainer than the first draft that worked.
- Dead: members, imports, ids, files, schema keys, reader members, `supports` keys, script flags, IPC functions, test helpers nothing reaches (grep, and remember what loads by name); leftovers of abandoned attempts (code, comments, debug `console.log`, temporary IPC handlers); code alive but powerless (a condition always false, a parameter every caller passes the same, a property always overwritten before it's read).
- Repeated: the same logic twice, or again where a shared piece does it (`docs/dev/core/shared-ui-pieces.md`, `components/methods/`, `components/reusable/`). A decision a methods helper makes (`SurfaceContext`, `EdgeAttach`, `BarEnds`, `GridPlacement`, `LayerStack`, …) worked out again in a host is also a rules break.
- Simpler shapes: a state machine that is a boolean, a Timer that should be a binding, a wrapper that only forwards, state synced by hand that can be a binding, a special case the general path covers, a generalisation with one user.
- Comments that describe old code or the debugging history, or repeat the next line.

## rules: axiom's rules

Walk `AGENTS.md` and each touched directory's `AGENTS.md` against the code; report a break only with the rule quoted. The checks hold structure, sizes, imports, the Quickshell.Io allowlist, live Repeater models, `duration:` literals, `Quickshell.screens`, `Qt.formatDateTime` and readers' `??`: skip those. Most often broken and unchecked: the layering (UI polling or reading `ConfigManager.config`); the compositor reached past `CompositorManager` or gated on a name, not `supports`; `acquire`/`release` pairing; config written past `ConfigManager`/`SettingsManager` or a preview by mutation; a schema change without default, `x-scope`, migration or test; geometry not from `SurfaceContext`/`EdgeAttach`, a popout that moves, anything over fullscreen; radii, easing, `StyledIcon`, `ClippingRectangle`; `I18n.tr` sentences; `~` unexpanded, writes under `Paths.axiomPath`, secrets past `SecretsManager`, greeter side effects without `Paths.greeter`; a new methods case, migration step or script without its test; a new dependency missing from install.sh, `Packages.packages` or the PKGBUILDs.

## design: does it make sense, and is it described truthfully

- Is each piece in the layer and place the area's docs lead a reader to expect? Does a new abstraction earn its keep, or is an existing one bent to fit?
- Illogical choices: a value computed in one place and corrected in another, a workaround where the cause is fixable, a fix in the consumer for the producer's problem, two sources of truth, a name saying the opposite of what it does, a timing hack (`Qt.callLater` chains, magic delays) standing in for an ordering the code could state.
- Docs: every doc covering the changed files still true, describing the final code; an `issues.md` entry fixed but not removed (or removed unfixed); a user-visible feature missing from `README.md` / `docs/features.md` / `docs/usage.md` where its kind is listed.
- Intent: what the intent implies and the change doesn't do (a compositor left out, a setting not exposed), and changes the intent doesn't explain.
