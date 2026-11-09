pragma ComponentBehavior: Bound
import QtQuick

// An invisible pixel that flips for a few frames after burst(), so its
// window draws (and commits) again and the last frame shown is the right
// one. Hyprland sometimes keeps showing a layer's frame from before a
// change until something else makes it commit (a hover, the clock): a
// bar's stretch changing under an open popout, the blur window's shapes
// resizing.
Item {
  id: root

  property bool _flip: false

  function burst() {
    nudges.left = 6;
    nudges.restart();
  }

  width: 1
  height: 1

  Rectangle {
    anchors.fill: parent
    color: "#02000000"
    opacity: root._flip ? 0.5 : 0.4
  }

  Timer {
    id: nudges
    property int left: 0
    interval: 32
    onTriggered: {
      root._flip = !root._flip;
      if (--nudges.left > 0)
        nudges.restart();
    }
  }
}
