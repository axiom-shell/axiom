pragma ComponentBehavior: Bound
import QtQuick

// A value that follows `source` only while its host is closed: what
// changes a popout's window layer or namespace (Hyprland reads a layer
// rule only as a surface maps), so an open popout never moves or restacks.
// It opens as it should next time.
QtObject {
  id: root

  property var source
  // Whether the host is closed (not occupied)
  property bool closed: true
  property var value

  function _follow() {
    if (root.closed)
      root.value = root.source;
  }
  onSourceChanged: root._follow()
  onClosedChanged: root._follow()
  Component.onCompleted: root._follow()
}
