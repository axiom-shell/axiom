pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets

import qs.config
import qs.components.reusable

// A notification's picture: its image (rounded, cropped) when it has one,
// else the app's icon (the notification's own, else its desktop entry's),
// else a bell. `badge` puts the app icon in a corner of an image.
Item {
  id: root

  property string appIcon: ""
  property string desktopEntry: ""
  property string image: ""
  property int size: Widget.px(32)
  property real radius: Widget.radius
  property bool badge: false

  // An icon name, a path or a URL, resolved to a source ("" if none)
  function iconSource(icon) {
    if (!icon)
      return "";
    if (icon.startsWith("/"))
      return "file://" + icon;
    if (icon.includes("://"))
      return icon;
    return Quickshell.iconPath(icon, true);
  }

  readonly property string appIconSource: {
    const own = iconSource(root.appIcon);
    if (own !== "")
      return own;
    const entry = root.desktopEntry !== "" ? DesktopEntries.byId(root.desktopEntry) : null;
    return entry ? iconSource(entry.icon) : "";
  }
  readonly property bool showImage: root.image !== "" && picture.status !== Image.Error

  implicitWidth: size
  implicitHeight: size

  ClippingRectangle {
    anchors.fill: parent
    visible: root.showImage
    radius: root.radius
    color: "transparent"

    Image {
      id: picture
      anchors.fill: parent
      source: root.image
      sourceSize: Qt.size(root.size * 2, root.size * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
  }

  Image {
    id: icon
    visible: !root.showImage && root.appIconSource !== "" && status !== Image.Error
    anchors.fill: parent
    source: root.showImage ? "" : root.appIconSource
    sourceSize: Qt.size(root.size * 2, root.size * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
  }

  StyledIcon {
    visible: !root.showImage && !icon.visible
    anchors.centerIn: parent
    text: "notifications"
    textColor: Theme.accent
    textSize: root.size * 0.8
  }

  Image {
    visible: root.badge && root.showImage && root.appIconSource !== ""
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: -2
    width: root.size * 0.42
    height: width
    source: visible ? root.appIconSource : ""
    sourceSize: Qt.size(width * 2, height * 2)
    asynchronous: true
  }
}
