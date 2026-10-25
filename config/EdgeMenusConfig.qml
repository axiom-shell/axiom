pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// EdgeMenus: menus that pop out of a screen edge, holding overlay modules.
// While the edge menu editor has unsaved edits, the running menus show
// those (ConfigManager.previews). Named with a Config suffix so the shell
// entry can be `EdgeMenus`.
QtObject {
  id: root

  // EdgeMenus.items: [EdgeMenu], each { id, name, enabled, screen, edge,
  // mode, …, layout: { grid, moduleScale, moduleBorders, modules }, open,
  // trigger, close }
  readonly property var menus: (ConfigManager.previews.EdgeMenus ?? ConfigManager.config.EdgeMenus).items
  readonly property var enabledMenus: root.menus.filter(menu => menu.enabled && menu.id)
  // A menu's own fields in groups (`x-group`), for the edge menu editor
  readonly property var fieldGroups: SchemaLayout.objectGroups(ConfigManager.configSchema.definitions.EdgeMenu, ["layout.modules"])

  // A menu with no edge of its own: it opens only beside another, from a
  // Submenu module there (content/Submenu/MenuSubmenu)
  function isSubmenu(menu) {
    return menu?.mode === "submenu";
  }

  function menuById(id) {
    return root.menus.find(menu => menu.id === id) ?? null;
  }

  // The menu a bar widget opens as its popout (its `popout.menu`, with
  // `popout.enabled` on), else "": it opens its own popout, if any. A menu
  // that's gone or disabled leaves it its own. Widgets without the fields
  // (Separator, the tray) have none; a Button has no popout of its own.
  function popoutMenuOf(properties) {
    const id = properties?.popout?.enabled ? (properties.popout.menu ?? "") : "";
    return id !== "" && root.enabledMenus.some(menu => menu.id === id && !root.isSubmenu(menu)) ? id : "";
  }

  // The ids of the menus a bar widget entry opens, as configured (gone or
  // disabled alike): its menu popout, then a Button's click menu
  function menusOpenedBy(widget) {
    const props = widget?.properties;
    const ids = [props?.popout?.enabled ? (props.popout.menu ?? "") : ""];
    if (widget?.type === "Button" && props?.action === "edgeMenu")
      ids.push(props.menu ?? "");
    return ids.filter((id, i) => id !== "" && ids.indexOf(id) === i);
  }

  // A bar widget with a popout of its own opens it: on, and no menu
  // opened in its place
  function opensOwnPopout(properties) {
    return !!properties?.popout?.enabled && root.popoutMenuOf(properties) === "";
  }

  // The first enabled menu holding a module of `type`, else null
  function menuWithModule(type) {
    return root.enabledMenus.find(menu => menu.layout.modules.some(module => module.type === type)) ?? null;
  }

  // The menu's screen: the one its ScreenTarget names, else the primary
  // monitor
  function screenFor(menu) {
    return General.screensFor(menu.screen)[0] ?? null;
  }

  // The menu's edge as a Bar.Location
  function edgeOf(menu) {
    return Bar.getLocationFromString(menu.edge);
  }

  // The menu's box colours
  function colorsOf(menu) {
    return {
      "fill": Theme.resolveColor(menu.backgroundColor),
      "stroke": Theme.resolveColor(menu.borderColor)
    };
  }

  // Space between the menu's box and its modules: its own, else (-1) the
  // popouts'
  function paddingOf(menu) {
    return menu.padding >= 0 ? Widget.px(menu.padding) : PopoutsConfig.padding;
  }

  // The menu's length along its edge, from config alone (for the hover
  // strip before the menu has ever been loaded): its modules' grid at
  // card size `unit` and `gap` px between cards (EdgeMenuManager.cardUnitOf
  // and gapOf), as EdgeMenuBody lays it out, plus its padding
  function lengthOf(menu, vertical, unit, gap) {
    return root.gridLengthOf(menu, vertical, unit, gap) + root.paddingOf(menu) * 2;
  }

  // The menu's modules' grid along its edge, unstretched, at card size
  // `unit`, `gap` px between cards
  function gridLengthOf(menu, vertical, unit, gap) {
    const sizes = GridPlacement.trackSizes(GridPlacement.bounds(menu.layout.modules), unit, null, gap);
    return vertical ? sizes.height : sizes.width;
  }
}
