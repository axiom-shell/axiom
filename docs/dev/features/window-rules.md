# Window rules

> **Files:** `backend/internal/windowrules/`, `backend/internal/procinfo/`, `backend/internal/compositor/windows/`, `backend/internal/compositor/render/windowrules.go`, `qml/config/schema/sections/WindowRules.yaml`, `qml/config/schema/definitions/common/WindowRule.yaml`, `qml/config/schema/definitions/common/WindowRuleCondition.yaml`, `qml/config/schema/definitions/shared/WindowRuleWhen.yaml`, `tests/fixtures/windowrules/regex.json`, `qml/components/views/WindowRules/{WindowRules,RulesPanel,RuleInspector,KindBlock}.qml`, `qml/services/compositor/{WindowRulesManager,WindowRulesEditor}.qml`, `qml/components/methods/WindowRuleIssues.qml`
> **Config:** `WindowRules.*` (no reader: the page edits a `ConfigDraft`; the daemon reads the rest)
> **Related:** [Config modes](../compositor/config-modes.md), [Keybinds](../hyprland/keybinds.md), [Schema annotations](../core/schema-annotations.md), [Saved configs and sharing](../core/saved-configs-sharing.md)

The user's window rules: the model, its validation, the renderers that compile it, the writers that put the rules in each compositor's config, and the Window rules page that edits them.

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

### Processes and games
- `procinfo.Reader.Lookup` gives a window's process name (`comm`, with the kernel's 15-byte cut undone), the names of the processes above it and its game signals. It reads only the user's own processes, cached by pid and start time; the facts are taken at the first lookup and kept.
- Only process names and signal names leave the package; argument and environment values never do: environment and command line are scanned for a fixed list of names and dropped. A non-dumpable process reads as not ours.
- The signals and where each looks (the window's process, the processes above it, its environment) are the table in `procinfo/game.go`. Steam counts through what it launches (`reaper SteamLaunch` or a Steam game id), so Steam's own windows are not games. Lutris and Heroic count only through what runs the game (`lutris-wrapper`, `legendary`, `gogdl`, `nile`, or `LUTRIS_GAME_UUID` / `HEROIC_APP_NAME` in the environment), not their UI process. Wine and gamescope count only together with a launcher signal (Steam, Proton, Lutris, Heroic, umu): a bare `wine notepad` is not a game.
- An X11 bridge (`xwayland-satellite`, `Xwayland`) stands for many windows, so its windows have no process facts: on niri, X11 games are recognised only by their `steam_app_N` app id. `procinfo.Detect` adds that app id signal.

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

### The page
- The Window rules tool page (`needs: configModes`: rules reach the compositor only through the config writer) has the rules as a list, dragged to order (list order is priority), and beside it the selected rule: its name, icon and switch, its kinds of window and their conditions, its "When it opens" effects, and its problems. A condition is one compact row (field, test, value); the test's options and the value box follow the schema (`x-enumShowIf`, `x-showIf`).
- Edits are a `ConfigDraft` of `WindowRules` in `WindowRulesManager.editor`, saved like every editor. Problems come from Go only: the draft's from `compositor.checkRules` (300 ms after the last edit, on load and when the compositor's abilities change; only the latest answer is kept) while the draft differs from what's saved, else `compositor.state`'s `windowRules` (`WindowRulesManager.savedReport`, what the compositor actually has). A rule with problems still saves; it isn't applied.
- Right after a save the page shows the previous saved report until the daemon pushes the new state, and a dirty draft shows the saved report until its first check answers; a failed check keeps the last report.
- No preview: unsaved rules never reach the compositor (`WindowRules` stays out of `CompositorConfigManager._layerSections`).
- Effects the compositor can't do are greyed by `x-enabledIf` on the same capabilities `ruleGates` drops them for (a Go test keeps the two in step), with `CompositorManager.unsupportedNote` saying why; a greyed value is kept. A numbered workspace on niri, a special workspace on sway and kinds with live conditions are shown as "applied just after the window opens".
- The conditions offered are `WindowRulesEditor.offeredFields`: app id, title, XWayland and Steam game. A rule already holding another field shows it.
- An issue's text is its English `message` through `I18n.tr` with `args` filled in (a field id as its label): `WindowRulesEditor.issueText`, which lists every message of `validate.go` for the translations (a Go test keeps the list complete).

### Watching windows
- `compositor/windows` reports the compositor's windows as `Event`s (`reset`, `opened`, `changed`, `closed`; `Window` has id, app id, X11 class, title, pid, XWayland, workspace, output, floating, fullscreen, focused) for Hyprland, sway and niri. Nothing starts it yet; the engine will.
- **Reset vs Opened**: the first full list after each (re)connect is one `Reset`, never `Opened`: only a window that appears after it is `Opened`. Windows already open are touched only on "Apply to open windows", and the while-effects are rebuilt from the `Reset` after a daemon restart.
- **A batch, then a diff**: the run loop reads every event that is ready, the backend applies them to its table (at most one refetch of each kind), and the watcher emits the difference: `Closed`, `Changed` (only when a field differs), then `Opened`. A burst costs one refetch, and a window that opens and closes inside one batch emits nothing.
- **What refetches**: Hyprland applies `windowtitlev2`, `activewindowv2` and `closewindow` from the payload and refetches `j/clients` (and `j/monitors` for a monitor event or an unknown monitor id) on `openwindow`, `movewindowv2`, `changefloatingmode`, `fullscreen`, `moveworkspacev2`, `renameworkspace` and `configreloaded`; sway refetches `get_tree` on window `new`/`move` and workspace `move`/`rename`/`reload` and updates the rest from the event's container; niri's stream is the whole state (only `Outputs` is requested, for the logical sizes). The watcher connects again after a drop with a fresh `Reset`.
- **Fields**: Hyprland ids keep their `0x` (socket2 leaves it off, the watcher adds it); focus comes from `activewindowv2`, never `focusHistoryID`. niri has no XWayland flag (`xwayland` is false; an X11 window shows as its class) and no fullscreen field: a tiled window as big as its output's logical size (within 1 px) is fullscreen. sway's scratchpad windows have no workspace or output.
- **Fixtures**: `compositor/windows/testdata/<kind>.json` are sessions recorded in nested Hyprland, sway and niri, replayed on the fetch seam; `<kind>.want.json` are the expected events (`go test -run TestFixtures -update`). To re-record, run the same script nested: open window A, then open B (its title changes), float it, fullscreen it and leave, move it to workspace 2, open an X11 window, focus A, close the X11 window then B, saving each step's events and the replies a refetch would get.

The "While it's open, focused or fullscreen" effects, the engine that matches windows and places what a config can't, applying to open windows, the pickers and the built-in switches come with the rest of the window rules work.
