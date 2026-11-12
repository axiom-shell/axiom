pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// The urgent workspaces' looping pulse (`urgentPulse`): one per row or
// popout, so every urgent cell in it pulses in step, its box or line and
// content alike. `value` is how far an urgent cell is toward its muted self
// (the core's cell() pulse), 0 while still.
QtObject {
  id: root

  // While anything shown is urgent and the widget pulses
  property bool running: false
  property real value: 0
  // Whether it is running, its colors following `value` each frame
  readonly property bool pulsing: fade.running

  readonly property SequentialAnimation _fade: SequentialAnimation {
    id: fade
    running: root.running && Appearance.animations
    loops: Animation.Infinite
    onRunningChanged: {
      if (!fade.running)
        root.value = 0;
    }

    NumberAnimation {
      target: root
      property: "value"
      to: 1
      duration: Appearance.animSlow * 2
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "value"
      to: 0
      duration: Appearance.animSlow * 2
      easing.type: Appearance.easing
    }
  }
}
