pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Image element: a path or URL (the widget's image field
// by default), cropped or fitted to its box with rounded corners, or a
// circle. A round picture sits in the box by Across and Down;
// the others fill it.
CustomElementBase {
  id: root

  readonly property string path: root.text("image", "image")
  readonly property string source: root.imageUrl(root.path)

  Thumbnail {
    x: root.placeX(width)
    y: root.placeY(height)
    width: root.options.round ? Math.min(root.width, root.height) : root.width
    height: root.options.round ? width : root.height
    radius: root.options.round ? width / 2 : Style.radius
    source: root.source
    fillMode: root.options.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
    cache: false
  }
}
