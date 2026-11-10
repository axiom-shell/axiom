pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable
import qs.components.surfaces.menu

// A menu's modules in another menu's submenu (SubPopout, loaded as
// "Submenu/MenuSubmenu" by a Submenu module): its MenuBody, at the card
// size of the menu it opens from, scaled by this one's moduleScale. Its
// modules' host is this menu's, marked `submenu`.
Item {
  id: root

  required property var wrapper
  required property string menuId
  // The menu it opens from: its screen sizes the cards
  property string parentId: ""

  readonly property var menu: MenusConfig.menuById(root.menuId)
  readonly property var parentMenu: MenusConfig.menuById(root.parentId)
  readonly property bool empty: (root.menu?.layout?.modules ?? []).length === 0

  implicitWidth: root.empty ? emptyText.implicitWidth : body.implicitWidth
  implicitHeight: root.empty ? emptyText.implicitHeight : body.implicitHeight

  // What keeps the submenu up (SubPopout's dismiss logic)
  property alias hovered: hoverHandler.hovered
  HoverHandler {
    id: hoverHandler
  }

  Loader {
    id: body
    anchors.fill: parent
    active: !root.empty
    sourceComponent: MenuBody {
      menu: root.menu
      vertical: true
      submenu: true
      screen: root.parentMenu ? MenusConfig.screenFor(root.parentMenu) : null
      // Kept on the screen: past its room, it scrolls (SubPopout.maxContentHeight)
      maxLength: root.wrapper?.maxContentHeight ?? 0
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
