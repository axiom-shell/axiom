pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components.content.parts.custom

// A custom widget's Image element: a path or URL (the widget's image field
// by default), cropped or fitted to its box with rounded corners, or a
// circle.
CustomElementBase {
  id: root

  readonly property string path: root.text("image", "image")
  readonly property string source: root.path === "" ? "" : /^[a-z]+:\/\//.test(root.path) ? root.path : "file://" + Paths.expandHome(root.path)

  ClippingRectangle {
    anchors.centerIn: parent
    width: root.options.round ? Math.min(root.width, root.height) : root.width
    height: root.options.round ? width : root.height
    radius: root.options.round ? width / 2 : Widget.radius
    color: Theme.backgroundHighlight

    Image {
      anchors.fill: parent
      source: root.source
      fillMode: root.options.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }
  }
}
