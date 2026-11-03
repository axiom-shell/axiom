pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.config

// A track's cover, rounded, a new one fading in over the old once it has
// loaded; a note while `source` is empty (MediaManager.artSource). The
// Now Playing module's and the OSD's now playing card's.
Item {
  id: root

  property string source
  property real radius: Widget.radius

  ClippingRectangle {
    anchors.fill: parent
    radius: root.radius
    color: Theme.backgroundAlt
    CrossFade {
      anchors.fill: parent
      value: root.source
      delegate: Image {
        required property var value
        readonly property bool ready: status !== Image.Loading
        source: value
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }
    }
    StyledIcon {
      anchors.centerIn: parent
      visible: root.source === ""
      text: "music_note"
      textSize: Math.min(root.width, root.height) * 0.4
      opacity: 0.4
    }
  }
}
