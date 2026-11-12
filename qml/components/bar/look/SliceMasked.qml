pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Paints a slice of the bar's gradient only where its children draw (the
// gradient stroke strokeGradient would give, which is Qt 6.12+): the
// children are the mask, drawn in any opaque colour, and a Shape filled
// with the slice shows through them.
Item {
  id: root

  // BarGradient.gradientSlice's three stops
  property var slice: null
  property bool vertical: false
  // The box's length along the bar
  property real length: 0
  default property alias content: maskItem.data

  anchors.fill: parent

  Item {
    id: maskItem
    anchors.fill: parent
    visible: false
    layer.enabled: true
  }

  Shape {
    id: paintShape
    anchors.fill: parent
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: maskItem
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1
    }

    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: paint

      PathSvg {
        path: "M0 0 H" + paintShape.width + " V" + paintShape.height + " H0 Z"
      }
    }

    ShapeSlice {
      id: paint
      slice: root.slice
      vertical: root.vertical
      length: root.length
    }
  }
}
