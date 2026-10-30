# Keybinds (actions and the Keybinds page)

> **Files:** `services/compositor/KeybindManager.qml` (the reader), `services/compositor/KeybindEditor.qml` (`KeybindManager.editor`), `services/compositor/KeybindsPageState.qml` (`KeybindManager.page`), `config/KeybindsConfig.qml`, `backend/internal/compositor/actions/table.json` (what each action is, its argument kinds; the shell gets it from `compositor.bindActions` as `KeybindManager.actionTable`), `components/methods/BindActions.qml` (its functions, the table handed in), `backend/internal/compositor/render/hyprconfig.go` (`bindLua`, `dispatcherLua`), `services/compositor/CompositorConfigManager.qml`, `backend/internal/compositor/manager/hypr.go`, `components/views/Keybinds/Keybinds.qml`, `components/views/Keybinds/` (`BindEditor`, `BindSection`, `BindListRow`, `BindInspector`, `KeyMapPanel`, `PresetSheet`, `KeyRecorder`, `FilterChips`), `components/methods/KeyNames.qml`, `components/methods/KeybindFilter.qml`, `components/methods/BindKeys.qml`, `components/methods/BindGroups.qml`, `components/methods/KeyMap.qml`, `components/methods/BindRows.qml`, `components/content/parts/KeybindSection.qml`, `components/content/parts/KeybindRow.qml`, `components/content/parts/KeyboardMap.qml`, `components/content/parts/KeyboardReference.qml`
> **Config:** `Keybinds.binds`, `Keybinds.presets`, `Apps.terminal`/`fileManager`/`browser`
> **Related:** [Bind merge](bind-merge.md), [Config modes](config-modes.md), [Window switcher](window-switcher.md), [Screenshots and recording](../features/screenshots-recording.md), [Workspace strips](workspace-strips.md)

What a bind can do, and how the Keybinds page lists the compositor's binds and edits axiom's own. The binds are compositor-neutral (`Keybinds.binds`, `Hyprland.binds` before config version 60); each backend's config writer turns them into its own binds (on Hyprland, `render.bindLua`).

### Bind actions
- `binds` are edited on the Keybinds page, not in settings.
- An action is one of:
  - **An axiom IPC call** (the table's `ipcActions`). This includes the `audio`/`media` targets on AudioManager/MediaManager, so the OSD shows.
  - **A compositor action bound directly** (the table's `compositorActions`; on Hyprland its Lua in `render.dispatcherLua`):
    - focus/move/resize, close, fullscreen, floating, pin, special workspaces
    - mouse drag/resize on a `mouse:272` key (Hyprland makes that a mouse bind by itself)
    - the window switcher's `windowSwitcher`/`windowSwitcherReverse`, Lua functions that enter its submap ([Window switcher](window-switcher.md))
    - `exitSession`
    - `pseudo` and `toggleSplit`
    - `raw`: a command in the compositor's own language, for the compositor its `compositor` field names (bound nowhere else). On Hyprland, any dispatcher as Lua, compiled with `load` when the bind is made, so a mistake leaves only that bind a `no_op`
    - `terminal`/`fileManager`/`browser`: exec `Apps.terminalCommand` etc., so the binds follow the `Apps` section's `terminal`/`fileManager`/`browser` (empty is the system default)
    - `mediaStop` etc. on `media`.
  - **`scrollStep`** (`workspaces scroll`, the default SUPER + scroll): along the focused output's strip where it has one (`CompositorManager.stepStrip`, focus follows), else a workspace step that way (`stepWorkspace`).
  - **`screenshot`** (argument `region`/`window`/`screen`) and **`screenRecord`**, which go to ScreenshotManager ([Screenshots and recording](../features/screenshots-recording.md)).
- Binds carry `repeating`/`locked`/`release` flags, preset from the table's `actionFlags` when the action is picked.
- **Paused binds** (`paused`) stay in `Keybinds.binds` but aren't bound: every writer and runtime layer reads `KeybindsConfig.activeBinds`, which leaves them out (so does the window switcher's held modifiers). In the editor a paused bind holds no key: it clashes with nothing, isn't a user conflict, and its only issue is an `info` note. `setPaused(indices, on)` pauses one bind, a run or a whole section.
- **A modifier on its own** (a tap): the key is the modifier's keysym alone, `Super_L` (`KeyNames.tapModifier`; `SUPER + Super_L` reads the same). It fires when the key is let go with no other key between, `release` or not, and needs `modifierTap` (`BindActions.keySupported`; niri can't, so it gets a warning and isn't written). Hyprland binds it as `SUPER + Super_L` on release (`render.bindKey`), sway as `bindsym --release Super_L`. `BindKeys.keyId` leaves a tap's own modifier out of its id, as Hyprland lists the modifier held and sway doesn't.
- **What a compositor can do**: The table's `needs` lists the capabilities an action needs (any one of them), e.g. `strip*` → `strips`, `toggleSpecial` → `namedSpecial` or `scratchpad`. The picker (`KeybindManager.actionInfo`) offers only the actions the running compositor supports; a saved bind with another keeps it and gets a warning in `issues` (`BindActions.appliesUnder`), as does a `raw` bind written for another compositor. An action the compositor does itself and can't be bound to (`CompositorManager.builtInBinds`: niri's Mod + left/right drag) gets an `info` note instead when the bind is on that combo, or a warning naming the combo when it isn't; `info` notes don't count as issues (`hasIssue`, `issueCount`). Binds the layout leaves idle get an `info` note too: `strip*` with no strip anywhere (the strip binds are in the defaults for every layout), and on Hyprland `toggleSplit` (dwindle's) on the scrolling layout.

### What the page lists
- Streamed in as the page opens (`StreamedLoader`, [streamed building](../core/streamed-building.md)): the header's filter chips, each bind section (keyed by count, `KeybindFilter.columns`), and the presets popup (`PresetSheet`, a `Popup` in a loader covering the list). The keyboard reference and the editing inspector (the bind or the key map) are built only in their modes. `KeybindManager.editor.ensureLoaded()` keeps a draft that's current (`ConfigDraft.loadIfStale`).
- Every bind the compositor reports (`CompositorManager.withBinds`, needs `bindMerge`), grouped by "Section: Label" descriptions.
- Axiom's own `Keybinds.binds` are edited in a `ConfigDraft` and saved with `save()`. Every bind needs an `id` unique in the list (the schema's `ItemId`), but added, duplicated, merged and preset binds come without one or with a copy of another's: `save()` and `savePreset` run them through `BindKeys.withIds` first, which keeps a valid id not taken earlier and names the rest from the key (`super-y`, `super-y-2`), as the config conversion does.
- Per-bind `issues`:
  - no key, a bad modifier, a missing argument, a duplicate
  - a key the user's own config binds. This is Hyprland's binds minus the saved axiom binds it applied, since every Lua bind shows up as an opaque `__lua` dispatcher.
- Each row carries `axiom`/`user`:
  - `axiom`: any of its binds is one of axiom's applied binds (`_axiomIds`, by `BindKeys.keyId`, never in a submap)
  - `user`: it is the user's own.
- Each row also carries `ids` (its keys' `BindKeys.keyId`s), `action` (its first axiom bind's, for the icon) and `overrides` (the label of an axiom bind skipped because this user bind holds its key, `_skippedLabels`).
- `methods/BindRows` folds rows: numbered runs (`collapseNumbered`, "Go to workspace 1–9") and direction sets (`collapseDirections`, "Focus left/down/up/right" with the same modifiers become "Focus" with a `cluster` per alternative, H J K L). Key names are shortened through `KeyMap.labelOf` (the key map's labels: `[`, `Vol +`).

### The reference (All binds, Keyboard)
- **All binds**: the sections in masonry columns (`KeybindFilter.columns`), each a `content/parts/KeybindSection`: its icon (`sectionIcon`), then its rows grouped by their first combo's modifiers (`BindRows.byModifiers`) under a header that folds the group (`refFolded`, `toggleRefFold`, by `refGroupKey`). Rows (`KeybindRow`) are keys first, in one column as wide as the section's widest, then the action's icon (a person for the user's own binds), the label eliding at the card's edge, and a warning when it `overrides` an axiom bind. A click on an axiom row opens it in the editor (`bindIndexFor(ids)`, `editBind`).
- The page takes the editor's whole width (list + inspector), so switching tabs doesn't resize it.
- Section, modifier and source chips filter.
- **Look up a combo**: a `KeyRecorder` recording into `lookupIndex` (-2) sets `lookupCombo` instead of a bind's key; the list then shows only rows on that key (`KeybindFilter.filter`'s `ids`), or offers Bind it when nothing holds it.
- **Keyboard**: `content/parts/KeyboardReference` draws `KeyMap.labels(sections, mods)` on `KeyboardMap` (the same keyboard as the editor's key map, through hooks): each key's icon and label under `keyMapMods`, coloured by source.
- Remembered per user (`StateManager` `keybindsReference`): `refView`, `refDensity` (compact rows), `refGlyphs` (⌃ ⌥ ⇧ and a Super icon, or words), `refFolded`.
### The editor
- `Keybinds.qml` while `editing`: the list card (three quarters of `editorWidth`, less where the screen is too narrow for both) beside an inspector card (`sideWidth * 1.45`) that holds Save/Discard.
- **The list** (`BindEditor`): `editLayout`, from `BindGroups.groups` over `visibleIndices` (the search and chips, in the saved order), through a JSON string so it only rebuilds when its shape changes. Sections in `actionSections` order (`BindSection`, folds kept in `EditsManager.keybindsFolded`); in a section, numbered runs (`BindGroups.runKey`: a workspace-number action on its own number key, no label of its own, same modifiers and flags) fold into one row that unfolds (`expandedRuns`). Rows (`BindListRow`): the pause switch, keycaps, the label, flags that are on, an issue mark, the unsaved dot.
- **Selection**: `selectedIndex` / `selectBind(i, reveal)`; adds, removes and moves keep it on its bind. `reveal(index)` sets `revealIndex` and emits `revealRequested(index)`, which unfolds its section and run; the row scrolls the card to centre itself (`TitledCard.scrollTo(item, true)`, which polishes the body first) and clears it (`revealDone`). A row built after the ask (the editor's Loader opening, the page opened from a Cheatsheet, a run unfolding) finds `revealIndex` when it completes. `editBind(index)` (the reference, the keyboard, a Cheatsheet) clears the edit search and chips if they hide the bind; a click on a row's own selection doesn't scroll. Add bind and Duplicate select the new bind and start recording its key.
- **The inspector** (`BindInspector`): rebuilt per selection (a Repeater over `[selectedIndex]`), so a typed field never commits onto another bind. With nothing selected, `KeyMapPanel`: `KeyMap.rows`/`extras` coloured by `KeyMap.occupancy` (axiom, paused, the user's config, both) under `keyMapMods`; a free key adds a bind on it, an axiom key selects its bind.
- **Changed and undo**: `_origins` holds each draft bind's index in the saved list (-1 new), matched by JSON whenever `draft.saved` changes and kept by every add/remove/move; `changedBinds` drives the unsaved dots, `revertBind` puts one back. `_remember(text)` snapshots the draft before a removal, preset or multi-bind pause; `undo()` restores it, `undoText` labels the strip. Saving or discarding clears it.
- **Reordering**: while `reorderable` (no search or chips), a row drags within its section over a `DragLayer` in `BindEditor`; the section is the target and `dropAt` turns a row position into `moveBind`.

### Presets
- `presets` are built from the workspace layout: four-way steps in a grid and with dynamic workspaces (up and down the output's list, left and right to the next output), and number keys 1–10 there, as the compositor's list has no set size. With those four-way steps, Southpaw too (SUPER + W/S and H/L through the workspaces, H/L being the next monitor with dynamic workspaces; A/D and J/K move focus; with SHIFT the window goes along). With strips (the scrolling layout's too), the Strips preset. Window management and Strips include SUPER + scroll (`scrollStep`). `presetPlan(id)` says per bind whether it's new, the same as an active bind already there, on a taken key (`takenBy`: every active bind on it), or `resume` (a paused bind does just this). Paused binds hold no key, so they take nothing. The Presets sheet (`PresetSheet`) shows that with checkboxes, taken keys ticked only for a preset that `replaces` (Southpaw, whose keys the defaults bind to other actions). `applyPreset(id, keyIds)` adds the ticked new binds at the end, resumes the ticked `resume` ones, and for a ticked taken key pauses the binds on it and puts the preset's bind right after them. All of it is an unsaved draft edit until Save, and Undo takes it back.
- **Saved presets** (`Keybinds.presets`, `[{ id, name, binds }]`, binds as `definitions.Keybind`; `personal` scope like `binds`, an exec/raw bind in one `commands`): `savePreset(name)` saves the editor's binds (unsaved edits too) at once through `SettingsManager.commitValues`, over the one by that name if there is one; `renamePreset`, `deletePreset`. `savedPresets` shapes them like the built-in ones (id `saved:<id>`), so `presetPlan`/`applyPreset` take them too (`_presetById`). The sheet lists them under the built-in ones, each group a `FoldingSection`; a saved one restores with Replace all binds (`restorePreset(id)`: the draft becomes its binds, origins matched afresh) or Merge (`applyPreset`).

### Recording a key
- `startRecording(index)` calls `CompositorManager.captureKeys(true)` (needs `keyCapture`), so bound combos reach `keybinds/KeyRecorder` instead of firing.
  - The recorder's window also inhibits the compositor's shortcuts while it records (a `ShortcutInhibitor`): niri's only way, as it has no empty mode to enter.
  - On Hyprland (`HyprlandManager.captureKeys`) that is an empty `axiom_record` submap. Hyprland only registers a submap that has a bind, so the submap has one unreachable bind.
  - A Lua timer leaves the submap after 30 s, even if qs dies.
  - This is the key recorder. It is unrelated to screen recording.
- A modifier pressed alone and let go records a tap (`KeyNames.tapName`, left or right from the keycode) and sets `release`, where the compositor has `modifierTap`.
- `components/methods/KeyNames` turns the Qt key event into a Hyprland key name.
- A wheel turn over the recorder becomes `mouse_up`/`mouse_down`/`mouse_left`/`mouse_right` with the modifiers held (`fromWheel`).
- Known gap: the recorder doesn't tell keypad keys apart, and doesn't map AltGr.

### Filters
- **List tab.**
  - A search plus toggle chips: `query`, `sectionFilter`, `modFilter`, `sourceFilter`, and the combo looked up (`lookupCombo`). They live in the manager so they survive the page.
  - Changed with `toggleFilter(group, value)` and `clearFilters()`.
  - The chips come from `modOptions`, built from the binds, not from the filtered result.
  - Filtering is done by `components/methods/KeybindFilter`. Chips in one group are alternatives; the groups and the search all apply.
- **Editor tab.**
  - Its own chips: `editSectionFilter`, `editModFilter`, and a state group of `editPausedOnly` (Paused, `pausedCount`) and `editIssuesOnly` (With issues), either when both are on; options `editSectionOptions`/`editModOptions`.
  - Cleared by `clearEditFilters()`, which Add bind also calls.
  - Applied in `visibleKey`. Turning any of them on, or searching, turns `reorderable` off.
- Both tabs draw their chips with `views/Keybinds/FilterChips`: groups of `{ value, label }` options, a `selection` map, and `toggled`/`cleared` signals.
