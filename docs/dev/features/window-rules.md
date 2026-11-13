# Window rules

> **Files:** `backend/internal/windowrules/`, `qml/config/schema/sections/WindowRules.yaml`, `qml/config/schema/definitions/common/WindowRule.yaml`, `qml/config/schema/definitions/common/WindowRuleCondition.yaml`, `qml/config/schema/definitions/shared/WindowRuleWhen.yaml`, `tests/fixtures/windowrules/regex.json`
> **Config:** `WindowRules.*` (no reader yet: only the daemon's package reads it)
> **Related:** [Config modes](../compositor/config-modes.md), [Keybinds](../hyprland/keybinds.md), [Schema annotations](../core/schema-annotations.md), [Saved configs and sharing](../core/saved-configs-sharing.md)

The user's window rules: what exists is the model and its validation; nothing reads the section at runtime yet.

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

The writers, the engine and the page come with the rest of the window rules work.
