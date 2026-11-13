# Window rules

> **Files:** `backend/internal/windowrules/`, `backend/internal/compositor/render/windowrules.go`, `qml/config/schema/sections/WindowRules.yaml`, `qml/config/schema/definitions/common/WindowRule.yaml`, `qml/config/schema/definitions/common/WindowRuleCondition.yaml`, `qml/config/schema/definitions/shared/WindowRuleWhen.yaml`, `tests/fixtures/windowrules/regex.json`
> **Config:** `WindowRules.*` (no reader yet: only the daemon's package reads it)
> **Related:** [Config modes](../compositor/config-modes.md), [Keybinds](../hyprland/keybinds.md), [Schema annotations](../core/schema-annotations.md), [Saved configs and sharing](../core/saved-configs-sharing.md)

The user's window rules: what exists is the model, its validation and the renderers that compile it; nothing reads the section at runtime yet.

### The model
- `WindowRules.rules` is an id'd list whose order is the priority: the higher a rule, the more it counts when two set the same thing. `Parse` turns the section into `Config`.
- A rule's `windows` are kinds of window (any kind matches); a kind's conditions are `{field, op, value}` and every one must hold.
- `window` is what the compositor's config does when the window opens (float, size, workspace, ...); `shell` is axiom's own effects (do not disturb, keep awake, power profile, hide from, pause shortcuts, pause OSDs, hide the bar). Each shell effect has its own `enabled` switch, so a configured list survives turning it off, and its own `when` (open, focused or fullscreen). `when` defaults to open, except pause shortcuts, pause OSDs and hide the bar, which default to focused.
- `WindowRules.switches` are built-in rules, all off by default and ranked below the user's: float Steam's small windows, and send games to a special workspace (`games`, shown, until changed).
- A rule sent to a workspace has a `follow` switch ("Go there too", off): off, the window opens there and you stay put; on, you switch to it, like the special workspace's shown or silent switch.
- An unset effect is its zero value (`false`, `''`, `0`; size 0 is "as it opens", opacity 0 is "unchanged"): every key is always filled, never null. Defaults come from the schema (a rule's `enabled` defaults to true); `Parse` expects the section after defaults are filled and reads a missing key as its zero value.
- `window.monitor` carries `x-scope: machine` itself, because a scope condition sees only an item's own keys: a shared rule travels without its monitor.

### Kinds: written or live
- Some fields only the daemon can test: `process`, `startedFrom` and `game` are live (`Field.Live`). A kind with one live condition is live, so no compositor config can match it; `Rule.CompiledKinds` and `Rule.LiveKinds` split a rule's kinds, in order.
- `steamGame` lowers to the app id `steam_app_<N>` and `app` (a desktop entry id) to the app ids a resolver gives, so neither is live. `Lower` gives a kind as tests, flags and the live bit.

### Patterns
- A condition's value becomes one of three anchored forms: the literal (`is`, `isNot`), the literal inside `(?s:.*)` on both sides (`contains`), or the user's own pattern inside the same (`matches`).
- A user's pattern is re-printed through `regexp/syntax` (`Normalise`) so every compositor's engine (RE2, Rust regex, PCRE2) reads it the same way. Four constructs are refused (`(?m)`, `\Q…\E`, `\p`, `\b`), capture groups are dropped (their names and numbers would clash when patterns are joined), `$` prints as `\z` and `\v` as `\x0b`.
- Several `isNot` conditions on one field merge into one negated alternation.
- `tests/fixtures/windowrules/regex.json` pins the printed forms and what they match; a Go upgrade that prints differently fails its test.

### Validation
- `Validate` lists every rule's issues, enabled or not, then the switches'. A bad rule still saves and carries issues; `Usable` returns the enabled rules with none (a repeated id drops all its rules), the ones to write and match.
- An issue's `message` is an English template with `{0}` placeholders that `args` fill, so the page can translate it; a field in `args` is its raw id.
- The codes and their checks are in `validate.go`.

### Writing
- The daemon compiles the usable rules once per config change (`windowRules` in `buildInputs`) and each writer puts them where its compositor's rules go: the module, the managed config, niri's detached module, or the runtime (Hyprland's `AXIOM_RULES`, sway's `for_window`). Who wins per mode, the managed split on niri, and the runtime layers: [config modes](../compositor/config-modes.md), [Hyprland](../hyprland/config-modes.md), [niri](../compositor/niri-backend.md), [sway](../compositor/sway-backend.md).
- `compositor.state`'s `windowRules` reports the issues and, per usable rule, what the config applies, what the daemon will place after open, what's dropped; `compositor.checkRules` checks an unsaved draft the same way (unsaved rules never reach the compositor).

### Compiling
- `HyprRuleLines`, `NiriRuleNodes` and `SwayRuleLines` (`render/windowrules.go`) take a `RuleSet` (the usable rules, the app id resolver, the backend's `supports`) and give the rules in Hyprland Lua, niri KDL and sway config lines, plus an `Unwritten` per rule with something left out. One compile step decides which kinds and effects are written, from the capabilities (never the compositor's name); the printers only print.
- Rules are written lowest priority first: every compositor lets the later rule win for the same property, so the higher rule in the list lands last.
- Effects: the table in `windowrules.go` has the full lists. `ruleMaximize`, `ruleTearing`, `ruleNoScreenShare` and `ruleXwayland` are the new capabilities; `pin`, `namedSpecial`, `windowOpacity` and `windowBlur` gate their effects too. An effect without its capability is dropped and reported. Center is written by Hyprland and sway; niri writes nothing (it opens a new floating window at the center already).
- A workspace move is silent (the window opens there and you stay put) unless the rule's `follow` is on: Hyprland drops `silent`, sway adds a `workspace` command. niri's `open-on-workspace` has no following form. Hyprland writes `name:<name>` for every non-numeric workspace, so "-1" is a name, not a relative selector.
- Negation: niri `exclude` (a kind with a negation gets its own block); Hyprland `negative:<re>`, on `initial_class` or `initial_title` when the field also has a positive test; sway a PCRE2 lookahead in the one criterion.
- sway's `app_id` matches only Wayland windows and `class` only X11 ones, so an app id test is written on both unless an xwayland condition picks one.
- Quoting: Lua and KDL strings escape a pattern natively. sway unescapes a config file C-style before reading criteria and expands `$name`, so `SwayCriterion` writes `\x22` for a quote and `\x24` for a `$`, and a file doubles every backslash on top. Over IPC (`runtime`) each `for_window` command chain goes through `SwayBindCommand`, because an unquoted chain is split at its commas; a file's stays bare. `RuleEffects` lists the effects a rule sets.
- Left to the daemon, reported in `Unwritten`: live kinds (`Live`) and a numbered workspace on niri or a special workspace on sway (`Placed`: sway's named specials are a per-window mark a `for_window` can't write). A kind no config can match (XWayland on niri, an app with no app ids) is `Skipped`.
- niri's `open-on-workspace` names a workspace niri's own config declares. sway's look sets every window's opacity and blur as focus moves, which overrides a rule's opacity and No blur while the look sets them.

The editor, the engine and the placement of what a config can't do come with the rest of the window rules work.
