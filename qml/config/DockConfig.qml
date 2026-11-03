pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Dock section: any number of docks, each with its own
// place, pinned apps and behaviour (DockEntry in the schema). Named
// DockConfig because `Dock` is the shell module.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Dock

  // [DockEntry]. Goes through a string so a reload that leaves the list
  // unchanged doesn't rebuild the docks.
  readonly property string _docksJson: JSON.stringify(_c.items)
  readonly property var docks: JSON.parse(_docksJson)
  // The enabled ones, by id: what the shell builds
  readonly property var shownIds: root.docks.filter(dock => dock.enabled).map(dock => dock.id)

  // The apps a dock pins: its own with pinnedOwn, else the shared
  // Apps.pinned
  function pinnedOf(dock) {
    return dock.pinnedOwn ? dock.pinned : Apps.pinned;
  }

  function dockById(id) {
    return root.docks.find(dock => dock.id === id) ?? null;
  }

  // The screens a dock may be on, by its `screen` (as an OSD's): every
  // one for "focused" and "all" (shell/Dock shows it only where
  // ShellManager.showsOn puts it), else those it's on
  function screensOf(dock) {
    return General.screensFor(dock.screen);
  }

  // The name on its tab: its own, else its edge's
  function labelOf(dock) {
    if (dock.name)
      return dock.name;
    const names = {
      "top": I18n.tr("Top dock"),
      "bottom": I18n.tr("Bottom dock"),
      "left": I18n.tr("Left dock"),
      "right": I18n.tr("Right dock")
    };
    return names[dock.edge] ?? dock.edge;
  }
}
