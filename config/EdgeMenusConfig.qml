pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// EdgeMenus: menus that pop out of a screen edge, holding overlay modules.
// While the edge menu editor has unsaved edits, the running menus show
// those (ConfigManager.live). Named with a Config suffix so the shell
// entry can be `EdgeMenus`.
QtObject {
  id: root

  // EdgeMenus.items: [EdgeMenu], each { id, name, enabled, screen, edge,
  // mode, …, layout: { grid, moduleScale, moduleBorders, modules }, open,
  // trigger, close }
  readonly property var menus: ConfigManager.live.EdgeMenus.items
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

  // The menu's edge as a ScreenEdge
  function edgeOf(menu) {
    return ScreenEdge.fromConfig(menu.edge);
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

  // An integrated menu's frame's inset from its strip's edges (0 without
  // one): the screen margin reaches its stroke's inner edge, as the screen
  // border's does, so the two strokes line up
  function frameInsetOf(menu) {
    return menu.frame ? Math.max(0, Appearance.screenMargin - Appearance.borderWidth) : 0;
  }

  // From an integrated menu's strip's edges to its padding: the frame and
  // its stroke
  function outerPadOf(menu) {
    return root.frameInsetOf(menu) + (menu.frame ? Appearance.borderWidth : 0);
  }

  // An integrated strip's own inner stroke: with the screen border off
  // (with it on, the border's strip inside it draws it)
  readonly property int innerStroke: Appearance.screenBorder ? 0 : Appearance.borderWidth

  // A menu's card size: the card size on its screen (OverlayConfig.
  // cardUnitOn, the card size setting's, not the overlay's own Module
  // size), scaled by the menu's moduleScale. A submenu's is on the screen
  // of the menu it opens from (`screen`)
  function cardUnitOf(menu, screen) {
    screen = screen ?? root.screenFor(menu);
    const unit = screen ? OverlayConfig.cardUnitOn(screen.width, screen.height) : GridPlacement.cardUnit;
    // A double grid (fineGrid) splits each unit in two each way
    return GridPlacement.gridUnitOf(unit * menu.layout.moduleScale / 100, menu.layout.grid.fine, root.gapOf(menu));
  }

  // The px between a menu's cards: the layout's gap drawn at the menu's
  // zoom (GridPlacement.gapOf), so the menu is an overlay page's grid
  function gapOf(menu) {
    return GridPlacement.gapOf(root.zoomOf(menu));
  }

  // What a menu's modules are drawn at: its moduleScale
  // (GridPlacement.zoomOf), so it scales their text and controls with
  // its cards, while the screen only changes how big the cards are
  function zoomOf(menu) {
    return GridPlacement.zoomOf(menu.layout.moduleScale / 100);
  }

  // The menu's length along its edge, from config alone (for the hover
  // strip before the menu has ever been loaded): its modules' grid at
  // card size `unit` and `gap` px between cards (cardUnitOf
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
