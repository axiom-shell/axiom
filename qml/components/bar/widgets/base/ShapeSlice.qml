pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// A shape's slice of the bar's gradient (BarWidgetStyle.gradientSlice's
// three stops, null for none), along the bar: a ShapePath's fillGradient
// or strokeGradient over an item `length` long (down a vertical bar)
LinearGradient {
  id: root

  property var slice: null
  property bool vertical: false
  property real length: 0

  readonly property var _noStop: ({
      "position": 0,
      "color": "transparent"
    })
  readonly property var _stops: root.slice ?? [root._noStop, root._noStop, root._noStop]

  x1: 0
  y1: 0
  x2: root.vertical ? 0 : root.length
  y2: root.vertical ? root.length : 0

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
