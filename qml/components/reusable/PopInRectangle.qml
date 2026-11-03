pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small mark that pops in and out (CountBadge, StatusChip, UnsavedDot):
// set `shown` rather than `visible`, and it grows in from its centre and
// shrinks away, staying visible (and laid out) until it has. `pulse()`
// gives it a short bump, for a value that changed while it shows.
Rectangle {
  id: root

  property bool shown: true

  property real _reveal: shown ? 1 : 0
  Glide on _reveal {}
  property real _bump: 1

  visible: _reveal > 0
  opacity: _reveal
  scale: (0.6 + 0.4 * _reveal) * _bump

  function pulse() {
    if (Appearance.animations && root.shown)
      bump.restart();
  }

  SequentialAnimation {
    id: bump
    NumberAnimation {
      target: root
      property: "_bump"
      to: 1.15
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "_bump"
      to: 1
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }
}
