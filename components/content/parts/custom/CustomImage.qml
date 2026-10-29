pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import Quickshell.Widgets

// A custom widget's Image element: a path or URL (the widget's image field
// by default), cropped to its box with rounded corners.
// options: fit (crop, fit), round (a circle)
CustomElementBase {
  id: root

  readonly property string path: root.text("image", "image")
  readonly property string source: root.path === "" ? "" : /^[a-z]+:\/\//.test(root.path) ? root.path : "file://" + Paths.expandHome(root.path)

  ClippingRectangle {
    anchors.centerIn: parent
    width: root.opt("round", false) ? Math.min(root.width, root.height) : root.width
    height: root.opt("round", false) ? width : root.height
    radius: root.opt("round", false) ? width / 2 : Widget.radius
    color: Theme.backgroundHighlight

    Image {
      anchors.fill: parent
      source: root.source
      fillMode: root.opt("fit", "crop") === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }
  }
}
