pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A large value with its unit, and a small label underneath
ColumnLayout {
  id: root

  property string value: ""
  property string unit: ""
  property string label: ""
  property color valueColor: Theme.foreground
  property int valueSize: Appearance.fontSize * 2

  spacing: 0

  FigureValue {
    value: root.value
    unit: root.unit
    valueColor: root.valueColor
    valueSize: root.valueSize
  }

  StyledText {
    visible: root.label !== ""
    Layout.fillWidth: true
    text: root.label
    elide: Text.ElideRight
    textSize: Appearance.fontSizeBy(-2)
    opacity: 0.6
  }
}
