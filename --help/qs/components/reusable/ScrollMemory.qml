pragma ComponentBehavior: Bound
import QtQuick
import qs.services.ui

// Keeps where a Flickable was scrolled to (EditsManager, by `key`), so a
// panel rebuilt when the overlay reopens comes back to the same spot. Its
// content usually grows for a moment after it's built (cards loading,
// columns settling), so the spot is applied as soon as the content is long
// enough, until it settles. An empty key keeps nothing, starting at the
// top.
QtObject {
  id: root

  property Flickable flickable: null
  property string key: ""

  // Waiting to put the saved spot back
  property bool _restoring: false
  property real _target: 0

  // Stops a restore under way (a jump to somewhere else wins)
  function cancel() {
    root._restoring = false;
    root._settle.stop();
  }

  function _restore() {
    root.cancel();
    if (!root.flickable)
      return;
    // Nothing kept: start at the top (search results, after a category)
    if (root.key === "") {
      root.flickable.contentY = 0;
      return;
    }
    root._target = EditsManager.scrollOf(root.key);
    // Restoring before moving it, so the move isn't kept as the spot
    root._restoring = true;
    root.flickable.contentY = 0;
    if (root._target <= 0) {
      root._restoring = false;
      return;
    }
    root._apply();
    if (root._restoring)
      root._settle.restart();
  }

  function _apply() {
    const room = root.flickable.contentHeight - root.flickable.height;
    root.flickable.contentY = Math.max(0, Math.min(root._target, room));
    if (room >= root._target)
      root.cancel();
  }

  onKeyChanged: root._restore()
  onFlickableChanged: root._restore()
  Component.onCompleted: root._restore()

  // Gives up waiting once the content has stopped growing: a quiet spell
  // restarted by every growth, so a literal (an animation duration is 0
  // with motion off)
  property Timer _settle: Timer {
    interval: 300
    onTriggered: root._restoring = false
  }

  property Connections _watch: Connections {
    target: root.flickable
    function onContentHeightChanged() {
      if (!root._restoring)
        return;
      root._apply();
      if (root._restoring)
        root._settle.restart();
    }
    function onContentYChanged() {
      if (!root._restoring && root.key !== "")
        EditsManager.rememberScroll(root.key, root.flickable.contentY);
    }
    // The user scrolled while it was still restoring
    function onMovingChanged() {
      if (root.flickable.moving)
        root.cancel();
    }
  }
}
