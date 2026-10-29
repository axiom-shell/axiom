pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config

// A volume bar (vertical or horizontal) with its icon, mute and optional
// percentage: drag, click or scroll to set it. PipewireVolumeBar binds it to audio.
Item {
  id: root

  // -- Signals --
  signal volumeChanged(real newVolume)

  // -- Public API --
  property int orientation: Qt.Vertical
  property real volumeLevel: 0.75
  property bool isMuted: false
  property string iconSource: "volume_up"
  // Shows the level as a percentage under the bar
  property bool showPercent: false
  // Level change per wheel notch (0-1); 0 turns scrolling off
  property real scrollStep: 0

  // -- Implementation --
  // Wide enough for "100%" under the icon
  implicitWidth: orientation === Qt.Vertical ? Math.max(Widget.px(48), showPercent ? widest.advanceWidth + Widget.spacing * 4 : 0) : Widget.px(160)
  implicitHeight: Widget.px(orientation === Qt.Vertical ? 160 : 48)

  // Anywhere on the bar; a notch is 120, so touchpads step smoothly
  WheelHandler {
    enabled: root.enabled && root.scrollStep > 0
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
      const level = root.volumeLevel + root.scrollStep * delta / 120;
      root.volumeChanged(Math.round(Math.max(0, Math.min(1, level)) * 100) / 100);
    }
  }

  Rectangle {
    id: background
    anchors.fill: parent
    radius: Widget.radius
    color: root.isMuted ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)

    ColorGlide on color {
      duration: Appearance.animNormal
    }
  }

  // Vertical: bar above the icon. Horizontal: icon left of the bar (a
  // column there would squeeze the bar to nothing in the 48px height).
  GridLayout {
    id: content
    readonly property bool isVertical: root.orientation === Qt.Vertical

    anchors.fill: parent
    anchors.margins: Widget.spacing * 2
    rowSpacing: Widget.spacing * 2
    columnSpacing: Widget.spacing * 2

    // Clips the fill, so a low level keeps to the trough's rounded ends
    ClippingRectangle {
      id: barContainer
      Layout.row: 0
      Layout.column: content.isVertical ? 0 : 1
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.alignment: Qt.AlignCenter

      implicitWidth: Widget.px(root.orientation === Qt.Vertical ? 12 : 120)
      implicitHeight: Widget.px(root.orientation === Qt.Vertical ? 120 : 12)

      radius: Widget.radius
      color: Qt.alpha(Theme.foreground, 0.2)

      Rectangle {
        id: barFill
        anchors.left: root.orientation === Qt.Horizontal ? parent.left : undefined
        anchors.bottom: parent.bottom
        anchors.right: root.orientation === Qt.Vertical ? parent.right : undefined
        anchors.leftMargin: root.orientation === Qt.Vertical ? parent.width - width : 0

        width: root.orientation === Qt.Horizontal ? parent.width * root.volumeLevel : parent.width
        height: root.orientation === Qt.Vertical ? parent.height * root.volumeLevel : parent.height

        radius: Widget.radius
        color: root.isMuted ? Qt.alpha(Theme.foreground, 0.4) : Theme.accent

        Behavior on height {
          enabled: root.orientation === Qt.Vertical
          NumberAnimation {
            duration: Appearance.animNormal
            easing.type: Easing.OutCubic
          }
        }

        Behavior on width {
          enabled: root.orientation === Qt.Horizontal
          NumberAnimation {
            duration: Appearance.animNormal
            easing.type: Easing.OutCubic
          }
        }
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function updateVolume(mousePoint) {
          var newVol = 0.0;
          if (root.orientation === Qt.Vertical) {
            newVol = 1.0 - (mousePoint.y / height);
          } else {
            newVol = mousePoint.x / width;
          }
          root.volumeChanged(Math.max(0.0, Math.min(1.0, newVol)));
        }

        onPressed: mouse => dragArea.updateVolume(mouse)
        onPositionChanged: mouse => {
          if (dragArea.pressed)
            dragArea.updateVolume(mouse);
        }
      }
    }

    Item {
      id: iconContainer
      Layout.row: content.isVertical ? 1 : 0
      Layout.column: 0
      Layout.alignment: Qt.AlignCenter
      implicitWidth: iconText.implicitWidth
      implicitHeight: iconText.implicitHeight

      // Cross-fades as the level crosses a step (volume to muted)
      CrossFade {
        id: iconText
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        value: root.iconSource
        delegate: StyledIcon {
          required property var value
          text: value
          textSize: Appearance.fontSizeBy(10)
        }
      }

      Rectangle {
        id: crossOutLine
        anchors.centerIn: parent
        width: parent.width * 1.2
        height: 2
        rotation: 45
        color: Theme.foreground
        radius: 1
        visible: root.isMuted
      }
    }

    StyledText {
      text: root.showPercent ? Math.round(root.volumeLevel * 100) + "%" : ""
      textSize: Appearance.fontSizeBy(-2)
      horizontalAlignment: Text.AlignHCenter
      Layout.row: content.isVertical ? 2 : 0
      Layout.column: content.isVertical ? 0 : 2
      Layout.alignment: Qt.AlignCenter
      // A fixed width for percentages, so the bar doesn't shift as it changes
      Layout.preferredWidth: root.showPercent ? widest.advanceWidth : -1
      visible: text !== ""
      elide: Text.ElideRight
      Layout.maximumWidth: root.showPercent ? Infinity : parent.width - Widget.px(4)

      TextMetrics {
        id: widest
        font.family: Appearance.fontFamily
        font.pixelSize: Appearance.fontSizeBy(-2)
        text: "100%"
      }
    }
  }
}
