pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small filled pill with a bold word: a status (On, Running, Not
// installed) in its colour, on the settings page's status cards
PopInRectangle {
  id: root

  property string text: ""

  implicitWidth: label.implicitWidth + Widget.padding * 2
  implicitHeight: label.implicitHeight + Widget.px(4)
  radius: height / 2
  color: Theme.foregroundAlt

  ColorGlide on color {
    duration: Appearance.animNormal
  }

  StyledText {
    id: label
    anchors.centerIn: parent
    text: root.text
    textColor: Theme.background
    textSize: Appearance.fontSizeBy(-2)
    font.bold: true
  }
}
