pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.hosts.overlay

// An edge menu's modules in another menu's submenu (SubPopout, loaded as
// "Submenu/MenuSubmenu" by a Submenu module), on a grid at the card size of
// the menu it opens from, scaled by this one's moduleScale. Its modules'
// host is this menu's, marked `submenu`.
Item {
  id: root

  required property var wrapper
  required property string menuId
  // The menu it opens from: its screen sizes the cards
  property string parentId: ""

  readonly property var menu: EdgeMenusConfig.menuById(root.menuId)
  readonly property var parentMenu: EdgeMenusConfig.menuById(root.parentId)

  // Modules re-read only when they actually change (as EdgeMenuBody)
  readonly property string _modulesKey: JSON.stringify(root.menu?.layout?.modules ?? [])
  property var modules: []
  on_ModulesKeyChanged: root.modules = JSON.parse(root._modulesKey)
  Component.onCompleted: root.modules = JSON.parse(root._modulesKey)

  readonly property var host: ({
      "kind": "edgeMenu",
      "id": root.menuId,
      "bare": !(root.menu?.layout?.moduleBorders ?? true),
      "submenu": true
    })

  OverlayGrid {
    id: overlayGrid
    fixedUnit: root.menu ? EdgeMenuManager.cardUnitOf(root.menu, root.parentMenu ? EdgeMenusConfig.screenFor(root.parentMenu) : null) : 0
    gap: root.menu ? EdgeMenuManager.gapOf(root.menu) : OverlayConfig.cardSpacing
  }

  readonly property bool empty: root.modules.length === 0

  implicitWidth: root.empty ? emptyText.implicitWidth : moduleGrid.implicitWidth
  // Kept on the screen: past its room, it scrolls (SubPopout.maxContentHeight)
  implicitHeight: root.empty ? emptyText.implicitHeight : Math.min(moduleGrid.implicitHeight, root.wrapper?.maxContentHeight ?? moduleGrid.implicitHeight)

  // What keeps the submenu up (SubPopout's dismiss logic)
  property alias hovered: hoverHandler.hovered
  HoverHandler {
    id: hoverHandler
  }

  Flickable {
    anchors.fill: parent
    visible: !root.empty
    contentWidth: moduleGrid.implicitWidth
    contentHeight: moduleGrid.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: moduleGrid.implicitHeight > root.height

    ModuleGrid {
      id: moduleGrid
      modules: root.modules
      grid: overlayGrid
      host: root.host
      zoom: root.menu ? EdgeMenuManager.zoomOf(root.menu) : 1
    }
  }

  StyledText {
    id: emptyText
    visible: root.empty
    text: root.menu ? I18n.tr("No modules in this menu yet") : I18n.tr("This menu is gone")
    textColor: Theme.accent
    opacity: 0.5
    padding: Widget.spacing
  }
}
