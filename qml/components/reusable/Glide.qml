pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The shell's eased change to a number: `Glide on width {}` is
// `Behavior on width { NumberAnimation { duration: Appearance.animFast;
// easing.type: Appearance.easing } }`. `duration` takes Appearance.animNormal
// or animSlow instead; `enabled` gates it as a Behavior's does. A Behavior
// with any other animation is written out.
Behavior {
  id: root

  property int duration: Appearance.animFast

  NumberAnimation {
    duration: root.duration
    easing.type: Appearance.easing
  }
}
