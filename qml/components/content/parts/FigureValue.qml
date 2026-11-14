pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A value with its unit beside it, on one baseline (StatFigure,
// CompactFigure)
RowLayout {
  id: root

  property string value: ""
  property string unit: ""
  property color valueColor: Style.text
  property real valueSize: Style.typeBody * 2

  spacing: 2

  StyledText {
    text: root.value
    textColor: root.valueColor
    textSize: Math.max(Style.typeMicro, root.valueSize) // fitted: the value's row
    font.weight: Style.roleDisplay.weight
  }
  StyledText {
    visible: root.unit !== ""
    Layout.alignment: Qt.AlignBaseline
    text: root.unit
    // Never larger than the value it follows
    textSize: Math.min(Style.typeBody, root.valueSize * 0.7) // fitted: beside the value
    tone: "muted"
  }
}
