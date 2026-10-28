# Workspace strips (Hyprland scrolling layout)

> **Files:** `config/WorkspacesConfig.qml`, `components/methods/DynamicWorkspaces.qml`, `backend/internal/compositor/render/hyprlua.go` (`StripsLua`, `StripsRuntimeLua`), `services/compositor/HyprlandManager.qml` (`stripWindows`, `stepStrip`), `components/methods/WorkspaceGeometry.qml`, `components/bar/widgets/Workspaces/ActiveStrip.qml`, `components/bar/widgets/Workspaces/StripWindows.qml`
> **Config:** `Workspaces.strips`, `Workspaces.stripColumnWidth`, `Workspaces.stripFollowFocus`
> **Related:** [Workspaces](workspaces.md), [Config modes](config-modes.md), [Keybinds](keybinds.md), [Onboarding](../features/onboarding.md)

Monitors on Hyprland's `scrolling` layout: how they're configured, how the Lua reaches Hyprland in each mode, and how the bar, overview and binds follow them. On niri every output is a strip (`supports.stripsAlways`): the strip list is hidden, `stripColumnWidth` is niri's `default-column-width`, and the rest below (order, bar, overview, binds) holds as it does here ([niri backend](../compositor/niri-backend.md)).

### Config
- `strips` lists monitors as `{ monitor, direction }`:
  - `*` means every monitor, and a named entry wins over it
  - an empty monitor means the primary monitor.
- **The scrolling layout** (`Workspaces.layout: scrolling`, the one-choice niri-style setup) makes every monitor a horizontal strip: `WorkspacesConfig.strips` is `[{ monitor: "*", direction: "horizontal" }]` and the list is hidden, but kept for switching back. The onboarder offers it as a layout and then doesn't ask tiling or strips.
- `stripColumnWidth`/`stripFollowFocus` show only while there are strips (`x-showIf` `{ notEmpty: true }`, or the scrolling layout). They are `x-compositor.hyprland` fields, like the managed options, written through `configTable`.
- `WorkspacesConfig.strips` resolves the monitors and keeps each monitor's first entry; the compositor layer's are the daemon's own, resolved the same way (`manager.stripsOf`, from `Workspaces` and the primary monitor the shell sends).
- `stripDirection(screenName)` is `horizontal`, `vertical`, or `""` (tiles).

### Lua (`render.StripsLua`, the same in every mode)
- A `*` strip makes `scrolling` the layout everywhere, with its `scrolling.direction`: horizontal is `right`, vertical is `down`.
- Each named monitor gets a `hl.workspace_rule` on `m[<name>]` with `layout = "scrolling"` and its direction in `layout_opts`. This wins over the `*` strip.
- **Included / managed:** `M.strips()` runs from `setup()`.
  - It runs after managed's `hl.config`, so it wins over `general.layout`.
  - `general.layout` only offers dwindle and master; scrolling belongs to the strips.
- **Detached:** it runs in the runtime eval, wrapped by `render.StripsRuntimeLua` to apply once per Hyprland load (workspace rules add up rather than replace).
  - `AXIOM_STRIPS` names the strips applied. It lives in Hyprland's Lua state, so a Hyprland reload resets it and a shell reload keeps it.
  - Different strips can't be taken back, so a change reloads Hyprland's config. Its `configreloaded` then applies the new strips over the user's config alone.

### The scrolling layout (niri's workspaces on Hyprland)
- `Workspaces.layout: scrolling` makes every monitor a horizontal strip (above) and gives each monitor niri's workspaces: a column of them from its first id, without gaps, with an empty one after the last. `HyprlandManager.dynamicByLayout` turns on `supports.dynamicWorkspaces`, so everything niri's drive works the same: the bar (`WorkspaceStrip`, `WorkspaceCellRow`: occupied ones and the active one, app icons), the overview's column, up and down steps through the list and left and right to the next monitor (`HyprlandManager.focusOutput`, or `moveWindowToOutput`: the window to the workspace that monitor shows), number keys as the n-th of the list (its last, the empty one, past its end), and the Keybinds page's four-way presets. Unlike niri's, the layout stays editable (`CompositorManager.dynamicByLayout`), so the `WorkspacesStatus` intro and the onboarder's note don't show.
- **Ids.** Each monitor owns a block of `HyprlandManager.blockSize` (100) ids. Switching to or from the layout changes `CompositorManager.blockSize`, which remaps the workspaces like any layout change ([workspaces](workspaces.md) › Layout changes).
- **Shown.** `HyprlandManager.workspaces` is `DynamicWorkspaces.workspaces`: each monitor's real workspaces in its block, then the empty one after the last (made by Hyprland once gone to). Workspaces outside the block (special, named, stuck on another monitor) are left out.
- **Compaction.** Hyprland drops an empty workspace once it's left, which leaves a gap. 300 ms after a window fetch, with no slide, fetch or Lua under way, `HyprlandManager._compaction` plans with `DynamicWorkspaces.compaction`: each monitor's occupied workspaces and its active one go to its first ids in order, the windows moving down (`follow = false`, lowest target first, so none merges) with the `workspaces` animation off, then each monitor whose active one moved goes to its new id, and the focused monitor gets focus back last (without focusing its workspace again, which `workspace_back_and_forth` could undo). The plan is worked out from the state at that moment, so a change made meanwhile is just planned for next time.
- **Slides.** Every switch slides vertically (`goToWorkspace` treats the list as one column), with `animate`.
- **Fallback.** Where the compositor has no strips (sway) the layout is per monitor: the strips are ignored there and nothing turns dynamic. On niri the layout is greyed out, as niri works this way already.
- **Binds.** The Keybinds page's Strips preset, as with any strips; `stripConsume` (`consume_or_expel prev|next`) and `stripCenter` (`center`) are actions to bind by hand.

### Window order
- Where the compositor says which column a window is in and its place there (niri: the window's `column` and `tile`), that's the order. Hyprland reports no columns, so there strip order comes from the windows' places (`WorkspaceGeometry.stripOrder`):
  - tiled windows along the strip
  - a column's windows across it
  - floating windows last.
- `CompositorManager.stripWindows(id, vertical)` returns that order.

### Bar
- On a strip monitor, both workspace switchers follow their workspaces (all of them, or the shown grid row) with `workspaces/ActiveStrip`:
  - a divider: a `SeparatorMark` in the bar's `separatorStyle`, or a line when that's none
  - then the active workspace's windows, in strip order.
- The windows are drawn by `workspaces/StripWindows`: bar cells with app icons sized to the cells, the last focused one active, and a click focuses.
- **Wheel.** The wheel scrolls the strip a column at a time (`CompositorManager.stepStrip`: `layout("move ±col")`).
  - It acts on the focused monitor only, since layout messages act on the focused workspace.
  - It needs windows on the workspace; Hyprland refuses it on an empty one.
  - Hyprland focuses the column it moves to and warps the cursor there.
- **Popout.** `WorkspaceStrip`'s popout on a strip monitor is `WorkspaceStrips`: each occupied workspace (plus the active one) as its number cell, then its `StripWindows`.
- **One workspace.** With one workspace shown on a strip monitor (a size of 1, or down to the active one without `showEmpty` or with dynamic workspaces), the switchers show the windows alone (`stripOnly`: no number cell, no divider) while the workspace has any. With size 1, or one dynamic workspace, there's no popout. Every compositor.

### Overview
- The overview squeezes a strip workspace's tiled windows into its cell along the strip (`WorkspaceGeometry.stripRects`), so off-screen columns show.
- A tiled window dropped on a strip workspace lands as a new column after the nearest one (`stripDropTarget`). `placeWindow` focuses the target, after which scrolling opens it.

### Binds and onboarding
- The Keybinds page's Strips preset is listed while there are strips. It binds:
  - the `strip*` dispatcher actions: `swapcol`, `colresize ±conf`, `fit visible`
  - `SUPER + mouse_down`/`mouse_up` to focus right/left (`focusDir`), which moves along the strip.
- The onboarder's Workspaces page offers tiling, horizontal strips or vertical strips on every monitor, plus the list for per-monitor strips.
