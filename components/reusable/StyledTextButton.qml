pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config

// A button with a text label and an optional Material Symbols icon, with
// hover and press colors and an optional tooltip.
Rectangle {
  id: root

  // -- Signals --
  signal clicked

  // -- Public API --
  property alias text: label.text
  // A Material Symbols name drawn beside the label (or alone, with no text)
  property string iconText: ""
  // Draw the icon after the label instead of before it
  property bool iconAfter: false
  // The label's and the icon's size
  property real textSize: Appearance.fontSize
  property string tooltipText: ""

  // -- Configurable Appearance --
  property int textPadding: Math.round(Widget.smallPadding * 4 / 3)
  property color backgroundColor: Theme.backgroundHighlight
  property color hoverColor: Theme.accent
  property color pressColor: Theme.accentAlt
  property color textColor: Theme.foreground
  property color textHoverColor: Theme.background
  property color borderColor: Theme.border
  property int borderWidth: 0
  property real borderRadius: Widget.radius

  // -- Implementation --
  implicitWidth: content.implicitWidth + (textPadding * 2)
  implicitHeight: content.implicitHeight + (textPadding * 2)
  Layout.alignment: Qt.AlignVCenter

  color: Appearance.fill(mouseArea.pressed ? pressColor : (mouseArea.containsMouse ? hoverColor : backgroundColor))
  border.color: borderColor
  border.width: borderWidth
  radius: borderRadius

  Behavior on color {
    ColorAnimation {
      duration: Appearance.animNormal
      easing.type: Easing.InOutQuad
    }
  }

  property color _contentColor: mouseArea.containsMouse ? root.textHoverColor : root.textColor

  Behavior on _contentColor {
    ColorAnimation {
      duration: Appearance.animNormal
      easing.type: Easing.InOutQuad
    }
  }

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: Widget.spacing / 2
    layoutDirection: root.iconAfter ? Qt.RightToLeft : Qt.LeftToRight

    StyledIcon {
      visible: root.iconText !== ""
      text: root.iconText
      textColor: root._contentColor
      textSize: root.textSize
    }

    StyledText {
      id: label
      visible: text !== ""
      textColor: root._contentColor
      textSize: root.textSize
      font.bold: true
    }
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
