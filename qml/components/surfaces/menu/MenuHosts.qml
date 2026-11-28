pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout

// One menu from MenusConfig, on its screen, at its placement. The
// edge and strip hosts are created only in use (FreeMenuPlace.hosts); a
// free menu's free hosts, and those of an edge menu that can pop out
// (MenusConfig.canPopOut), are built up front and stay (their held windows
// keep their place in map order), showing nothing until used
// (`freeScreen` ""). A popped-out edge menu shows in the free host, its
// edge host kept until the free one has shown, so the box hands over with
// no gap. The free host is one per
// screen; only the one on the screen the menu opened on shows it
// (FreeMenuPlace.openedOn, decided as it opens: its widget's screen, the
// cursor's for `at: cursor`, else its `screen`), so an open menu never
// moves to another screen. A free menu opened as a bar widget's popout
// shows in the edge host instead, out of that widget's bar edge on its
// screen (`_openerRect`); the free host's box goes first when it was open
// there, and it moves to another widget the same way (the box out at the
// first, in at the next).
Scope {
  id: root

  required property string menuId
  readonly property var _live: MenusConfig.menuById(root.menuId)
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
  readonly property ShellScreen screen: root.menu ? MenusConfig.screenFor(root.menu) : null
  // An open free menu that went to its `screen` setting (no widget, not
  // at the cursor) follows it: set differently (Layouts' preview), it
  // shows there
  onScreenChanged: {
    if (root._placing && !MenuManager.anchors[root.menuId] && root.menu.freeAnchor.at !== "cursor")
      root._locate();
  }
  // Popped out (MenuManager.popOut), and once the free host has shown
  // it (kept until it docks: a fullscreen window hiding the free host
  // never brings the edge one back)
  readonly property bool poppedOut: MenuManager.isPoppedOut(root.menuId)
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
  // At a widget the edge host waits for the free host to finish closing:
  // `hosts` reads _freeKept, set a tick after _freeOccupied, so the edge
  // loader never changes inside the free host's own occupied change
  readonly property bool _freeOccupied: root._freeHosts?.occupied ?? false
  property bool _freeKept: false
  on_FreeOccupiedChanged: Qt.callLater(() => root._freeKept = root._freeOccupied)
  // -- At a bar widget --
  // The widget a free menu is open at as its popout (PopoutAnchor), else
  // null; the one the edge host's box comes from, which follows it only
  // while that box is closed (the box in place never moves)
  readonly property var _wantedAnchor: MenuManager.widgetAnchor(root.menuId)
  readonly property var _edgeHost: edgeLoader.item
  // Open, closing, or its pill still drawing back after its box has gone.
  // Unloaded sooner, its pill's stretch went in one frame
  readonly property bool _edgeOccupied: (root._edgeHost?.occupied || root._edgeHost?.stretchDrawn) ?? false
  // The latch's change unloads the edge host, so it must never run inside
  // that host's own occupied change: kept a tick later, as _freeKept
  property bool _edgeKept: false
  on_EdgeOccupiedChanged: Qt.callLater(() => root._edgeKept = root._edgeOccupied)
  property ClosedLatch _openerAnchor: ClosedLatch {
    source: root._wantedAnchor
    closed: !root._edgeKept
    // The widget's place as it opens (PopoutAnchor.screenRect: its bar's
    // edge and screen with it), taken here, not bound: cleared first, so a
    // new screen gets a new window; null once the widget is gone
    onValueChanged: {
      root._openerRect = null;
      root._openerGone = false;
      const anchor = value;
      if (anchor)
        Qt.callLater(() => {
          if (anchor !== root._openerAnchor.value)
            return;
          root._openerRect = anchor.screenRect?.() ?? null;
          root._openerGone = root._openerRect === null;
        });
    }
  }
  property var _openerRect: null
  // The widget's place came back null: the menu shows in its own window
  property bool _openerGone: false
  readonly property bool _atWidget: root._openerRect !== null || (root._wantedAnchor !== null && !root._openerGone)
  // The edge host shows it while it is still the widget wanted
  readonly property bool _edgeShows: root._openerRect === null || root._wantedAnchor === root._openerAnchor.value
  readonly property var hosts: FreeMenuPlace.hosts(root.menu?.placement ?? "", root.poppedOut, root.poppedOut ? root._handedOver : root._freeKept, root._atWidget, root._openerRect !== null, MenusConfig.canPopOut(root.menu))

  // -- The free host's screen --
  // Where a free menu opened (FreeMenuPlace.openedOn), "" while closed or
  // while the cursor is asked for; and the cursor in global px (`at:
  // cursor`), for the box's place
  property string _openedOn: ""
  property var _cursor: null
  // Open and free: also a menu turned free while open (its placement
  // changed in Layouts while previewed), which no free host showed yet
  readonly property bool _placing: MenuManager.isOpen(root.menuId) && MenusConfig.isFree(root.menu)
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
    const rect = MenuManager.anchors[root.menuId]?.screenRect?.() ?? null;
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
    "popOut": MenuManager.poppedOut[root.menuId] ?? null,
    "opened": root._openedOn,
    "atWidget": root._atWidget,
    "screens": General.outputs.map(s => s.name),
    "configured": root.screen?.name ?? ""
  })

  // (a free menu's edge host waits for its widget's place: its screen)
  LazyLoader {
    id: edgeLoader
    active: !!root._live && !!root.screen && root.hosts.edge

    FloatingEdgeMenu {
      menu: root.menu
      screen: root._openerRect?.screen ?? root.screen
      openerRect: root._openerRect
      shows: root._edgeShows
    }
  }

  LazyLoader {
    active: !!root._live && !!root.screen && root.hosts.strip

    IntegratedEdgeMenu {
      menu: root.menu
      screen: root.screen
    }
  }

  // A free host on every screen, built up front (each window's
  // LayerSlot is held, so it keeps its place in map order)
  LazyLoader {
    id: freeLoader
    active: !!root._live && !!root.screen && root.hosts.free

    Scope {
      id: freeHosts
      // Its box drawn on some screen (instances is a list object, not a
      // JS Array)
      readonly property bool boxShown: Array.prototype.some.call(freeVariants.instances, host => host?.boxShown === true)
      // Some free host is occupied (open or closing)
      readonly property bool occupied: Array.prototype.some.call(freeVariants.instances, host => host?.occupied === true)

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
