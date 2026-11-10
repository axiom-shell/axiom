pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout

// What the edge menu hosts (FloatingEdgeMenu, IntegratedEdgeMenu, FreeMenu) share:
// following MenuManager (opening and closing when it says, telling it
// when the menu closes by itself), being held open (pinned, or by the
// editor), and a reveal (MenuManager.reveal): held open until hovered,
// the cursor moved into it once shown (`warpRequested`; never into a free
// menu, which waits for the pointer to arrive). Also reports
// where the host's modules can sit (`frame`, MenuManager.frames).
QtObject {
  id: root

  required property PopoutWrapperBase host
  required property var menu
  required property ShellScreen screen
  // The host's window: a grab partner, and what must be mapped to warp
  required property var window
  // Its hover strip, also a grab partner: hovering it opens the menu while
  // the overlay holds the grab (none for a free menu, which has no edge)
  property var triggerWindow: null

  // Where the host's modules can sit on its screen (MenuManager.frames)
  property var frame: null

  // The cursor should move into the menu (it's being revealed and shown)
  signal warpRequested
  // Whether a reveal moves the cursor into it: not a free menu's
  // (FreeMenu), opened by a bind or IPC with the pointer left where it is
  property bool warps: true

  readonly property string menuId: root.menu.id
  // Pinned, or held open by the editor
  readonly property bool held: MenuManager.isHeld(root.menuId)
  // Whether this host shows the menu at all: a free menu has a host on
  // every screen, and only the one it opened on shows it (MenuHosts)
  property bool shows: true
  readonly property bool wanted: MenuManager.openMenus[root.menuId] === true && root.shows
  readonly property bool revealing: MenuManager.revealing[root.menuId] === true
  // Closes when the pointer leaves, unless held or being revealed
  readonly property bool autoDismiss: root.menu.close.onLeave && !root.held && !root.revealing

  // The hover strip's length, from config alone, so it's the same open
  // or closed: its box's, its modules' grid with `pad` on both ends, no
  // longer than `room` (the box's room along the edge), which a
  // whole-edge menu takes
  function triggerLength(vertical, pad, room) {
    if (GridPlacement.menuFillsEdge(root.menu))
      return room;
    return Math.min(room, MenusConfig.gridLengthOf(root.menu, vertical, MenusConfig.cardUnitOf(root.menu), MenusConfig.gapOf(root.menu)) + pad * 2);
  }

  function _sync() {
    if (root.wanted && !root.host.isOpen)
      root.host.show({
        "anchorItem": MenuManager.anchors[root.menuId] ?? null,
        "claimKind": MenuManager.claimKinds[root.menuId] ?? "menu"
      });
    else if (!root.wanted)
      root.host.hide();
  }
  onWantedChanged: root._sync()

  property Connections _host: Connections {
    target: root.host

    // The host's own autoDismiss (bound to this one's) once it has
    // changed: this one's change can reach a handler here before the
    // host's binding, which then restarted the countdown of a menu just
    // held (a pinned free menu closed by a reload)
    function onAutoDismissChanged() {
      root.host.updateDismissTimer();
    }

    function onIsOpenChanged() {
      if (!root.host.isOpen)
        MenuManager.revealDone(root.menuId);
      if (!root.host.isOpen && root.wanted && !root.host.hasPendingOpen)
        MenuManager.close(root.menuId);
      else if (root.host.isOpen && !root.wanted)
        MenuManager.open(root.menuId, null);
    }

    function onContentHoveredChanged() {
      if (root.host.contentHovered)
        MenuManager.revealDone(root.menuId);
    }
  }

  property Timer _warp: Timer {
    interval: 150
    running: root.warps && root.revealing && root.host.isOpen && root.window.visible
    onTriggered: root.warpRequested()
  }

  // The id the frame was reported under: a renamed menu drops the old one
  property string _frameId: ""
  function _publishFrame() {
    if (root._frameId !== root.menuId)
      MenuManager.clearFrame(root._frameId, root.screen?.name ?? "");
    root._frameId = root.menuId;
    if (root.frame)
      MenuManager.setFrame(root._frameId, root.frame);
  }
  onFrameChanged: root._publishFrame()
  onMenuIdChanged: root._publishFrame()

  Component.onCompleted: {
    SurfaceManager.registerGrabPartner(root.window, root.screen?.name ?? "");
    if (root.triggerWindow)
      SurfaceManager.registerGrabPartner(root.triggerWindow, root.screen?.name ?? "");
    Qt.callLater(root._sync);
    root._publishFrame();
  }
  Component.onDestruction: {
    SurfaceManager.unregisterGrabPartner(root.window);
    if (root.triggerWindow)
      SurfaceManager.unregisterGrabPartner(root.triggerWindow);
    MenuManager.clearFrame(root._frameId, root.screen?.name ?? "");
  }
}
