pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Menus: menus of overlay modules, on a screen edge, in a strip beside the
// windows or in a window of their own. While the menu editor has unsaved
// edits, the running menus show those (ConfigManager.live). Named with a
// Config suffix so the shell entry can be `Menus`.
QtObject {
  id: root

  // Menus.items: [Menu], each { id, name, enabled, screen, edge,
  // placement, …, layout: { grid, moduleScale, moduleBorders, modules }, open,
  // close }
  readonly property var menus: ConfigManager.live.Menus.items
  readonly property var enabledMenus: root.menus.filter(menu => menu.enabled && menu.id)
  // A menu's own fields in groups (`x-group`), for the menu editor
  readonly property var fieldGroups: SchemaLayout.objectGroups(ConfigManager.configSchema.definitions.Menu, ["layout.modules"])

  // A menu with no edge of its own (`placement` free): it opens in a window
  // of its own (surfaces/menu/FreeMenu) at the bar widget that opens
  // it as its popout or at its `freeAnchor`, or beside another menu from
  // a Submenu module there (content/Submenu/MenuSubmenu)
  function isFree(menu) {
    return menu?.placement === "free";
  }

  function menuById(id) {
    return root.menus.find(menu => menu.id === id) ?? null;
  }

  // Each placement's label (the schema's `x-enumLabels`: English, shown
  // through I18n.tr), for the menu pickers
  readonly property var placementLabels: ConfigManager.configSchema.definitions.Menu.properties.placement["x-enumLabels"]

  // Whether a menu picker limited to `placements` (its `x-menuPlacements`:
  // a widget's hover popout takes no strip, which pushes the bars
  // inwards) offers menu `id`
  function offeredIn(id, placements) {
    const menu = root.menuById(id);
    return menu !== null && Array.prototype.includes.call(placements, menu.placement);
  }

  // The menu a bar widget opens as its popout (its `popout.menu`, with
  // `popout.enabled` on), else "": it opens its own popout, if any. A menu
  // that's gone or disabled leaves it its own. Widgets without the fields
  // (Separator, the tray) have none; a Button has no popout of its own.
  // A free menu opens at the widget (FreeMenuPlace)
  function popoutMenuOf(properties) {
    const id = properties?.popout?.enabled ? (properties.popout.menu ?? "") : "";
    return id !== "" && root.enabledMenus.some(menu => menu.id === id) ? id : "";
  }

  // The ids of the menus a bar widget entry opens, as configured (gone or
  // disabled alike): its menu popout, then a Button's click menu
  function menusOpenedBy(widget) {
    const props = widget?.properties;
    const ids = [props?.popout?.enabled ? (props.popout.menu ?? "") : ""];
    if (widget?.type === "Button" && props?.action === "menu")
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

  // Whether an edge menu can pop out (`popOutButton`, an `edge` menu's
  // alone: never a strip, and a free menu is out already): its button
  // lifts it into the free host, at its box (MenuManager.popOut)
  function canPopOut(menu) {
    return menu?.placement === "edge" && !!menu.popOutButton;
  }

  // Whether a menu is drawn as tiles (`background: none` on an edge or
  // free menu, MenuTiles.tiled): no box of its own, its cards each a tile
  // with its own shadow and blur
  function tiledOf(menu) {
    return MenuTiles.tiled(menu);
  }

  // Whether an edge menu is held off its edge: `detached`, or tiled
  // (MenuTiles.detached). Every read of a menu's detached state goes
  // through here
  function detachedOf(menu) {
    return MenuTiles.detached(menu);
  }

  // The menu's box colours
  function colorsOf(menu) {
    return {
      "fill": Theme.resolveColor(menu.backgroundColor),
      "stroke": Theme.resolveColor(menu.borderColor)
    };
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
  // size), at the menu's Module size (scaleOf). A submenu's is on the
  // screen of the menu it opens from (`screen`)
  function cardUnitOf(menu, screen) {
    screen = screen ?? root.screenFor(menu);
    const unit = screen ? OverlayConfig.cardUnitOn(screen.width, screen.height) : GridPlacement.cardUnit;
    // A double grid (fineGrid) splits each unit in two each way
    return GridPlacement.gridUnitOf(unit * root.scaleOf(menu, screen), menu.layout.grid.fine, root.gapOf(menu, screen));
  }

  // A menu's Module size as a factor: its moduleScale, shrunk so its
  // modules' depth across its edge (a submenu's width) fits its screen
  // less its padding (GridPlacement.fitModuleScale), as a screen layout's cards
  // shrink to fit its screen. Along its edge it scrolls or is fitted
  // instead (MenuBody)
  function scaleOf(menu, screen) {
    screen = screen ?? root.screenFor(menu);
    const scale = menu.layout.moduleScale / 100;
    if (!screen)
      return scale;
    const wide = root.isFree(menu) || menu.edge === "left" || menu.edge === "right";
    const bounds = GridPlacement.bounds(menu.layout.modules);
    return GridPlacement.fitModuleScale(scale, wide ? bounds.cols : bounds.rows, OverlayConfig.cardUnitOn(screen.width, screen.height), menu.layout.grid.fine, (wide ? screen.width : screen.height) - PopoutsConfig.padding * 2);
  }

  // The px between a menu's cards: the layout's gap drawn at the menu's
  // zoom (GridPlacement.gapOf), so the menu is an overlay page's grid
  function gapOf(menu, screen) {
    return GridPlacement.gapOf(root.zoomOf(menu, screen));
  }

  // What a menu's modules are drawn at: its Module size (scaleOf,
  // GridPlacement.zoomOf), so it scales their text and controls with its
  // cards, while the screen only changes how big the cards are
  function zoomOf(menu, screen) {
    return GridPlacement.zoomOf(root.scaleOf(menu, screen));
  }

  // The menu's modules' grid along its edge, unstretched, at card size
  // `unit`, `gap` px between cards
  function gridLengthOf(menu, vertical, unit, gap) {
    const sizes = GridPlacement.trackSizes(GridPlacement.bounds(menu.layout.modules), unit, null, gap);
    return vertical ? sizes.height : sizes.width;
  }
}
