pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.methods

// A rectangular icon button with hover and press colors and a tooltip.
Rectangle {
  id: root

  // -- Signals --
  signal clicked

  // -- Public API --
  property string iconText: ""
  property string tooltipText: ""

  // -- Configurable Appearance --
  property alias iconSize: iconLabel.textSize
  property alias iconColor: iconLabel.textColor
  property color backgroundColor: Theme.backgroundAlt
  property color hoverColor: root.backgroundColor
  property color pressColor: root.backgroundColor
  property color borderColor: "transparent"
  property color borderHoverColor: root.borderColor
  property int borderWidth: Appearance.borderWidth
  property real borderRadius: Widget.radius

  // -- Implementation --

  // A square of this side, which layouts keep (anchor or size it to
  // change that)
  property int size: Widget.height

  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
  implicitWidth: root.size
  implicitHeight: root.size

  color: Appearance.fill(Utils.fadeable(mouseArea.pressed ? root.pressColor : (mouseArea.containsMouse ? root.hoverColor : root.backgroundColor), root.hoverColor, root.backgroundColor))
  border.color: Utils.fadeable(mouseArea.pressed ? root.borderColor : (mouseArea.containsMouse ? root.borderHoverColor : root.borderColor), root.borderHoverColor, root.borderColor)
  border.width: root.borderWidth
  radius: root.borderRadius

  ColorGlide on color {
    duration: Appearance.animNormal
  }

  ColorGlide on border.color {
    duration: Appearance.animNormal
  }

  StyledIcon {
    id: iconLabel
    anchors.centerIn: parent
    text: root.iconText
    textSize: Appearance.fontSize
    textColor: Theme.foreground
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  LazyLoader {
    active: mouseArea.containsMouse && root.tooltipText !== ""
    StyledToolTip {
      target: root
      text: root.tooltipText
    }
  }
}
