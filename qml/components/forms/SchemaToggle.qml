pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// i18n: keys from callers and the schema (titles, descriptions, type labels)
// A setting of two or three values (`x-control: toggle`): its label and
// description, a StyledToggle with the options at the row's right end,
// centred on them; with two, a click anywhere on the row flips it
Item {
  id: root
  required property string label
  required property var options
  required property var optionLabels
  property var currentValue
  property string description: ""
  // After the label (FieldHeader.trailing)
  property Component headerExtra: null

  signal picked(var value)

  Layout.fillWidth: true
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  // Under the toggle, which takes its own clicks (two options only: with
  // three, the row can't say which)
  MouseArea {
    anchors.fill: parent
    enabled: root.options.length === 2
    cursorShape: Qt.PointingHandCursor
    onClicked: root.picked(root.options[1 - Math.max(0, root.options.indexOf(root.currentValue))])
  }

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Widget.spacing * 2

    FieldHeader {
      label: root.label
      description: root.description
      trailing: root.headerExtra
    }

    // Centred on the label and description together
    StyledToggle {
      Layout.alignment: Qt.AlignVCenter
      options: root.options
      labels: root.optionLabels
      value: root.currentValue
      onPicked: value => root.picked(value)
    }
  }
}
