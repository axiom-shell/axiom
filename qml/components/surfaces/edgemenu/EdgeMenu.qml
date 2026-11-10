pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.ui
import qs.components.methods

// One edge menu from EdgeMenusConfig, on its screen, at its placement. Only the
// host in use is created (FreeMenuPlace.hosts): a popped-out edge menu
// shows in the free host, its edge host kept until the free one has
// shown, so the box hands over with no gap.
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
  // Popped out (EdgeMenuManager.popOut), and once the free host has shown
  // it (kept until it docks: a fullscreen window hiding the free host
  // never brings the edge one back)
  readonly property bool poppedOut: EdgeMenuManager.isPoppedOut(root.menuId)
  property bool _handedOver: false
  onPoppedOutChanged: {
    if (!root.poppedOut)
      root._handedOver = false;
  }
  readonly property bool _freeShown: (freeLoader.item as FreeMenu)?.boxShown ?? false
  on_FreeShownChanged: {
    if (root._freeShown && root.poppedOut)
      root._handedOver = true;
  }
  readonly property var hosts: FreeMenuPlace.hosts(root.menu?.placement ?? "", root.poppedOut, root._handedOver)

  LazyLoader {
    active: !!root._live && !!root.screen && root.hosts.edge

    FloatingEdgeMenu {
      menu: root.menu
      screen: root.screen
    }
  }

  LazyLoader {
    active: !!root._live && !!root.screen && root.hosts.strip

    IntegratedEdgeMenu {
      menu: root.menu
      screen: root.screen
    }
  }

  LazyLoader {
    id: freeLoader
    active: !!root._live && !!root.screen && root.hosts.free

    FreeMenu {
      menu: root.menu
      screen: root.screen
    }
  }
}
