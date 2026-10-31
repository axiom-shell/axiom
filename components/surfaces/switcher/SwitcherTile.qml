pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.surfaces.workspaces

// One window in the switcher: its capture (or app icon) over its title,
// highlighted while selected. A click picks it.
Item {
  id: root

  required property int index

  readonly property var windowData: WindowSwitcherManager.windows[root.index] ?? null
  readonly property bool selected: WindowSwitcherManager.index === root.index
  readonly property real pad: Widget.padding / 2
  // The capture's box: the window's shape fitted into 16:10
  readonly property real boxWidth: WindowSwitcherConfig.tileSize - root.pad * 2
  readonly property real boxHeight: root.boxWidth * 10 / 16
  readonly property real windowWidth: root.windowData?.w || 16 // fixed px: a shape (16:10) for a window with no size
  readonly property real windowHeight: root.windowData?.h || 10 // fixed px: a shape (16:10) for a window with no size
  readonly property real fit: Math.min(root.boxWidth / root.windowWidth, root.boxHeight / root.windowHeight)

  width: WindowSwitcherConfig.tileSize
  implicitHeight: root.boxHeight + Widget.spacing + title.implicitHeight + root.pad * 2

  Rectangle {
    anchors.fill: parent
    radius: Widget.radius
    color: root.selected ? Qt.alpha(Theme.accent, 0.14) : mouse.containsMouse ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)
    border.width: Appearance.borderWidth
    border.color: root.selected ? Theme.accent : "transparent"

    ColorGlide on color {}
  }

  Item {
    id: box
    x: root.pad
    y: root.pad
    width: root.boxWidth
    height: root.boxHeight

    WindowPreview {
      anchors.centerIn: parent
      visible: WindowSwitcherConfig.previews
      width: root.windowWidth * root.fit
      height: root.windowHeight * root.fit
      windowData: root.windowData
      capturing: WindowSwitcherConfig.previews && WindowSwitcherManager.shown
      live: root.selected
      showTitle: false
      radius: Widget.radius
    }

    Image {
      anchors.centerIn: parent
      visible: !WindowSwitcherConfig.previews
      width: Math.min(box.width, box.height) * 0.6
      height: width
      sourceSize: Qt.size(128, 128)
      source: AppIconManager.resolveWindowIcon(root.windowData?.appId, root.windowData?.title)
      fillMode: Image.PreserveAspectFit
    }
  }

  StyledText {
    id: title
    anchors.top: box.bottom
    anchors.topMargin: Widget.spacing
    anchors.left: box.left
    anchors.right: box.right
    text: root.windowData?.title || root.windowData?.appId || ""
    textColor: root.selected ? Theme.accent : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: WindowSwitcherManager.pick(root.index)
  }
}
