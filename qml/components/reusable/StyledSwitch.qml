pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.components.methods
import qs.config

// A themed on/off switch. `compact` is the dense row's: the track
// `Widget.smallHeight` high, the same proportions.
Switch {
  id: root

  // -- Public API --
  property bool compact: false

  // -- Implementation --
  implicitWidth: Math.round(implicitHeight * 1.9)
  implicitHeight: root.compact ? Widget.smallHeight : Widget.height - Widget.px(4)

  indicator: Rectangle {
    x: root.checked ? root.width - width - Widget.px(2) : Widget.px(2)
    y: Widget.px(2)
    width: root.height - Widget.px(4)
    height: root.height - Widget.px(4)
    // Concentric in the track, whatever its radius
    radius: StyleTokens.concentric(track.radius, Widget.px(2), Style.radiusMin)
    color: root.checked ? Style.onAccent : Style.inkHighest.icon

    ColorGlide on color {
      duration: Appearance.animNormal
    }

    Glide on x {
      duration: Appearance.animNormal
    }
  }

  background: Rectangle {
    id: track
    implicitWidth: root.implicitWidth
    implicitHeight: root.implicitHeight
    radius: Style.radiusInner
    color: root.checked ? Style.accent : Style.surfaceHighest
    // A hairline while off, so the track shows on a highest fill
    border.color: Style.borderStrong
    border.width: root.checked ? 0 : Style.hairline

    ColorGlide on color {
      duration: Appearance.animNormal
    }

    FocusRing {
      shown: root.visualFocus
    }
  }
}
