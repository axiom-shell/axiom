pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A bold value with its unit beside it, on one baseline (StatFigure,
// CompactFigure)
RowLayout {
  id: root

  property string value: ""
  property string unit: ""
  property color valueColor: Theme.foreground
  property real valueSize: Appearance.fontSize * 2

  spacing: 2

  StyledText {
    text: root.value
    textColor: root.valueColor
    textSize: root.valueSize
    font.bold: true
  }
  StyledText {
    visible: root.unit !== ""
    Layout.alignment: Qt.AlignBaseline
    text: root.unit
    // Never larger than the value it follows
    textSize: Math.min(Appearance.fontSize, root.valueSize * 0.7)
    opacity: 0.7
  }
}
