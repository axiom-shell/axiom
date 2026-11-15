pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small mark that pops in and out (CountBadge, StatusChip, UnsavedDot):
// set `shown` rather than `visible`, and it slides up into place as it fades
// in and back as it fades out, staying visible (and laid out) until it has. `pulse()`
// gives it a short bump, for a value that changed while it shows.
Rectangle {
  id: root

  property bool shown: true

  property real _reveal: shown ? 1 : 0
  Glide on _reveal {}
  property real _bump: 1
  // Its pulse scales the badge: the text inside is drawn distance field while it does
  readonly property real contentZoom: root.scale

  visible: _reveal > 0
  opacity: _reveal
  scale: root._bump
  // A transform, never `y`: the badge's layout owns that
  transform: Translate {
    y: Math.round((1 - root._reveal) * Style.enterOffset)
  }

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
