pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A tray submenu's content, in its popout's submenu (SubPopout, loaded as
// "parts/TraySubmenu")
Item {
  id: root
  required property var wrapper
  required property var menuItem

  implicitWidth: menuList.implicitWidth
  implicitHeight: menuList.implicitHeight

  // Exposes our hover state to the wrapper's (SubPopout)
  // centralized dismiss logic — timing and dismissal live there.
  property alias hovered: hoverHandler.hovered

  // Children arrive over DBus; the wrapper waits for them (see TrayMenuList)
  readonly property bool contentReady: menuList.contentReady

  HoverHandler {
    id: hoverHandler
  }

  TrayMenuList {
    id: menuList
    anchors.fill: parent
    menu: root.menuItem
    emptyText: I18n.tr("No submenu items")

    onItemClicked: root.wrapper.requestDismiss()

    // A nested submenu drills down: it replaces this one in the same place
    // (same anchor window and attach rect), since submenus go one level
    // deep
    onSubmenuRequested: function (itemDelegate) {
      root.wrapper.safeOpenPopout(root.wrapper.currentAnchor, Object.assign({}, root.wrapper.currentData, {
        menuItem: itemDelegate.menuItem
      }));
    }
  }
}
