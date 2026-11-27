# Review lenses

What a reviewer agent reads besides its brief: "Every reviewer", then the lens sections its brief names. `review-branch` uses the six lenses here, over slices of a diff (`bugs`, `regressions`) and over the whole branch (the rest).

## Every reviewer

You review a slice of axiom, a Quickshell/QML desktop for Hyprland, sway and niri with a Go daemon. `CLAUDE.md` is already in your context: don't read it again, nor any file twice.

**Reading.** For code that matters, read the enclosing function (`grep -n` its bounds, `sed -n 'a,bp'`), a whole file only under ~150 lines or at the heart of the matter; callers by `grep -rn '<name>' --include='*.qml' --include='*.go' --include='*.py' --include='*.sh' --include='*.json' . | head -30`. Files loaded by name don't show as imports: bar widget and module `type`, `popoutName`, views, `x-card`/`x-intro`, IPC targets, `x-*` annotations, daemon method names (`// rpc:`), `Qt.createComponent` strings. Docs and `.claude/rules/` files: `grep -n '^##'` for the outline, then the one section; a choice that looks odd may be documented there. Never the generated files (`docs/dev/config/`, `docs/dev/generated/`, `qml/config/i18n/`, `qml/config/json/config.schema.json`, `qml/config/themes/template/`): the schema's source is its YAML under `qml/config/schema/`. Tests and `.json` data by grep, never whole. Stop reading once a finding is proven or ruled out.

**What is a finding.** Something provable from the code: the file and line, a concrete case (input, state, compositor, sequence) and what goes wrong. No case, no finding. In a branch, only what it adds or changes is a finding; what was wrong before goes under "Outside the slice". Nothing the checks enforce (`scripts/check_all.sh`: format, lint, structure, sizes, i18n keys, docs paths and members, the shell–daemon method names), no "consider adding a test / comment / error handling" without the failure it prevents, no taste, no restating the code. Inconsistency with a precedent you cite (`path:line`) is not taste: alignment with the codebase is axiom's top priority. A cleanup shows the simpler version and why it keeps every behaviour. Five proven findings beat twenty maybes; none is a valid answer.

**Proving it.** Before a finding goes in, try to refute it: is the path reachable, handled elsewhere, the "dead" code reached by name, the rule actually stated (quote it), does the simpler version keep every behaviour? Every fact in it is one a command just showed, never one remembered: `sed -n '<n>p'` the cited line (the number is that line's, not the function's), count lines and calls with `wc -l` / `grep -c`, and one finding per cause (two fixes to one function are one finding). What only running the shell can settle is marked PLAUSIBLE with what would settle it, and kept only at Major or above. Read-only: no running the shell, no IPC that changes state; `scripts/log.sh`, `scripts/run_tests.sh <Name>`, `go test` and the `check_*` scripts are fine.

**Severity.** Blocker: wrong behaviour users hit, a regression, a failing check, a safety or security rule broken. Major: a bug on a rarer path, a rule broken that no check catches, design that will bite, an added mechanism a smaller change would do (a new state, cache, retry or hold for a rare path), code a fix leaves behind that nothing needs any more, and every misalignment: code that repeats an existing piece or another part of the branch, a second name or unit for a concept that has one, one job done two ways, a new file or edit site that doesn't follow the precedent of its kind. Cleanup: other dead code, a simpler shape. Minor: misleading names, comments or docs, small inconsistencies.

**Reply.** `.claude/templates/finding.md`.

## bugs: correctness

Find code that does the wrong thing; trace every changed path with real values.
- Logic: inverted conditions, wrong operator, off-by-one, `==` vs `===` on mixed types, `||` swallowing a valid `0`/`""`/`false`, a `??` hiding a value that should be there, wrong unit (px vs grid, logical vs physical pixels, ms vs s).
- `undefined`/`null`: a property read before its object exists (Loader not loaded, `screen` null while monitors change, a config section in preview), an array assumed non-empty, a monitor or window that went away.
- QML bindings: an assignment that silently breaks a binding, a binding loop, a value read once in `Component.onCompleted` that should be a binding (or the reverse), a null or changing `Connections` target, a handler with the wrong parameter names, `visible`/`opacity`/`enabled` mixed up, implicit vs explicit size fighting, z/layer order; the traps in `docs/dev/core/qml-pitfalls.md`.
- Lifetimes: a delegate destroyed while a Timer, Process or callback still uses it; `acquire` without `release`; a `Process` toggled while running, parsed before it exits, or given an unexpanded `~`; state a hot reload loses that belongs in `PersistentProperties`; handlers that double-connect across reloads.
- The paths nobody takes daily: monitors added, removed, renamed, rescaled, none, several; startup order (a reader or service used before it's ready, a signal fired before its listener exists); each compositor the code runs under (what `supports` says vs what the code assumes); every setting it reads off, empty, at its minimum and maximum; rapid repeats (open/close/open, two requests in flight); the overlay closed mid-animation, a config reload mid-edit; failure (a command missing, a file unreadable, malformed JSON, a socket gone, a daemon call that errors).
- Scripts and Go: quoting, `set -e` traps, non-atomic writes of watched files, paths with spaces, an unchecked missing command, untrusted JSON read without a shape check, an error dropped or a goroutine leaked.
- The branch's claims: does each fix remove the cause on every path that reaches it, or a symptom one caller over? A "fix" that doesn't fix is the most valuable finding there is.

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
- Repeated: the same logic twice, or again where a shared piece does it (`docs/dev/core/shared-ui-pieces.md`, `qml/components/methods/`, `qml/components/reusable/`). A decision a methods helper makes (`SurfaceContext`, `EdgeAttach`, `BarEnds`, `GridPlacement`, `LayerStack`, …) worked out again in a host is also a rules break.
- Simpler shapes: a state machine that is a boolean, a Timer that should be a binding, a wrapper that only forwards, state synced by hand that can be a binding, a special case the general path covers, a generalisation with one user.
- Comments that describe old code or the debugging history, or repeat the next line.

## rules: axiom's rules

Walk the rules in `CLAUDE.md`, the area's rules file against the code; report a break only with the rule quoted. The checks hold structure, sizes, imports, the Quickshell.Io allowlist, live Repeater models, `Quickshell.screens`, `Qt.formatDateTime` and readers' `??`: skip those. Most often broken and unchecked: the layering (UI polling or reading `ConfigManager.config`); the compositor reached past `CompositorManager` or gated on a name, not `supports`; `acquire`/`release` pairing; config written past `ConfigManager`/`SettingsManager` or a preview by mutation; a schema change without default, `x-scope`, migration or test; geometry not from `SurfaceContext`/`EdgeAttach`, a popout that moves, anything over fullscreen; radii, easing, `StyledIcon`, `ClippingRectangle`; `I18n.tr` sentences; `~` unexpanded, writes under `Paths.treePath`, secrets past `SecretsManager`, greeter side effects without `Paths.greeter`; a new methods case, migration step or script without its test; a new dependency missing from install.sh, `Packages.packages` or the PKGBUILDs.

## design: does it make sense

- Is each piece in the layer and place the area's docs lead a reader to expect? Does a new abstraction earn its keep, or is an existing one bent to fit?
- Illogical choices: a value computed in one place and corrected in another, a workaround where the cause is fixable, a fix in the consumer for the producer's problem, two sources of truth, a name saying the opposite of what it does, a timing hack (`Qt.callLater` chains, magic delays) standing in for an ordering the code could state.
- Intent: what the branch's purpose implies and the change doesn't do (a compositor left out, a setting not exposed), and changes the purpose doesn't explain.

## consistency: one way, one name, the codebase's way

The whole branch, never a slice: what one slice can't see is the point. Start from `python3 scripts/dev/new_names.py --base <mb>` (every name the branch adds, and where else that name is defined) and the ledger if the brief names one; read code only to settle a candidate.
- Duplicates: for each new function, property, component and test helper, does the codebase or another part of the branch already do that job? Search `.claude/templates/ledger.md` › Where to search. A block of three or more lines written twice across files is a duplicate.
- Names: one concept, one name in every file; one name, one meaning (the `also defined` column shows clashes); a family of readers or helpers doing one job under different names, result shapes or argument orders; a member whose unit differs from its siblings' (factor vs %, px vs grid cells) or from the name's other uses.
- Patterns: every site of one kind (a config write, a call into a helper, a form hook, a wrapper) written the same way; each new file mirrors the precedent of its kind (member order, comment style, test layout).
- Decisions: a helper's decision worked out again in a host or the UI (`CLAUDE.md` › Layering).
- Wrong reuse: a reused piece run in a mode or with flags (`submenu: true`, a different host) that changes behaviour from what the purpose names; "X becomes Y" built from a third piece instead of X's own. No duplicate exists, so name the behaviour lost, with both call sites.
- Schema: a field definition written out again instead of referenced and overridden; a new key named unlike its siblings.
- User strings and docs: one wording per message (grep the existing `I18n.tr` strings); every UI label a description or doc names exists in the QML; one home per fact, linked from the others.
- Ledger: every added public name is in it, with the same name and unit; every ledger entry is built.

Every finding here is Major, except wording in comments (Minor). Each names both locations and which one is the precedent the other should follow.

