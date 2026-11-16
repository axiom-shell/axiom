pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components.reusable

// An attached image's thumbnail, cut to the rounded border; `removable`
// adds a remove button
ClippingRectangle {
  id: root

  // { path, mime, name }
  property var attachment: ({})
  property int size: Widget.px(56)
  property bool removable: false

  signal removed

  implicitWidth: root.size
  implicitHeight: root.size
  radius: Widget.radius / 2
  color: Style.surfaceHighest
  border.color: Style.borderSubtle
  border.width: Style.hairline

  // Inside the border: the content item is inset by its width
  Image {
    anchors.fill: parent
    source: root.attachment?.path ? "file://" + root.attachment.path : ""
    sourceSize.width: root.size * 2
    sourceSize.height: root.size * 2
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    // A deleted file
    onStatusChanged: missing.visible = status === Image.Error
  }

  StyledIcon {
    id: missing
    visible: false
    anchors.centerIn: parent
    text: "broken_image"
    textColor: Style.inkHighest.icon
  }

  HoverHandler {
    id: hover
  }

  StyledIconButton {
    visible: root.removable && hover.hovered
    kind: "tonal"
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Widget.spacing
    // Never under what its glyph needs
    size: Style.minHit(Style.iconXs)
    borderRadius: size / 2
    iconText: "close"
    iconSize: Style.iconXs
    onClicked: root.removed()
  }
}
