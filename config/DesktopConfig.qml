pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Reader for the Desktop section: overlay modules on the desktop, under
// the windows. Desktop.items are layouts, each for the monitors its
// `screen` (a ScreenTarget) picks: a monitor shows the most specific one
// that's enabled, one naming it, else the primary monitor's (on the
// primary monitor), else the one for all monitors; a layout naming a
// monitor that's turned off leaves it empty. Each is a DesktopLayout
// ({ id, enabled, screen, grid, moduleScale, moduleBorders, modules }).
// The layouts editor's unsaved draft shows live (DesktopManager sets it as
// a preview).
QtObject {
  id: root
  readonly property var desktop: ConfigManager.previews.Desktop ?? ConfigManager.config.Desktop
  // A DesktopLayout's own fields in groups (`x-group`), for the layouts
  // editor
  readonly property var fieldGroups: SchemaLayout.objectGroups(ConfigManager.configSchema.definitions.DesktopLayout, ["modules", "screen"])
  // The primary monitor's name, as surfaces place on it (a primary monitor
  // that isn't plugged in falls back to the first screen)
  readonly property string primaryName: General.screensNamed(General.primaryMonitor)[0]?.name ?? ""
  // The layout the screen named `name` matches in `desktop` (a Desktop
  // section; the live one when left out), most specific first, enabled or
  // not; null for none
  function matchFor(name, desktop) {
    const items = (desktop ?? root.desktop).items;
    return items.find(layout => layout.screen.mode === "named" && layout.screen.names.includes(name)) ?? (name === root.primaryName ? items.find(layout => layout.screen.mode === "primary") : undefined) ?? items.find(layout => layout.screen.mode === "all") ?? null;
  }
  // Which layout the screen named `name` shows in `desktop`: "named" (one
  // naming it), "primary", "all", or "" for none (none matches, or the
  // match is turned off)
  function sourceFor(name, desktop) {
    const match = root.matchFor(name, desktop);
    return match?.enabled ? match.screen.mode : "";
  }
  // The DesktopLayout the screen named `name` shows, or null
  function layoutFor(name) {
    const match = root.matchFor(name);
    return match?.enabled ? match : null;
  }
}
