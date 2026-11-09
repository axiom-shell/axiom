pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Draws its children with `holes` (rects in its coordinates) cut out:
// a stroke left open where something joined to it carries on over it.
// No layer while there are none, unless kept (`keepLayer`): a layer and
// its mask made in the same pass as the first hole may show a frame with
// nothing cut yet.
Item {
  id: root

  property var holes: []
  property bool keepLayer: false
  readonly property bool _layered: root.keepLayer || root.holes.length > 0
  default property alias content: inner.data

  Item {
    id: inner
    anchors.fill: parent
    layer.enabled: root._layered
    layer.effect: MultiEffect {
      maskEnabled: true
      maskInverted: true
      maskSource: mask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 0
    }
  }

  Item {
    id: mask
    anchors.fill: parent
    visible: false
    layer.enabled: root._layered

    Repeater {
      model: root.holes.length

      Rectangle {
        required property int index
        readonly property rect hole: root.holes[index] ?? Qt.rect(0, 0, 0, 0)
        x: hole.x
        y: hole.y
        width: hole.width
        height: hole.height
        color: "black"
      }
    }
  }
}
