# Workspaces (layout, navigation, the bar widget)

> **Files:** `config/WorkspacesConfig.qml`, `services/compositor/CompositorManager.qml`, `services/compositor/HyprlandManager.qml`, `components/methods/WorkspaceGeometry.qml`, `components/bar/widgets/Workspaces/Workspaces.qml`, `components/bar/widgets/Workspaces/`, `components/surfaces/workspaces/`, `components/views/Settings/WorkspacesStatus.qml`
> **Config:** `Workspaces.*` (`layout`, `count`, `columns`, `rows`, …)
> **Related:** [Workspace strips](workspace-strips.md), [Keybinds](keybinds.md), [Bar composition](../bar/composition.md), [Shared UI pieces](../core/shared-ui-pieces.md)

One workspace layout serves everything that shows workspaces or moves between them:
- the `Workspaces` bar widget, with its `WorkspaceGrid` and `WorkspaceStrips` popouts
- the workspace overview (`surfaces/workspaces/`; where the compositor has its own, `supports.overview`, `WorkspaceOverlay.compositorOverview` opens that instead: [contract](../compositor/contract.md) › Capabilities)
- the `WorkspacesMap` module
- the launcher's `/ws`
- the `workspaces` IPC target.

### Layouts
- `standard`: ids 1..`count`, shared by every monitor.
- `perMonitor`: each monitor gets its own block of `count` ids.
- `grid`: each monitor gets a block of `columns × rows` ids.
- `scrolling`: ids as `perMonitor` (`count` each), and every monitor a horizontal strip (`WorkspacesConfig.strips` is `*` whatever the list holds; [workspace strips](workspace-strips.md)). Offered only with `supports.strips` and not `stripsAlways` (`x-enumShowIf`). On Hyprland its workspaces are dynamic, as niri's, kept by axiom ([workspace strips](workspace-strips.md) › The scrolling layout). A config carrying it elsewhere (sway) works as `perMonitor`: the strips are ignored there (`CompositorManager.stripDirection`), and nothing else tells the two apart.
- Blocks are numbered over every monitor the saved monitor profiles name (`MonitorsConfig.profiles`, by their rules' `output`), connected or not, then the connected ones no profile names, each part in a stable order (`WorkspaceGeometry.orderMonitors`: the primary first, then by output identity). So a hotplug never moves a block: an unplugged monitor keeps its block for when it comes back. `WorkspaceGeometry.blockBases` gives each output's first id; `CompositorManager`, `HyprlandManager` and `NiriManager` all pass it the profiles, so their bases agree, and the remap places blocks by the same order (each monitor's `block`, its index taken from `_bases`).
- Where the compositor's workspaces belong to an output (`supports.outputWorkspaces`, niri), every layout gets blocks, `standard` too (`CompositorManager.perMonitorBlocks`), and nothing is remapped.
- **Dynamic workspaces** (`supports.dynamicWorkspaces`, niri): the compositor makes and removes them itself, one column per output, so no layout applies. The section's fields are greyed out under its `x-intro` (`WorkspacesStatus`), except `wrap`. Blocks are the backend's `blockSize` long (`CompositorManager.blockSize`), `workspaceIds` are the ones it has, `workspaceGrid` is false whatever the layout says (so the Workspaces widget's `showActiveIcon` is hidden), the widget always shows app icons (`showAppIcons` is hidden; `WorkspaceCellRow.appIcons`), `wideActive` and `relativeNumbers` show whatever the layout, and the overview is one column.
- Nothing else holds a workspace count or grid size.

### Ids
- `CompositorManager.workspaceBase(output)` / `workspaceIds(output)` give an output's ids (by its name).
- The overview lays them out `boardColumns × boardRows`. In the standard layout it shows windows from every monitor, each placed against its own monitor's origin.

### Navigation
- Everything goes through `CompositorManager`, so every switch slides the same way, on every compositor:
  - `goToWorkspace(id, mode, output)`
  - `stepWorkspace(direction, mode)`
  - `nthWorkspace(n, mode)`
  - `focusWindow`, for focusing a window on another workspace (used by the overview, dock, launcher and notifications).
- Never dispatch `hl.dsp.focus({ workspace })` or `{ window }` directly. (Rule: AGENTS.md › Services.)
- `CompositorManager` works out the legs (`{ id, axis }`) and hands them to the backend's `travel`; a backend without `workspaceSlide` just goes to the last one ([contract](../compositor/contract.md)).
- `mode` is `go`, `move` or `moveSilent`.
- Surfaces on a monitor pass their output's name; the focused one is the default. In a grid, an id outside that monitor's block is refused.
- **Dynamic workspaces**: up and down go through the output's list (`wrap` wraps round it, `workspaceWrapped` along the row), left and right to the output that way (`WorkspaceGeometry.outputToward`; the backend's `focusOutput`, or `moveWindowToOutput` for `move`/`moveSilent`), nothing without one. `nthWorkspace(n)` is the n-th of the list.
- **In a grid** a move only reaches the monitor's own ids.
  - It goes sideways first, then vertically, sliding along each axis in turn (`animate`).
  - Each leg of a two-leg trip takes `_legSpeed` of the configured time.
- **The slide** (`HyprlandManager.travel`) briefly overrides Hyprland's `workspaces` animation, then puts it back. The animation is read with the options (`HyprlandManager.animations`, and `animationsEnabled`: with `animations:enabled` off there's no slide, just the switch) at startup and on config reload.
- Keybinds call `axiom ipc workspaces …` rather than scripts of their own.

### Layout changes (remap)
- The compositor's workspaces stay where they are when the layout or size changes, so `CompositorManager` remaps them.
  - `_remapWorkspaces` runs 200 ms after `perMonitorBlocks`/`size` change, starting from the layout it last applied.
- `WorkspaceGeometry.remapWorkspaces` (pure, tested) sends each workspace's windows to the same place in its own monitor's new ids.
  - The first monitor in monitor order keeps a contested id; the rest take free ones, merging only when none is free.
  - It picks each monitor's new active workspace.
- The backend carries the plan out (`applyRemap`). On Hyprland one Lua chunk does it, with the `workspaces` animation off:
  1. windows go to `name:axiom-remap-<id>`, created on their own monitor, so a chain like 10 → 11, 11 → 12 can't merge
  2. every monitor goes to `name:axiom-remap-mon-<i>`, so its old (maybe empty) workspace is gone before its id is reused
  3. windows go to their ids
  4. monitors go to theirs, the focused one last.
- IPC `workspaces reconcile` runs the remap for the current layout, re-homing workspaces left outside their monitor's ids.

### The bar widget
- `bar/widgets/Workspaces/Workspaces.qml` loads a strip by layout:
  - standard: `workspaces/WorkspaceStrip`
  - grid (`CompositorManager.workspaceGrid`): `workspaces/WorkspaceGridStrip`, showing the active row (or column, on a vertical bar).
- **Which cells.** Without `showEmpty` (off by default; hidden with dynamic workspaces, which always leave empty ones out, the compositor's empty last one too) a strip shows the workspaces with windows and the active one; the grid strip does so within its row (`WorkspaceGridStrip.lineIds`). Down to one on a strip monitor, the strip shows alone ([workspace strips](workspace-strips.md)).
- With `wideActive`, both strips make the active `WorkspaceCell` twice as long.
- **Cells.** Both strips lay their cells out with `workspaces/WorkspaceCellRow`.
  - It holds every shown workspace, or one grid row.
  - `glyphOf` gives the grid's position arrow.
- **Active cell.** The active cell's box is one `workspaces/ActiveCellIndicator` sliding along the row.
  - It is drawn between the cells' two parts (`WorkspaceCell`'s `part`): the boxes at rest are under it, the labels and icons over it.
  - A step past an end (`CompositorManager.workspaceWrapped`, or the strip's own wheel wrap) sends it out of that end and in at the other.
- **Cross-fades.**
  - The grid strip cross-fades (`CrossFade`) to another row or column; the old one keeps its active cell while it fades.
  - `ActiveStrip` cross-fades to the windows of the next workspace.
- **Background.** With `showBackground` off, `Workspaces.qml` leaves its box clear (the bar's color shows through) and drops the inset: the cells take the full `widgetSize`, while the widget keeps its place among the bar's boxed widgets (`hasBackground`).
- **Pinned start.** The widget keeps its start put while its box resizes (`pinStart`, which `BarWidgetHost` reads), so its cells don't drift as the strip after them comes and goes.
- **Options.** The strips share one schema definition. Layout-only options hide themselves with `x-showIf: { "/Workspaces.layout": … }`.
- **Grid popout.** In a grid, the widget hands its `properties` and its bar's config to the `WorkspaceGrid` popout. Its cells are the strip's own `WorkspaceCell`s, with the same:
  - size, spacing and corners
  - widget style and colors
  - labels (grid position) and app icons
  - click to switch.
- On strip monitors the widget also shows the active workspace's windows ([Workspace strips](workspace-strips.md)).
