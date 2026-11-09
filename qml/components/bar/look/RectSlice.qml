pragma ComponentBehavior: Bound
import QtQuick

// A Rectangle's slice of the bar's gradient (BarGradient.gradientSlice's
// three stops, null for none), along the bar (down a vertical one): an
// underline's line, a split badge
Gradient {
  id: root

  property var slice: null
  property bool vertical: false

  readonly property var _noStop: ({
      "position": 0,
      "color": "transparent"
    })
  readonly property var _stops: root.slice ?? [root._noStop, root._noStop, root._noStop]

  orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal

  GradientStop {
    position: root._stops[0].position
    color: root._stops[0].color
  }
  GradientStop {
    position: root._stops[1].position
    color: root._stops[1].color
  }
  GradientStop {
    position: root._stops[2].position
    color: root._stops[2].color
  }
}
