pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// An icon that turns while `spinning` (and animations are on), back
// upright when it stops: a busy mark (a scan, a build).
StyledIcon {
  id: root

  property bool spinning: false

  onSpinningChanged: if (!spinning)
    rotation = 0

  RotationAnimation on rotation {
    running: root.spinning && Appearance.animations
    loops: Animation.Infinite
    from: 0
    to: 360
    duration: Appearance.animSlow * 4
  }
}
