pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.methods

// A ToolButton showing a Material Symbols icon, with hover and press colors
// and an optional tooltip.
ToolButton {
  id: root

  // -- Public API --
  property string iconText: ""
  property string tooltipText: ""
  // A square of this side that doesn't stretch in layouts
  property int size: Widget.iconButton

  // -- Configurable Appearance --
  property int iconSize: Appearance.fontSize
  property color iconColor: Theme.foreground
  property color backgroundColor: "transparent"
  property color hoverColor: Theme.backgroundHighlight
  property color pressColor: Theme.backgroundAlt
  property color borderColor: "transparent"
  property int borderWidth: Appearance.borderWidth
  property real borderRadius: Widget.radius

  // -- Implementation --

  implicitWidth: size
  implicitHeight: size
  Layout.preferredWidth: size
  Layout.preferredHeight: size
  Layout.fillWidth: false
  Layout.fillHeight: false
  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

  padding: 0
  opacity: enabled ? 1.0 : 0.4
  scale: root.pressed ? 0.92 : 1.0

  Glide on scale {}

  HoverHandler {
    cursorShape: Qt.PointingHandCursor
  }

  LazyLoader {
    active: root.hovered && root.tooltipText !== ""
    StyledToolTip {
      target: root
      text: root.tooltipText
    }
  }

  contentItem: StyledIcon {
    text: root.iconText
    textSize: root.iconSize
    textColor: root.iconColor
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  background: Rectangle {
    color: Utils.fadeable(root.pressed ? root.pressColor : (root.hovered ? root.hoverColor : root.backgroundColor), root.hoverColor, root.backgroundColor)
    border.color: root.borderColor
    border.width: root.borderWidth
    radius: root.borderRadius

    ColorGlide on color {
      duration: Appearance.animNormal
    }
  }
}
