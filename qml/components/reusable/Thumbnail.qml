pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.config

// A picture in a rounded box on Style.surfaceHighest, decoded
// asynchronously at `decodeSize` and cropped (`fillMode`) to the box. The
// callers size it (and set `radius` to differ): a row's thumbnail, a custom
// widget's Image element and list tiles. `round` makes it a circle (an
// avatar); `placeholderIcon` is a faint glyph, fitted to the box, shown until
// the picture is ready.
ClippingRectangle {
  id: root

  property string source: ""
  property int fillMode: Image.PreserveAspectCrop
  property bool cache: true
  // The size the image is decoded at; a 0 side keeps the picture's ratio
  property size decodeSize: Qt.size(width, height)
  // A circle: the radius is half the shorter side
  property bool round: false
  // A Material Symbols name shown while the picture isn't loaded (none, or
  // failed, or empty source); empty shows nothing
  property string placeholderIcon: ""
  // The picture has loaded (a host hides the box until then)
  readonly property bool ready: image.status === Image.Ready

  radius: root.round ? Math.min(root.width, root.height) / 2 : Style.radiusInner
  color: Style.surfaceHighest

  StyledIcon {
    anchors.centerIn: parent
    visible: root.placeholderIcon !== "" && !root.ready
    text: root.placeholderIcon
    textSize: Math.max(Style.typeMicro, Math.round(Math.min(root.width, root.height) * 0.45)) // fitted: the box
    tone: "faint"
  }

  Image {
    id: image
    anchors.fill: parent
    source: root.source
    fillMode: root.fillMode
    asynchronous: true
    cache: root.cache
    sourceSize: root.decodeSize
  }
}
