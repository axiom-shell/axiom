pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config

// A themed on/off switch.
Switch {
  id: root

  // -- Implementation --
  implicitWidth: Math.round(implicitHeight * 1.9)
  implicitHeight: Widget.height - Widget.px(4)

  indicator: Rectangle {
    x: root.checked ? root.width - width - 2 : 2
    y: 2
    width: root.height - Widget.px(4)
    height: root.height - Widget.px(4)
    radius: (root.height - Widget.px(4)) / 2
    color: Theme.foreground

    Glide on x {
      duration: Appearance.animNormal
    }
  }

  background: Rectangle {
    implicitWidth: root.implicitWidth
    implicitHeight: root.implicitHeight
    radius: height / 2
    color: root.checked ? Theme.accent : Theme.backgroundHighlight
    border.color: Theme.border
    border.width: Appearance.borderWidth

    ColorGlide on color {
      duration: Appearance.animNormal
    }
  }
}
