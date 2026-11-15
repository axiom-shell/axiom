pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.config

// A picture in a rounded box on Style.surfaceHighest, decoded
// asynchronously at `decodeSize` and cropped (`fillMode`) to the box. The
// callers size it (and set `radius` to differ): a row's thumbnail, a custom
// widget's Image element and list tiles.
ClippingRectangle {
  id: root

  property string source: ""
  property int fillMode: Image.PreserveAspectCrop
  property bool cache: true
  // The size the image is decoded at; a 0 side keeps the picture's ratio
  property size decodeSize: Qt.size(width, height)

  radius: Widget.radius / 2
  color: Style.surfaceHighest

  Image {
    anchors.fill: parent
    source: root.source
    fillMode: root.fillMode
    asynchronous: true
    cache: root.cache
    sourceSize: root.decodeSize
  }
}
