pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.hosts.overlay

// An edge menu's modules on a grid of quarter cards, as on a Custom overlay
// page, with its screen's overlay cards (EdgeMenusConfig.cardUnitOf). Taking
// its whole edge (`length: "edge"`, and an integrated menu always:
// GridPlacement.menuFillsEdge) the grid fits the edge exactly, its rows (or columns) growing or shrinking
// evenly to `maxLength` (scrolling only past half a unit); otherwise it's
// capped there and scrolls past that.
Item {
  id: root

  required property var menu
  required property bool vertical
  // Room along the edge
  property real maxLength: 0

  // Modules re-read only when they actually change, so an unrelated config
  // save doesn't rebuild every module. As the menu lays them out
  // (GridPlacement.menuModules: an integrated menu's from its edge's start)
  readonly property string _modulesKey: JSON.stringify(GridPlacement.menuModules(root.menu))
  property var modules: []
  on_ModulesKeyChanged: root.modules = JSON.parse(root._modulesKey)
  Component.onCompleted: root.modules = JSON.parse(root._modulesKey)

  // `bare`: the menu hides its modules' card boxes (moduleBorders off)
  readonly property var host: ({
      "kind": "edgeMenu",
      "id": root.menu.id,
      "bare": !root.menu.layout.moduleBorders
    })

  OverlayGrid {
    id: overlayGrid
    fixedUnit: EdgeMenusConfig.cardUnitOf(root.menu)
    gap: EdgeMenusConfig.gapOf(root.menu)
  }

  // Whether the menu takes its whole edge
  readonly property bool fillsEdge: GridPlacement.menuFillsEdge(root.menu)
  // As its modules are shown: grown ones included (ModuleGrid.places)
  readonly property var _natural: overlayGrid.sizes(moduleGrid.bounds, null)
  // Its height with every growing module at its most, so a floating top
  // or bottom menu's window has room for it from the start
  readonly property real maxGrownHeight: {
    const places = root.modules.map(module => module?.place ?? null);
    const most = GridPlacement.grown(places, root.modules.map(module => module?.properties?.grow ?? 0), moduleGrid.growTowards);
    return overlayGrid.sizes(GridPlacement.bounds(most.map(place => ({
          "place": place
        }))), null).height;
  }
  // Along the edge before stretching or the cap
  readonly property real naturalLength: root.vertical ? root._natural.height : root._natural.width
  readonly property var _stretch: root.fillsEdge && root.maxLength > 0 ? (root.vertical ? {
      "height": root.maxLength,
      "fit": true
    } : {
      "width": root.maxLength,
      "fit": true
    }) : null

  readonly property real contentLength: root.vertical ? moduleGrid.implicitHeight : moduleGrid.implicitWidth
  readonly property real length: root.maxLength > 0 ? Math.min(root.contentLength, root.maxLength) : root.contentLength

  // Escape closes the menu once it has the keyboard (both hosts take it
  // on demand, when clicked)
  focus: true
  Keys.onEscapePressed: EdgeMenuManager.close(root.menu.id)

  implicitWidth: root.vertical ? moduleGrid.implicitWidth : root.length
  implicitHeight: root.vertical ? root.length : moduleGrid.implicitHeight

  Flickable {
    anchors.fill: parent
    contentWidth: moduleGrid.implicitWidth
    contentHeight: moduleGrid.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: root.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
    interactive: root.contentLength > root.length

    ModuleGrid {
      id: moduleGrid
      modules: root.modules
      grid: overlayGrid
      stretch: root._stretch
      host: root.host
      zoom: EdgeMenusConfig.zoomOf(root.menu)
      // A bottom menu's edge is under its modules
      growTowards: root.menu.edge === "bottom" ? 1 : -1
    }
  }

  // The menu's pin (pinButton): in the corner away from its edge, at the
  // end, over the modules' corner
  readonly property bool pinned: EdgeMenuManager.isPinned(root.menu.id)
  StyledIconButton {
    visible: root.menu.pinButton
    z: 2
    width: Widget.height
    height: Widget.height
    padding: 0
    anchors.top: root.menu.edge === "top" ? undefined : parent.top
    anchors.bottom: root.menu.edge === "top" ? parent.bottom : undefined
    anchors.right: root.menu.edge === "right" ? undefined : parent.right
    anchors.left: root.menu.edge === "right" ? parent.left : undefined
    anchors.margins: Widget.spacing / 4
    iconText: "push_pin"
    iconColor: root.pinned ? Theme.background : Theme.foreground
    backgroundColor: root.pinned ? Theme.accent : Qt.alpha(Theme.background, 0.85)
    hoverColor: root.pinned ? Theme.accent : Theme.backgroundHighlight
    borderColor: Theme.border
    tooltipText: root.pinned ? I18n.tr("Unpin: close as usual") : I18n.tr("Pin: keep this menu open")
    onClicked: EdgeMenuManager.togglePinned(root.menu.id)
  }
}
