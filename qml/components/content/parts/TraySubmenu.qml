pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
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

  // Read through a var: QsWindow.window is typed QObject
  readonly property var _window: root.QsWindow.window

  // Children arrive over DBus; the wrapper waits for them (see TrayMenuList)
  readonly property bool contentReady: menuList.contentReady

  HoverHandler {
    id: hoverHandler
  }

  TrayMenuList {
    id: menuList
    anchors.fill: parent
    menu: root.menuItem
    maxWidth: (root._window?.screen?.width ?? 2000) * 0.3 // fixed px: a stand-in screen width
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
