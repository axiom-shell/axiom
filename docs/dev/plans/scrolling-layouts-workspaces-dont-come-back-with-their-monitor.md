# The scrolling layout's workspaces don't come back with their monitor

> **Issue:** [The scrolling layout's workspaces don't come back with their monitor](../issues.md#the-scrolling-layouts-workspaces-dont-come-back-with-their-monitor)
> **Status:** proposed

### Problem
Under `Workspaces.layout: scrolling` on Hyprland, axiom keeps niri-style workspaces itself (`HyprlandManager.dynamicByLayout`): each monitor shows only the workspaces inside its block of 100 ids (`DynamicWorkspaces.workspaces`), and `_compaction` closes gaps only inside that block. Nothing in the shell or the daemon reacts to a hotplug for workspaces: `CompositorManager.outputsHotplugged` has no listener, the remap runs only on a layout or size change (`_remapTimer`), and the daemon's hotplug work (`manager.Manager`'s profile switch) is outputs only; stage 7 changed none of this. Three things go wrong, from reading the code (none tried on a nested Hyprland yet):

1. **The unplugged monitor's workspaces vanish from every list.** Hyprland moves them to another monitor, outside that monitor's block, so `DynamicWorkspaces.workspaces` drops them and `compaction` ignores them. Their windows are reachable only by the overview or `axiom ipc workspaces reconcile`. Hyprland is believed to move them back on replug (each workspace keeps the monitor it left, `m_lastMonitor`, in its monitor-connect code); that needs confirming before anything is built on it.
2. **Blocks shift with the connected set.** `WorkspaceGeometry.blockBases` numbers blocks by position among the *connected* monitors (primary first, then output identity). Unplug a monitor that isn't last in that order and every monitor after it gets a new base: its real workspaces (201…) fall outside its new block (101…199), so its whole list shrinks to the one synthetic empty workspace. This is wider than the entry says. The same shift hits the `perMonitor` and `grid` layouts on Hyprland and sway (`CompositorManager._bases`), outside this entry.
3. **Persistent workspaces sit empty in the list.** A user's `persistent` workspace rule keeps an empty workspace alive; `DynamicWorkspaces.workspaces` shows every real in-block workspace, so it sits in the middle or past the end of the list. A gap before an occupied one closes (compaction moves the later windows onto it), but empty persistent ones after the last occupied one stay, and the "one empty after the last" rule no longer holds.

Who it affects: scrolling-layout users on Hyprland who hotplug a monitor (laptop docks), and the few who also keep persistent workspace rules. niri isn't affected (`supports.outputWorkspaces`, which skips the remap).

### Options
#### A. Defer
Keep the entry logged. `workspaces reconcile` already re-homes what drops out. Costs nothing, but problem 2 makes a dock unplug empty the remaining monitors' lists until the user runs a command they have no reason to know about.

#### B. Re-home on hotplug (reuse the remap)
Under `dynamicByLayout`, run the remap `reconcile` runs (`_remapWorkspaces(current, current)`) once the outputs have settled after `outputsHotplugged`. `WorkspaceGeometry.remapWorkspaces` already moves every out-of-block workspace into a free id of the monitor it's on, so problems 1 and 2 both clear: the moved workspaces join the remaining monitor's list, and the shifted monitors' workspaces move into their new blocks. Compaction then tidies them as usual. About 15 lines in `CompositorManager` plus a test row. **Left out:** nothing comes back on replug. The unplugged monitor's workspaces now belong to the monitor they moved to (their old ids are gone, so Hyprland has nothing to return), and the returning monitor starts empty. That matches what `reconcile` does today, but not niri.

#### C. Stable blocks plus borrowed workspaces (niri's behaviour)
Number blocks over every monitor the saved monitor profiles name (`MonitorsConfig.profiles`, already kept; unknown monitors after), so a block never shifts with what's connected (problem 2). `DynamicWorkspaces.workspaces` lists a monitor's out-of-block workspaces after its own as borrowed, and compaction and navigation leave them where they are, so Hyprland's own return on replug brings them home (problem 1). Costs: `HyprlandManager._bases` and `CompositorManager._bases` must change together (and the latter serves every layout), the borrowed workspaces need a rule in navigation (`nthWorkspace`, steps) and the overview's column, and it relies on Hyprland's return, unconfirmed. Likely 100–150 lines plus tests, at the rare-path limit, for one layout on one compositor.

Separately from A–C, problem 3 has one small fix: `DynamicWorkspaces.workspaces` leaves out in-block workspaces that are empty and not active (the synthetic one after the last still covers "go to a new one"). That's a pure-helper change with test rows in `tst_DynamicWorkspaces`, a few lines.

### Recommendation
**B, plus the persistent-workspace filter.** The rule for rare paths asks for the smallest fix, and B reuses the remap and IPC that exist rather than adding block bookkeeping. It clears the real harm (windows dropping out of every list, and problem 2 emptying the monitors that are still plugged in) at the cost of niri's give-back, which A doesn't have either. If the maintainer wants the give-back, C is the way, but only after a nested Hyprland confirms that Hyprland returns the workspaces. The block shift in `perMonitor`/`grid` (problem 2 outside this layout) should be logged as its own entry.

### Items
1. **The scrolling layout's workspaces re-home on hotplug** (small): `CompositorManager` listens for `outputsHotplugged` and, under `dynamicByLayout`, runs the current layout's remap after the outputs settle (restart `_remapTimer`, or a short settle timer if the profile switch's modeset needs longer). Test rows in `tst_WorkspaceGeometry` for a middle monitor unplugged (shifted bases) and one monitor's workspaces on another. Docs: `hyprland/workspace-strips.md` › The scrolling layout, `hyprland/workspaces.md` › Layout changes. Checked on a nested Hyprland with a headless output created and removed.
2. **Persistent workspaces stay out of the scrolling layout's list** (trivial): `DynamicWorkspaces.workspaces` drops empty, inactive in-block workspaces; `tst_DynamicWorkspaces` rows for a persistent one in the middle and past the end.
3. **Log the block shift for `perMonitor`/`grid`** (trivial, issues.md entry only): blocks move when a monitor that isn't last unplugs, on Hyprland and sway.
