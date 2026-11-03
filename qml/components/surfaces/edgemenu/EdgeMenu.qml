pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config

// One edge menu from EdgeMenusConfig, on its screen, in its mode. Only the
// host in use is created.
Scope {
  id: root

  required property string menuId
  readonly property var _live: EdgeMenusConfig.menuById(root.menuId)
  // The last entry seen, so the hosts never see it null while they go
  property var menu: null
  function _follow() {
    if (root._live)
      root.menu = root._live;
  }
  on_LiveChanged: root._follow()
  Component.onCompleted: root._follow()
  readonly property ShellScreen screen: root.menu ? EdgeMenusConfig.screenFor(root.menu) : null
  readonly property bool integrated: root.menu?.mode === "integrated"
  // A submenu menu has no host of its own (EdgeMenusConfig.isSubmenu)
  readonly property bool floating: root.menu?.mode === "floating"

  LazyLoader {
    active: !!root._live && !!root.screen && root.floating

    FloatingEdgeMenu {
      menu: root.menu
      screen: root.screen
    }
  }

  LazyLoader {
    active: !!root._live && !!root.screen && root.integrated

    IntegratedEdgeMenu {
      menu: root.menu
      screen: root.screen
    }
  }
}
