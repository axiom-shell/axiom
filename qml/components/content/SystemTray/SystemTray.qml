pragma ComponentBehavior: Bound
import QtQuick

import qs.components.content.parts

// A tray item's menu. Its submenus open beside it, in its popout's
// submenu (SubPopout, BarPopouts.submenu).
Item {
  id: root

  required property var wrapper

  property var trayItem: wrapper.currentData?.trayItem

  readonly property bool openToLeft: root.wrapper?.openToLeft ?? false

  // (an open submenu keeps it up too: the wrapper's childOpen)
  readonly property bool hovered: hoverHandler.hovered
  readonly property var submenu: root.wrapper.submenu

  implicitWidth: menuList.implicitWidth
  implicitHeight: menuList.implicitHeight

  // The host keeps the popout hidden until the menu has arrived
  readonly property bool contentReady: menuList.contentReady

  HoverHandler {
    id: hoverHandler
  }

  TrayMenuList {
    id: menuList
    anchors.fill: parent
    menu: root.trayItem?.menu
    openToLeft: root.openToLeft

    onSubmenuRequested: function (itemDelegate) {
      // Beside this popout's box, level with the item
      root.submenu.safeOpenPopout(root.wrapper.window, {
        name: "parts/TraySubmenu",
        menuItem: itemDelegate.menuItem,
        anchorItem: itemDelegate
      });
    }

    // An entry picked closes the menu, as a submenu's does (TraySubmenu)
    onItemClicked: root.wrapper.requestDismiss()

    // Close any open submenu when hovering an item without one
    onPlainItemHovered: root.submenu.hide()
  }
}
