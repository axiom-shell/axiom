pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

/* The desktop's modules: the layouts editor's draft of the Desktop section
 * (`editor`, shown live on the desktop while it differs from the config),
 * which of its layouts is edited (`selectedTarget`: "all", "primary" or a
 * monitor's name), and the room each screen's desktop has.
 *
 * Desktop.items are layouts, each for what its `screen` picks: a monitor
 * shows one naming it if there is one, else the primary monitor's on the
 * primary monitor, else the one for all monitors (DesktopConfig.sourceFor).
 * A monitor without one of its own is edited by giving it one
 * (createForTarget), a copy of what it showed. */
QtObject {
  id: root

  // "all" | "primary" | a monitor's name
  readonly property string selectedTarget: root._selectedTarget
  property string _selectedTarget: "primary"

  property ScreenLayoutEditor editor: ScreenLayoutEditor {
    path: ["Desktop"]
    host: "desktop"
    name: I18n.tr("Desktop")
    scope: root.selectedTarget
    previewSection: "Desktop"
    screen: root.screenFor(root.selectedTarget)
    insets: root.insetsFor(screen)
    layoutOf: local => root.layoutIn(local, root.selectedTarget)
    layoutsOf: local => (local?.items ?? []).map(layout => ({
            "layout": layout,
            "name": layout.screen.mode === "all" ? I18n.tr("Desktop (all monitors)") : layout.screen.mode === "primary" ? I18n.tr("Desktop (primary monitor)") : I18n.tr("Desktop ({0})", layout.screen.names.join(", "))
          }))
  }

  // The selected target's own layout in the draft, null when it has none
  // (a monitor showing another's)
  readonly property var selectedLayout: root.editor.localLayout
  readonly property var _desktop: root.editor.local

  // The layout `key` names in a Desktop section ("all", "primary", or the
  // one naming that monitor), or null
  function layoutIn(desktop, key) {
    const items = desktop?.items ?? [];
    if (key === "all" || key === "primary")
      return items.find(layout => layout.screen.mode === key) ?? null;
    return items.find(layout => layout.screen.mode === "named" && layout.screen.names.includes(key)) ?? null;
  }

  // Whether `key` names one monitor (not all monitors or the primary one)
  function isMonitorTarget(key) {
    return key !== "all" && key !== "primary";
  }

  function selectTarget(key) {
    if (key === root._selectedTarget)
      return;
    root.editor.layout.clearSelection();
    root._selectedTarget = key;
  }

  // What can be edited, [{ key, label, status }]: all monitors, the
  // primary monitor, then each monitor (plugged in, then those with a
  // layout of their own that aren't), with what each shows
  readonly property var targets: {
    const desktop = root._desktop;
    if (!desktop)
      return [];
    const screens = General.outputs.slice();
    const names = screens.map(screen => screen.name);
    desktop.items.filter(layout => layout.screen.mode === "named").forEach(layout => layout.screen.names.forEach(name => {
        if (!names.includes(name))
          names.push(name);
      }));
    const onOff = layout => layout?.enabled ? I18n.tr("On") : I18n.tr("Off");
    const out = [
      {
        "key": "all",
        "label": I18n.tr("All monitors"),
        "status": onOff(root.layoutIn(desktop, "all"))
      },
      {
        "key": "primary",
        "label": DesktopConfig.primaryName ? I18n.tr("Primary monitor ({0})", DesktopConfig.primaryName) : I18n.tr("Primary monitor"),
        "status": onOff(root.layoutIn(desktop, "primary"))
      }
    ];
    names.forEach(name => {
      const screen = screens.find(s => s.name === name);
      out.push({
        "key": name,
        "label": screen ? (screen.model ? I18n.tr("{0} · {1}", name, screen.model) : name) : I18n.tr("{0} · not connected", name),
        "status": root.statusOf(name, desktop)
      });
    });
    return out;
  }

  // What the monitor named `name` shows, in words
  function statusOf(name, desktop) {
    switch (DesktopConfig.sourceFor(name, desktop)) {
    case "named":
      return I18n.tr("Own layout");
    case "primary":
      return I18n.tr("Uses the primary monitor's");
    case "all":
      return I18n.tr("Uses all monitors'");
    }
    return root.layoutIn(desktop, name) ? I18n.tr("Off") : I18n.tr("Shows nothing");
  }

  // The selected monitor gets a layout of its own: a copy of the one it
  // shows, else an empty one
  function createForTarget() {
    const name = root.selectedTarget;
    if (!root.isMonitorTarget(name) || root.selectedLayout)
      return;
    root.editor.edit(desktop => {
      const source = DesktopConfig.sourceFor(name, desktop);
      const shown = source === "primary" || source === "all" ? root.layoutIn(desktop, source) : null;
      const layout = shown ? Utils.clone(shown) : ConfigManager.withDefaults({}, "DesktopLayout");
      layout.id = Utils.newId(Utils.slug(name) || "monitor", desktop.items);
      layout.screen = {
        "mode": "named",
        "names": [name]
      };
      layout.enabled = true;
      desktop.items.push(layout);
    });
    root.editor.layout.clearHistory();
  }

  // The selected monitor's own layout goes: it shows the primary
  // monitor's or all monitors' again. A monitor that isn't plugged in
  // leaves the picker with it, so the primary monitor is selected instead
  function removeTarget() {
    const name = root.selectedTarget;
    if (!root.isMonitorTarget(name))
      return;
    root.editor.layout.clearSelection();
    root.editor.edit(desktop => {
      // Off its layout, which goes once it names no monitor
      desktop.items = desktop.items.map(layout => {
        if (layout.screen.mode !== "named" || !layout.screen.names.includes(name))
          return layout;
        layout.screen.names = layout.screen.names.filter(n => n !== name);
        return layout.screen.names.length > 0 ? layout : null;
      }).filter(layout => layout !== null);
    });
    root.editor.layout.clearHistory();
    if (!General.outputs.slice().some(screen => screen.name === name))
      root.selectTarget("primary");
  }

  function setEnabled(enabled) {
    if (!root.selectedLayout || root.selectedLayout.enabled === enabled)
      return;
    root.editor.updateLayoutField("enabled", enabled);
  }

  // --- Room ---

  // The screen a target is laid out on: its monitor, else the primary
  // monitor (for all monitors, and a monitor that isn't plugged in)
  function screenFor(key) {
    const screens = General.outputs.slice();
    return screens.find(screen => screen.name === key) ?? screens.find(screen => screen.name === DesktopConfig.primaryName) ?? screens[0] ?? null;
  }

  // The room kept clear on each side of a screen's desktop ({ left, top,
  // right, bottom } px): what axiom reserves there (the border, bars,
  // integrated edge menus), or what Hyprland says is reserved (docks too)
  // if more, then Hyprland's gaps_out, so the grid lines up with where
  // tiled windows start
  function insetsFor(screen) {
    if (!screen)
      return {
        "left": 0,
        "top": 0,
        "right": 0,
        "bottom": 0
      };
    const reserved = DockManager.reservedOf(screen);
    const side = (location, index) => Math.max(ScreenEdgeManager.reservedWithMenusOn(screen, location), reserved[index]) + (CompositorManager.gapsOut[Bar.edgeName(location)] ?? 0);
    return {
      "left": side(Bar.Left, 0),
      "top": side(Bar.Top, 1),
      "right": side(Bar.Right, 2),
      "bottom": side(Bar.Bottom, 3)
    };
  }
}
