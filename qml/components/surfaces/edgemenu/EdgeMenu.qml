pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods

// One edge menu from EdgeMenusConfig, on its screen, at its placement. Only the
// host in use is created (FreeMenuPlace.hosts): a popped-out edge menu
// shows in the free host, its edge host kept until the free one has
// shown, so the box hands over with no gap. The free host is one per
// screen; only the one on the screen the menu opened on shows it
// (FreeMenuPlace.openedOn, decided as it opens: its widget's screen, the
// cursor's for `at: cursor`, else its `screen`), so an open menu never
// moves to another screen.
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
  Component.onCompleted: {
    root._follow();
    if (root._placing)
      root._locate();
  }
  readonly property ShellScreen screen: root.menu ? EdgeMenusConfig.screenFor(root.menu) : null
  // An open free menu that went to its `screen` setting (no widget, not
  // at the cursor) follows it: set differently (Layouts' preview), it
  // shows there
  onScreenChanged: {
    if (root._placing && !EdgeMenuManager.anchors[root.menuId] && root.menu.freeAnchor.at !== "cursor")
      root._locate();
  }
  // Popped out (EdgeMenuManager.popOut), and once the free host has shown
  // it (kept until it docks: a fullscreen window hiding the free host
  // never brings the edge one back)
  readonly property bool poppedOut: EdgeMenuManager.isPoppedOut(root.menuId)
  property bool _handedOver: false
  onPoppedOutChanged: {
    if (!root.poppedOut)
      root._handedOver = false;
  }
  // The free hosts (one per screen, a var: FreeHosts' members)
  readonly property var _freeHosts: freeLoader.item
  readonly property bool _freeShown: root._freeHosts?.boxShown ?? false
  on_FreeShownChanged: {
    if (root._freeShown && root.poppedOut)
      root._handedOver = true;
  }
  readonly property var hosts: FreeMenuPlace.hosts(root.menu?.placement ?? "", root.poppedOut, root._handedOver)

  // ---- The free host's screen ----
  // Where a free menu opened (FreeMenuPlace.openedOn), "" while closed or
  // while the cursor is asked for; and the cursor in global px (`at:
  // cursor`), for the box's place
  property string _openedOn: ""
  property var _cursor: null
  // Open and free: also a menu turned free while open (its placement
  // changed in Layouts while previewed), which no free host showed yet
  readonly property bool _placing: EdgeMenuManager.isOpen(root.menuId) && EdgeMenusConfig.isFree(root.menu)
  on_PlacingChanged: {
    if (root._placing)
      root._locate();
    else
      root._openedOn = "";
  }
  // Decides where it opens, as it opens: its widget's screen
  // (PopoutAnchor.screenRect), else the cursor's (asked for first), else
  // its configured one
  function _locate() {
    const rect = EdgeMenuManager.anchors[root.menuId]?.screenRect?.() ?? null;
    const decide = cursor => {
      root._cursor = cursor;
      root._openedOn = FreeMenuPlace.openedOn({
        "opener": rect?.screen?.name ?? "",
        "at": root.menu.freeAnchor.at,
        "cursor": cursor,
        "screens": General.outputs.map(s => ({
              "name": s.name,
              "x": s.x,
              "y": s.y,
              "width": s.width,
              "height": s.height
            })),
        "configured": root.screen?.name ?? ""
      });
    };
    root._openedOn = "";
    if (rect || root.menu.freeAnchor.at !== "cursor") {
      decide(null);
      return;
    }
    CompositorManager.withCursorPos(pos => {
      if (root._placing && root._openedOn === "")
        decide(pos ?? null);
    });
  }
  // The screen whose free host shows it, "" for none yet
  readonly property string freeScreen: FreeMenuPlace.shownOn({
    "popOut": EdgeMenuManager.poppedOut[root.menuId] ?? null,
    "opened": root._openedOn,
    "screens": General.outputs.map(s => s.name),
    "configured": root.screen?.name ?? ""
  })

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

  // A free host on every screen, built up front (where layers stack by
  // map order each keeps its place: FreeMenu's LayerSlot is held)
  LazyLoader {
    id: freeLoader
    active: !!root._live && !!root.screen && root.hosts.free

    Scope {
      id: freeHosts
      // Its box drawn on some screen (instances is a list object, not a
      // JS Array)
      readonly property bool boxShown: Array.prototype.some.call(freeVariants.instances, host => host?.boxShown === true)

      Variants {
        id: freeVariants
        model: General.outputs

        delegate: FreeMenu {
          required property ShellScreen modelData
          menu: root.menu
          screen: modelData
          shows: root.freeScreen !== "" && root.freeScreen === modelData.name
          cursorAt: root._cursor
        }
      }
    }
  }
}
