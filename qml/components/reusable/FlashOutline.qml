pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// An accent outline over what it fills that shows for a moment on
// flash(): what a jump to a settings card or row lands on.
Rectangle {
  id: root

  function flash() {
    animation.restart();
  }

  z: 1
  radius: Widget.radius
  color: "transparent"
  border.color: Theme.accent
  border.width: Appearance.borderWidth + 1
  opacity: 0

  SequentialAnimation {
    id: animation
    NumberAnimation {
      target: root
      property: "opacity"
      to: 1
      duration: Appearance.animFast
    }
    PauseAnimation {
      duration: Appearance.animSlow
    }
    NumberAnimation {
      target: root
      property: "opacity"
      to: 0
      duration: Appearance.animSlow
    }
  }
}
