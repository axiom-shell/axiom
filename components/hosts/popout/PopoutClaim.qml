pragma ComponentBehavior: Bound
import QtQuick

import qs.services.ui

// A popout host's place in PopoutManager: registered while it `wants` to
// show and has a footprint (rects in screen px), released when it stops.
// The host shows only once `granted`; it closes on `evicted` or `refused`
// (a higher popout covers it), and a resident hides while `yielded` and
// comes back by itself.
QtObject {
  id: root

  // Unique per popout: "bar:<id>", "osd:<id>:<screen>", "menu:<id>", …
  required property string key
  // "dock" | "osd" | "bar" | "menu" | "launcher" | "submenu"
  required property string kind
  property string screen: ""
  // A Bar.edgeName, or "" for one floating free of the edges
  property string edge: ""
  property string barId: ""
  // A submenu's parent's key
  property string parentKey: ""
  // Held open by the user: ranks lowest
  property bool pinned: false
  // Gives way and comes back rather than closing
  property bool resident: false
  // Placed and wanting to show
  property bool wanted: false
  property var footprint: []

  readonly property bool granted: root._state === "open"
  readonly property bool yielded: root._state === "yielded"
  // Granted, or closing after it was: the host's pill draws back only
  // once its box has slid away, though the claim goes as the close starts
  // (`occupied`, `closing`: the host's)
  property bool occupied: false
  property bool closing: false
  readonly property bool held: root.granted || (root.closing && root._wasGranted)
  property bool _wasGranted: false
  onGrantedChanged: {
    if (root.granted)
      root._wasGranted = true;
  }
  onOccupiedChanged: {
    if (!root.occupied)
      root._wasGranted = false;
  }
  // Set by PopoutManager: "" | "open" | "yielded"
  property string _state: ""

  // Covered by a higher (or, opening later, an equal) popout: close
  signal evicted
  // Asked to show under a higher one: don't open
  signal refused

  // Whether it has a footprint at all, followed by hand: a granted popout
  // can change its own footprint (a pill bar it joins stretching under
  // it, PillBarJoin), which read in a binding here looped back into it
  property bool _placed: false
  onFootprintChanged: root._placed = (root.footprint?.length ?? 0) > 0
  Component.onCompleted: root._placed = (root.footprint?.length ?? 0) > 0
  readonly property bool _ready: root.wanted && root._placed
  on_ReadyChanged: root._sync()
  function _sync() {
    if (root._ready && root._state === "")
      PopoutManager.claim(root);
    else if (!root._ready && root._state !== "")
      PopoutManager.release(root);
  }
  // Moved, resized, pinned or let go while registered
  readonly property var _shape: [root.footprint, root.pinned, root.resident, root.screen]
  on_ShapeChanged: {
    if (root._ready && root._state !== "")
      PopoutManager.update(root);
  }
  Component.onDestruction: PopoutManager.release(root)
}
