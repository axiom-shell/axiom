# Window switcher (Alt+Tab)

> **Files:** `services/compositor/WindowSwitcherManager.qml`, `config/WindowSwitcherConfig.qml`, `backend/internal/compositor/render/hyprlua.go` (`SwitcherBindLua`, `SwitcherLua`), `components/methods/WindowOrder.qml`, `shell/WindowSwitcher.qml`, `components/surfaces/switcher/SwitcherStrip.qml`
> **Config:** `WindowSwitcher.*` (`showDelay`, `scope`, `previews`, `compositorSwitcher`)
> **Related:** [Keybinds](keybinds.md), [Config modes](config-modes.md), [Workspaces](workspaces.md)

Alt+Tab is the bind actions `windowSwitcher` and `windowSwitcherReverse`.
- The defaults are ALT + Tab and ALT + SHIFT + Tab.
- The Keybinds page's "Window switcher" preset adds them to an existing config.
- Where the compositor has a switcher of its own (`supports.compositorSwitcher`, niri) and `WindowSwitcher.compositorSwitcher` is on (the default), the included and managed files bind these keys to that switcher instead ([niri backend](../compositor/niri-backend.md) › Primitives); detached keeps axiom's.

**Hyprland holds every key.** A surface can't see a modifier released before it maps and takes focus, and a quick tap always is.

### The bind and the submap
- The bind is a Lua function (`render.SwitcherBindLua`). On the press itself it:
  1. enters the `axiom_switcher` submap
  2. emits `hl.dsp.event("axiom-switcher:step ±1")`.
- **The submap** (`render.SwitcherLua`) is built from the switcher binds (`KeyNames.split`).
  - It is emitted with the binds in every mode; in detached mode, only for the binds applied.
  - It repeats each switcher combo as a step, and binds Return (pick) and Escape (cancel).
- **The release is no bind.** Hyprland fires a release bind on a modifier only when no other key came between (as with a tapped SUPER), and Tab always comes between.
- **Instead, a listener.** The bind starts `axiom_switcher_watch()`, an `input.keyboard.key` listener.
  - 10 ms after each key release, it picks once none of the held keys is down (`hl.is_key_down`).
  - The held keys are `AXIOM_SWITCHER_HELD`, from `switcherHeld`: the bind's modifiers except SHIFT (which only turns the direction around), as `Alt_L`/`Alt_R`, ….
  - The listener removes itself on leaving.
- Picking, cancelling and the listener all leave the submap inside Hyprland itself, so it can't stick while qs is down.
- Redefining a submap adds to its binds, so the chunk first unbinds the keys its last run bound (`AXIOM_SWITCHER_KEYS`).
- KeybindManager leaves the submap out of the page, and its `editor` (KeybindEditor) flags a switcher key that has no modifier to hold.

### Events and the manager
- Events arrive on socket2 as `custom>>axiom-switcher:<verb>` (HyprlandManager's `switcherKey(verb, argument)`, the backend signal `WindowSwitcherManager` listens to; [contract](../compositor/contract.md)): no process per key, and in order. HyprlandManager fetches nothing for `custom` events.
- `WindowSwitcherManager.step(n)` opens the switcher on the first event.
  - It snapshots `CompositorManager.windows`, most recently used first (`methods/WindowOrder.mru`, by `focusHistoryID`).
  - The event-driven `CompositorManager.activeWindowId` goes first, since the fetched window list lags behind a quick second switch.
  - The list is filtered by `DockLayout.inScope` for `scope`, limited to the focused monitor, and fixed until the switcher closes.
- `commit()` focuses the selection through `CompositorManager.focusWindow`. It does nothing when the selection is the window focused at open.
- A tile click `pick`s, and leaves through `HyprlandManager.leaveSwitcher` (`axiom_switcher_leave()`). The listener stops and the submap resets, the same way the key recorder's submap is left ([Keybinds](keybinds.md#recording-a-key)).
- A commit while closed does nothing, so a late Return or release can't refocus the last pick.

### Drawing
- It draws only once held for `showDelay` (`shown`), so a tap swaps windows invisibly.
- `shell/WindowSwitcher` is a `FloatingPopout` per screen (`axiom-switcher`, blurred with the launcher), shown on the monitor it opened on. It claims `switcher:<screen>` (ranked `launcher`), so it closes the popouts it covers ([Registry](../popouts/registry.md)).
- It holds `surfaces/switcher/SwitcherStrip`: a `TileFlow` of `SwitcherTile`s by count, up to 80% of the screen wide.
- Each tile shows the overview's `WindowPreview` (live while selected), or the app icon when `previews` is off, over the title.
- It takes no keyboard focus, so focus stays on the window until one is picked.

### IPC
- `windowSwitcher`: `next`, `previous`, `commit`, `cancel`.
- No submap is involved, so nothing picks on a release. This is for scripts and testing.
