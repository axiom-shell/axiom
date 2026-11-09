pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// A state drawn over a widget's background in its shape, filling it
// (WidgetBackground): a press's tint, the bar editor's highlight, the hover
// outline. Built only while `shown` and it has a color to draw, fading out
// included; its colors glide (`glides`, over `duration`).
ShapedBox {
  id: root

  property bool shown: true
  property string startCap: "round"
  property string endCap: "round"
  // A tab's shape (BarTabs.tab), or null
  property var tab: null
  property color fill: "transparent"
  property color stroke: "transparent"
  property real strokeWidth: 0
  property bool glides: true
  property int duration: Appearance.animFast

  visible: shown && (fill.a > 0 || stroke.a > 0)
  outline: ({
      "startCap": root.startCap,
      "endCap": root.endCap,
      "tab": root.tab
    })
  paint: ({
      "fill": root.fill,
      "stroke": root.stroke,
      "strokeWidth": root.strokeWidth
    })

  ColorGlide on fill {
    enabled: root.glides
    duration: root.duration
  }
  ColorGlide on stroke {
    enabled: root.glides
    duration: root.duration
  }
}
