pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// The urgent workspaces' looping fade (`urgentPulse`): one per row or
// popout, so every urgent cell in it fades in step, its box or line and
// content alike. `value` is the opacity they take, 1 while it's still.
QtObject {
  id: root

  // While anything shown is urgent and the widget pulses
  property bool running: false
  property real value: 1

  readonly property SequentialAnimation _fade: SequentialAnimation {
    id: fade
    running: root.running && Appearance.animations
    loops: Animation.Infinite
    onRunningChanged: {
      if (!fade.running)
        root.value = 1;
    }

    NumberAnimation {
      target: root
      property: "value"
      to: 0.35
      duration: Appearance.animSlow * 2
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "value"
      to: 1
      duration: Appearance.animSlow * 2
      easing.type: Appearance.easing
    }
  }
}
