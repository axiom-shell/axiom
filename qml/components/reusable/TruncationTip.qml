pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// The full text of an elided label, as a tooltip while the pointer is over
// its host: built only while `hovered` and the `target` text is truncated.
LazyLoader {
  id: root

  // -- Public API --
  // The elided text item the tip hangs off
  property var target: null
  property string text: ""
  // The host's hover state
  property bool hovered: false
  // Wrap the tip at this width, when set
  property real maxWidth: 0

  active: root.hovered && root.target?.truncated === true

  StyledToolTip {
    target: root.target
    text: root.text
    maxWidth: root.maxWidth
  }
}
