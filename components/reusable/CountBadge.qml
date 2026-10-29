pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small pill holding a count (or any short label), for a button's or
// an icon's corner: StyledRectButton's badge, the notification bell's.
// Pops in and out by `shown`, and bumps when its count changes.
PopInRectangle {
  id: root

  property string text: ""
  property color textColor: Theme.background
  // Its size follows: a bar's badge takes the bar's text size
  property int textSize: Appearance.fontSizeBy(-4)

  implicitWidth: Math.max(implicitHeight, label.implicitWidth + Math.round(textSize * 0.6))
  implicitHeight: Math.round(textSize * 1.4)
  radius: height / 2
  color: Theme.error
  onTextChanged: pulse()

  // The glyphs' own box, from the baseline: the line's ascent and descent
  // aren't even about the digits, so centring the text's line box left
  // the count off centre
  TextMetrics {
    id: ink
    font: label.font
    text: root.text
  }

  StyledText {
    id: label
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: label.width / 2 - (ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2)
    anchors.verticalCenterOffset: label.height / 2 - (label.baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2)
    text: root.text
    textSize: root.textSize
    textColor: root.textColor
  }
}
