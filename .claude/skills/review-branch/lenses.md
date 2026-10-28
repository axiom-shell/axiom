# Review lenses

The checklist the lead reviewer walks through in `SKILL.md`, one lens at a time. In `deep` mode each lens is also a reviewer agent's prompt: "Every reviewer" plus one lens.

## Every reviewer

You are reviewing one angle of an axiom branch (a Quickshell/QML desktop shell for Hyprland, sway and niri). `AGENTS.md` is already in your context (CLAUDE.md imports it): don't read it again. Read `brief.md`, then your lens below.

How to work:
- **The diff is where to start; read only what a judgement needs.** For a hunk that changes behaviour, read the enclosing function or component (`grep -n` for its bounds, then `sed -n 'a,bp'`; a whole file only when it's under ~150 lines or is the heart of the change), and grep for its callers (`grep -rn '<name>' --include='*.qml' --include='*.py' --include='*.sh' --include='*.json' . | head -30`). Files loaded by name don't show up as imports: bar widgets (`type`), content (`popoutName`, module `type`), views, settings cards (`x-card`, `x-intro`), IPC targets, schema `x-*` annotations.
- Docs and local `AGENTS.md` files the brief lists: `grep -n '^###'` for the outline, then read only the section about your code. A choice that looks odd may be documented there, and a documented rule may be what the change breaks.
- Stop reading once a finding is proven or ruled out; never re-read a file you already have.
- Only lines the branch adds or changes, or behaviour it changes, are findings. Something already wrong before the branch goes under "Pre-existing" at the end of your file.
- **Every finding must be provable from the code.** Give the file and line, the concrete scenario (state, input, compositor, sequence) and what goes wrong. If you can't name the scenario, it isn't a finding; if it depends on runtime behaviour you can't trace, say what would settle it and mark it `PLAUSIBLE`.
- No style points the tooling already enforces (qmlformat, qmllint, check_structure, check_i18n, check_docs). No "consider adding a comment / test / error handling" without a failure it would prevent. No restating the code.
- Change no files. Don't run the shell, IPC that changes state, or anything `AGENTS.md` › "Never, while testing" forbids. Reading logs (`scripts/log.sh`), running `scripts/run_tests.sh <Name>` and the `check_*` scripts is fine.
- Aim for every real problem in your lens and nothing else. Five proven findings beat twenty maybes; zero is a valid answer when the code is sound.

Write your file in this shape and end your reply with its path:

```
## <n>. <claim in a few words>
- **Where:** `path:line` (and other places)
- **Severity:** blocker | major | cleanup | minor
- **Confidence:** high | medium (PLAUSIBLE: <what would settle it>)
- **Problem:** <what's wrong, the scenario, the evidence (quoted code, grep result, doc line)>
- **Fix:** <the concrete change; code when short>

## Pre-existing
- <title>: `path:line`, <one line>

## Checked and fine
- <risky things you looked at that hold up>
```

## bugs: correctness

Find code that does the wrong thing. Trace every changed path with real values.
- Logic: inverted conditions, wrong operator, off-by-one, `==` vs `===` on mixed types, `||` swallowing a valid `0`/`""`/`false`, a `??` hiding a value that should be there, wrong unit (px vs grid, logical vs physical pixels, ms vs s).
- `undefined`/`null`: a property read before its object exists (Loader not loaded, `screen` null while monitors change, a config section in preview), an array assumed non-empty, a monitor or window that went away.
- QML binding semantics: an assignment that silently breaks a binding, a binding loop, a value read once in `Component.onCompleted` that should be a binding (or the reverse), a `Connections` target that is null or changes, a signal handler with the wrong parameter names, `visible` vs `opacity` vs `enabled` mixed up, implicit vs explicit size fighting, z/layer order.
- Lifetimes: Loader/Repeater delegates destroyed while a Timer, Process or callback still uses them; `acquire` without `release`; a `Process` whose `running` is toggled while running, whose output is parsed before it exits, or whose args contain an unexpanded `~`; state that a hot reload loses and should be in `PersistentProperties`.
- Events and ordering: two signals arriving in the other order, a handler firing during startup with half the config, rapid toggling (open/close/open), monitors added or removed, the overlay closed mid-animation, a config reload mid-edit.
- Scripts: quoting, `set -e` traps, a temp file not written atomically, paths with spaces, a missing command not checked, Python reading untrusted JSON without a shape check.
- The **Claims** in the brief: does each fix actually remove the cause, on every path that reaches it?

## regressions: what used to work

For each changed function, property, signal, schema key, file name or script interface, find everything that depended on its old behaviour and check it still works.
- Callers and readers: grep every use of anything renamed, removed, retyped or given a new meaning, including string-built names, QML property aliases, IPC targets, `docs/usage.md`, tests and scripts.
- Other compositors: a change made for one (the brief says which) must not change Hyprland, sway or niri behaviour it wasn't meant to. Look for logic that should be gated on `CompositorManager.supports.<key>` and isn't, a `supports` key read where none is set, a backend-specific default reaching the others.
- Config: an old config.json must still load and mean the same thing. A key renamed, moved or reshaped needs a version bump, a format-2 step in `backend/internal/migrate/steps/` (idempotent) and its Go test; a changed default changes existing users' shells; `x-scope` and `x-takeover` must still be right for anything moved.
- Settings off: features disabled (blur off, animations off, border off, a bar on each edge, vertical bars, no bar, several monitors, a monitor unplugged) must behave as before.
- Performance: a new binding on a hot path (per frame, per sample, per window), a Repeater model rebuilt from live values, polling that no longer stops, a new layer or window per screen.
- Removed tests or weakened assertions: why, and is what they covered still covered?

## cleanup: dead, repeated and over-built code

The branch should leave the code smaller and plainer than the first draft that worked.
- Dead code: properties, functions, signals, imports, ids, files, schema keys, reader members, CSS-like style props, `supports` keys, script flags or test helpers that nothing uses after this branch (grep, and remember name-loaded files). **Leftovers of attempts that were tried and abandoned** (the brief's `issues.md` entries and commit messages say what was tried): code, comments, debug `console.log`, temporary IPC handlers, flags that only one branch of now reaches.
- Repetition: the same logic written twice in the branch, or written again when a shared piece already does it (`docs/dev/core/shared-ui-pieces.md`, `components/methods/`, `components/reusable/`). A decision a methods helper makes (`SurfaceContext`, `EdgeAttach`, `BarEnds`, `GridPlacement`, `LayerStack`, …) worked out again in a host is both a repeat and a rule break.
- Simpler shapes: a condition that can be one expression, a state machine that is a boolean, a Timer that should be a binding, a wrapper Item that only forwards, a property kept in sync by hand that can be a binding, a parameter every caller passes the same, a special case that the general path already handles, a generalisation with one user.
- Comments: ones that describe what the code used to do, narrate the debugging history, or say what the next line plainly says. Match the surrounding comment density.
- For every cleanup, show the simpler version and say why it keeps every behaviour. Don't propose churn that is only taste.

## rules: axiom's rules and architecture

Check the changed code against `AGENTS.md`, the local `AGENTS.md` of each touched directory, and the docs the brief lists. Report a break only when you can quote the rule. The ones the checks don't enforce, and that changes most often break:
- Layering: methods pure (no files, processes, `qs.*`); readers read only owners and each other, with no `??` default fallbacks; services own every side effect; UI runs no polling Process or repeating Timer and never reads `ConfigManager.config` directly.
- The compositor only through `CompositorManager` (neutral shapes; `goToWorkspace`/`focusWindow`, never a direct dispatch); only the backend talks to its compositor; gate on `supports.<key>`, never on a compositor's name; nothing writes compositor config unless `supports.configModes`.
- Polled data through `acquire`/`release`, requests from config only; Repeater models and requests never from live values.
- Config writes only through `ConfigManager`/`SettingsManager`; editors through a `ConfigDraft` and the manager's `select*()`; unsaved edits show through `ConfigManager.setPreview`, never by changing `config`; readers read `ConfigManager.live`.
- Schema: a new setting has a `default`, title, description, the right `x-scope`; a layout change has version bump + migration + test, schema edited first; module `x-hosts` lists overlay, edgeMenu and desktop, lockscreen/greeter only when safe.
- Geometry and popouts: from `SurfaceContext`/`EdgeAttach` only, collisions through `PopoutClaim`, an open popout never moves, shadows through `OutsideShadow`, layer order only from `LayerStack.layers`, bars and border never over fullscreen, nothing maps a Top window in response to fullscreen.
- UI: `Appearance.anim*` durations with `Appearance.easing` (`Glide`/`ColorGlide`), looping animations gated on `Appearance.animations`; `Appearance.borderRadius` only for outer edges, `Widget.radius` inside; rounded clipping by `ClippingRectangle` with `color` set; icons through `StyledIcon`, never sharing a Text with a label; screens from `General.screensFor`/`General.outputs`, never `Quickshell.screens`; IPC handlers enabled on the target instance only; reuse of shared pieces.
- Text: `I18n.tr("…")` with placeholders, never template-string sentences; dates through `I18n.formatDate`; logs and migration notes English; agents never fill translations.
- Files: nothing written under `Paths.axiomPath`; watched files written atomically; secrets only through `SecretsManager`; paths with `~` expanded before a process or read; greeter-reachable side effects check `Paths.greeter`; lock only through `LockManager.lock()`, unlock only by PAM.
- Naming: services `*Manager`, no shadowing Quickshell singletons, `Styled*` stand-ins, root id `root`, `Window` suffix rule, purpose comment above each root object, `// reads:` comments for config reads grep can't see.
- Tests: a changed methods helper or migration step has a new test case; a new script's test class is in verify.sh's `script_tests`; a new dependency is in install.sh, `Packages.packages` and the PKGBUILDs.
- The traps in `docs/dev/core/qml-pitfalls.md` (StyledTextEntry write-back, object literal without parentheses, assigning a bound property, redeclared base property, `visibleChildren` self-hide, `Item`-typed params read for custom members, inline component using another in a URL-loaded file, MultiEffect on own layer).

## design: does it make sense, and is it described truthfully

Step back from the lines and judge the choices.
- Is each piece in the right place and layer? Would the maintainer, reading the docs for this area, expect it there? Is a new abstraction earning its keep, or is an existing one being bent to fit?
- Illogical choices: a value computed in one place and corrected in another, a workaround where the cause is reachable and fixable, a fix in the consumer for a problem in the producer, two sources of truth for one fact, a flag whose name says the opposite of what it does, a timing hack (`Qt.callLater` chains, magic delays) standing in for an ordering the code could state.
- Names: does every new name say what the thing is or does, in the vocabulary the docs use?
- Docs: every doc the brief lists must still be true after the branch. A changed mechanism with an unchanged doc, a doc describing the first attempt rather than the final code, an `issues.md` entry that the branch fixes but doesn't remove (or removes without fixing), a new user-visible feature missing from `README.md` / `docs/features.md` / `docs/usage.md` where its kind is listed.
- Intent: anything the brief's intent implies that the branch doesn't do (a compositor left out, a setting not exposed, a case not handled), and anything the branch does that its intent doesn't explain (unrelated changes riding along).
