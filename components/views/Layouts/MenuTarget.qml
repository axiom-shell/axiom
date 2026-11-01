pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
import qs.components.methods

// The layouts editor on an edge menu (OverlayManager.menus' selected menu):
// its modules against its screen, where the menu really sits on it, with
// the band along its edge and, on request, the other menus.
EditTarget {
  id: root

  readonly property var menu: OverlayManager.menus.selectedMenu()
  // A submenu menu has no edge: just its grid
  readonly property bool submenu: EdgeMenusConfig.isSubmenu(root.menu)
  readonly property bool vertical: root.menu?.edge === "left" || root.menu?.edge === "right"
  readonly property var screen: root.menu ? EdgeMenusConfig.screenFor(root.menu) : null
  readonly property real length: root.menu ? EdgeMenusConfig.lengthOf(root.menu, root.vertical, EdgeMenusConfig.cardUnitOf(root.menu), EdgeMenusConfig.gapOf(root.menu)) : 0
  readonly property real edgeLength: root.screen ? (root.vertical ? root.screen.height : root.screen.width) : 0
  // Where the menu's modules sit on its screen (OverlayManager.menus.placementOf)
  readonly property var place: root.menu ? OverlayManager.menus.placementOf(root.menu) : null
  readonly property bool tooLong: root.menu !== null && !GridPlacement.menuFillsEdge(root.menu) && root.edgeLength > 0 && root.length > root.edgeLength
  // Whether it has a place on its lattice (not taking its whole edge or
  // longer than it), the offsets that keep it there, and its offset among
  // them (a config's can be past them, kept on the lattice)
  readonly property bool onLattice: root.place !== null && root.place.cell !== null
  readonly property var offsetRange: root.onLattice ? GridPlacement.offsetRange(root.place.lattice, root.place.units) : null
  readonly property int offset: root.onLattice ? GridPlacement.offsetFor(root.place.lattice, root.place.cell, root.place.units) : 0

  editor: OverlayManager.menus.layout
  modules: root.menu ? root.menu.layout.modules : null
  icon: root.submenu ? "menu_open" : root.menu ? Utils.edgeArrow(root.menu.edge) : "side_navigation"
  title: root.menu ? OverlayManager.menus.menuLabel(root.menu, OverlayManager.menus.selectedMenuIndex) : I18n.tr("No edge menus")
  emptyText: I18n.tr("No edge menus yet: add one with New menu.")
  edge: root.menu && !root.submenu ? root.menu.edge : ""
  screenBox: root.editor.screenBox
  screenSize: root.screen && !root.submenu ? ({
      "width": root.screen.width,
      "height": root.screen.height
    }) : null
  reservedDepth: root.place ? GridPlacement.menuReservedDepth(root.place) : 0
  reservedLabel: root.place?.frame.reserves ? I18n.tr("Reserved while open") : I18n.tr("Bars and border")
  // The other enabled menus on its screen, in screen px
  ghosts: root.menu && OverlayManager.menus.showingOthers ? OverlayManager.menus.othersOn(OverlayManager.menus.selectedMenuIndex) : []
  fitText: {
    if (!root.menu)
      return "";
    if (root.submenu)
      return I18n.tr("Opens beside a floating menu, from its Submenu module");
    if (GridPlacement.menuFillsEdge(root.menu))
      return I18n.tr("Takes its whole edge");
    if (root.tooLong)
      return I18n.tr("Longer than its edge: it scrolls");
    return I18n.tr("{0} px along its edge", Math.round(root.length));
  }
  fitWarning: root.tooLong && !root.submenu
  nudgeText: {
    const range = root.offsetRange;
    if (!range)
      return "";
    const units = Math.abs(root.offset);
    if (root.offset === 0)
      return I18n.tr("Centred");
    if (root.offset === range.min)
      return root.vertical ? I18n.tr("At the top") : I18n.tr("At the left end");
    if (root.offset === range.max)
      return root.vertical ? I18n.tr("At the bottom") : I18n.tr("At the right end");
    if (root.vertical)
      return root.offset < 0 ? I18n.tr("{0} up from the centre", units) : I18n.tr("{0} down from the centre", units);
    return root.offset < 0 ? I18n.tr("{0} left of the centre", units) : I18n.tr("{0} right of the centre", units);
  }
  nudgeVertical: root.vertical
  canNudgeBack: root.onLattice && root.offset > root.offsetRange.min
  canNudgeForward: root.onLattice && root.offset < root.offsetRange.max
  canCentre: root.offset !== 0
  nudge: step => OverlayManager.menus.nudgeSelected(step)
  centre: () => OverlayManager.menus.centreSelected()
  gridOffset: root.menu ? root.menu.gridOffset : 0
  gridOffsetLimit: OverlayManager.menus.gridOffsetLimit(root.menu)
  setGridOffset: px => OverlayManager.menus.setGridOffset(px)
  // The lattice's cells along the edge, in units from the grid's origin
  latticeSpan: root.onLattice ? ({
      "from": root.place.lattice.first - root.place.cell,
      "to": root.place.lattice.last - root.place.cell
    }) : null
  editable: root.menu !== null
  notEditableHint: I18n.tr("Add a menu to put modules in it")
}
