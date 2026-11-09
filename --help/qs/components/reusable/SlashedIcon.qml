pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// An icon struck through while `slashed`: the base icon ("wifi", never
// "wifi_off") with one drawn slash, top left to bottom right as Material's
// own run, over a wider line in `cutout` (what it sits on) that parts the
// glyph as Material's cutout does. So every off state looks the same,
// whichever icons have an off form.
Item {
  id: root

  property string text
  property int textSize: Appearance.fontSize
  property color textColor: Theme.foreground
  property bool slashed: false
  // The colour it's drawn on; transparent for no cutout
  property color cutout: Qt.alpha(Theme.background, 0)

  implicitWidth: icon.implicitWidth
  implicitHeight: icon.implicitHeight

  StyledIcon {
    id: icon
    anchors.centerIn: parent
    text: root.text
    textSize: root.textSize
    textColor: root.textColor
  }

  Rectangle {
    visible: root.slashed && root.cutout.a > 0
    anchors.centerIn: parent
    width: root.textSize * 1.05
    height: Widget.px(2) + Widget.px(3)
    radius: height / 2
    rotation: 45
    color: root.cutout
  }

  Rectangle {
    visible: root.slashed
    anchors.centerIn: parent
    width: root.textSize * 0.95
    height: Widget.px(2)
    radius: height / 2
    rotation: 45
    color: root.textColor
  }
}
