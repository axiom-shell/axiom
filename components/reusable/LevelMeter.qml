pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A level shown, not set: StyledSlider's trough and fill without the
// handle, `share` (0-1) of the way along, filling up when `vertical`.
// Centred across its box, `thickness` thick. The bar's custom widgets and
// a custom widget's Bar element draw it; a bar sets its own sizes.
Item {
  id: root

  property real share: 0
  property bool vertical: false
  property real thickness: Widget.px(6)
  property color trackColor: Theme.backgroundHighlight
  property color fillColor: Theme.accent

  readonly property real _share: Math.max(0, Math.min(1, root.share))

  Rectangle {
    id: track
    anchors.centerIn: parent
    width: root.vertical ? root.thickness : root.width
    height: root.vertical ? root.height : root.thickness
    radius: root.thickness / 2
    color: root.trackColor

    Rectangle {
      // Never shorter than its rounded ends while there's anything to show
      readonly property real length: root._share > 0 ? Math.max(root.thickness, (root.vertical ? track.height : track.width) * root._share) : 0
      x: 0
      y: root.vertical ? track.height - height : 0
      width: root.vertical ? track.width : length
      height: root.vertical ? length : track.height
      radius: track.radius
      color: root.fillColor

      Glide on width {}
      Glide on height {}
    }
  }
}
