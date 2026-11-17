pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config
import qs.components.methods

// A themed on/off switch. `compact` is the dense row's: the track
// `Widget.smallHeight` high, the same proportions.
Switch {
  id: root

  // -- Public API --
  property bool compact: false

  // -- Implementation --
  // On an accent host (a selected row) the on track takes a hairline in the accent's ink, so it shows
  readonly property var _scope: InkHost.find(root.parent)?.inkScope ?? null
  implicitWidth: Math.round(implicitHeight * 1.9)
  implicitHeight: root.compact ? Widget.smallHeight : Widget.slimHeight

  indicator: Rectangle {
    x: root.checked ? root.width - width - Widget.px(2) : Widget.px(2)
    y: Widget.px(2)
    width: root.height - Widget.px(4)
    height: root.height - Widget.px(4)
    // Concentric in the track, whatever its radius
    radius: Style.concentric(track.radius, Widget.px(2))
    color: root.checked ? Style.inkAccent.graphic : Style.inkHighest.icon

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
    border.color: root.checked ? Style.inkAccent.graphic : Style.borderStrong
    border.width: root.checked && root._scope !== Style.inkAccent ? 0 : Style.hairline

    ColorGlide on color {
      duration: Appearance.animNormal
    }

    FocusRing {
      shown: root.visualFocus
    }
  }
}
