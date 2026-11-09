pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.config

// The box of something that drops down over other content (a picker, a
// list opened from a header): bordered, rounded, with a shadow while
// `floating`
Rectangle {
  id: root

  // Over other content: casts a shadow
  property bool floating: true

  color: Appearance.fill(Theme.background)
  radius: Widget.radius
  border.color: Theme.border
  border.width: 1

  layer.enabled: root.floating
  // Qt 6 MultiEffect: Qt5Compat DropShadow fails to build its shader here
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: "#40000000"
    shadowBlur: 0.5
    shadowVerticalOffset: 2
  }
}
