pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// An attached image's thumbnail; `removable` adds a remove button
Rectangle {
  id: root

  // { path, mime, name }
  property var attachment: ({})
  property int size: Widget.px(56)
  property bool removable: false

  signal removed

  implicitWidth: root.size
  implicitHeight: root.size
  radius: Widget.radius / 2
  color: Theme.backgroundHighlight
  border.color: Theme.border
  border.width: 1
  clip: true

  Image {
    anchors.fill: parent
    anchors.margins: 1
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
    textColor: Theme.foregroundAlt
  }

  HoverHandler {
    id: hover
  }

  Rectangle {
    visible: root.removable && hover.hovered
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Widget.spacing
    width: Widget.smallHeight
    height: Widget.smallHeight
    radius: width / 2
    color: Qt.alpha(Theme.background, 0.85)

    StyledIcon {
      anchors.centerIn: parent
      text: "close"
      textSize: Appearance.fontSizeBy(-3)
    }

    TapHandler {
      onTapped: root.removed()
    }

    HoverHandler {
      cursorShape: Qt.PointingHandCursor
    }
  }
}
