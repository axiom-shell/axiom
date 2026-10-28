pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Workspaces section: the workspace layout the bar widget,
// the overview, the WorkspacesMap module and CompositorManager's navigation
// share. Named WorkspacesConfig because `Workspaces` is a bar widget type.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Workspaces

  // Grid: each monitor owns columns × rows ids. Per monitor: each monitor
  // owns a flat block of count ids. Standard: ids 1..count, shared by every
  // monitor. Grid/perMonitor number monitors by a stable order (see
  // WorkspaceGeometry.orderMonitors), not raw Hyprland discovery order.
  // Scrolling: ids as per monitor, and every monitor a horizontal strip
  // (strips below). Where the compositor has no strips, CompositorManager
  // ignores them, so it works as per monitor there (sway).
  // "standard" | "perMonitor" | "grid" | "scrolling"
  readonly property string layout: _c.layout
  readonly property bool grid: _c.layout === "grid"
  readonly property bool scrolling: _c.layout === "scrolling"
  // True when each monitor gets its own block of ids (grid or perMonitor)
  // instead of sharing 1..count (standard).
  readonly property bool perMonitorBlocks: _c.layout !== "standard"
  readonly property int count: _c.count
  readonly property int columns: grid ? _c.columns : count
  readonly property int rows: grid ? _c.rows : 1
  // Workspaces a monitor shows
  readonly property int size: grid ? columns * rows : count
  readonly property bool wrap: _c.wrap
  readonly property bool animate: _c.animate
  // The overview board's columns: the grid's, else even rows where possible
  readonly property int boardColumns: grid ? columns : _evenColumns(count)
  readonly property int boardRows: Math.ceil(size / boardColumns)

  // Strips (Hyprland's scrolling layout), per monitor: [{ monitor, direction }]
  // from each strip's ScreenTarget: the primary monitor's name, "*" for
  // every monitor a named entry doesn't cover, or each one named; only a
  // monitor's first entry kept. direction: "horizontal" | "vertical". The scrolling layout makes
  // every monitor a horizontal strip, whatever the list holds (it's kept
  // for switching back).
  readonly property var strips: scrolling ? [
    {
      "monitor": "*",
      "direction": "horizontal"
    }
  ] : [].concat(..._c.strips.map(strip => {
    const mode = strip.screen.mode;
    const monitors = mode === "all" ? ["*"] : mode === "named" ? strip.screen.names : [General.primaryMonitor];
    return monitors.map(monitor => ({
          "monitor": monitor,
          "direction": strip.direction
        }));
  })).filter((strip, i, all) => all.findIndex(other => other.monitor === strip.monitor) === i)
  readonly property bool hasStrips: strips.length > 0
  // The strips and their settings as a string, for CompositorConfigManager's
  // change check
  readonly property string _stripsJson: JSON.stringify([strips, stripOptions])
  // The strip settings Hyprland takes (HyprLua.stripsLua)
  readonly property var stripOptions: ({
      "stripColumnWidth": _c.stripColumnWidth,
      "stripFollowFocus": _c.stripFollowFocus
    })

  // Columns for n workspaces: one row up to 5, else the narrowest column
  // count at least as wide as tall that divides n evenly (10 → 5 × 2), as
  // long as that's at most 3:1; otherwise rows near square, the last short
  function _evenColumns(n) {
    if (n <= 5)
      return Math.max(1, n);
    for (let c = Math.ceil(Math.sqrt(n)); c <= n; c++) {
      if (n % c === 0 && c / (n / c) <= 3)
        return c;
    }
    return Math.ceil(n / Math.floor(Math.sqrt(n)));
  }

  // The strip direction of the monitor named `screenName`, "" when it tiles
  function stripDirection(screenName) {
    const strip = strips.find(s => s.monitor === screenName) ?? strips.find(s => s.monitor === "*");
    return strip?.direction ?? "";
  }
}
