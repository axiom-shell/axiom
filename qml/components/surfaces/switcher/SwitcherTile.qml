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
  readonly property real windowWidth: root.windowData?.w || 16 // a shape (16:10) for a window with no size
  readonly property real windowHeight: root.windowData?.h || 10 // a shape (16:10) for a window with no size
  readonly property real fit: Math.min(root.boxWidth / root.windowWidth, root.boxHeight / root.windowHeight)

  width: WindowSwitcherConfig.tileSize
  implicitHeight: root.boxHeight + Widget.spacing + title.implicitHeight + root.pad * 2

  Rectangle {
    anchors.fill: parent
    radius: Style.radius
    color: root.selected ? Style.accentContainer : Qt.alpha(Style.accentContainer, 0) // style-exempt: the selected fill at no alpha, so a selection change doesn't fade through black
    border.width: Appearance.borderWidth
    border.color: root.selected ? Style.accent : "transparent"

    ColorGlide on color {}

    StateLayer {
      hovered: mouse.containsMouse && !root.selected
    }
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
      radius: Style.radius
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
    textColor: root.selected ? Style.inkAccentContainer.text : Style.textMuted
    role: "caption"
    overflow: "line"
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
