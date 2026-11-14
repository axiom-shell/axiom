pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A setting of two or three values (`x-control: toggle`): its label and
// description, a StyledToggle with the options at the row's right end,
// centred on them; with two, a click anywhere on the row flips it (the
// FormRow's `rowClicked`, routed to `activate` by SchemaField)
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

  // Under its label when the toggle at its widest (constant per control:
  // StyledToggle's implicit width) leaves the label less than its least
  // column (D-83); decided from implicit widths only, never `truncated`
  readonly property bool stacked: root.width > 0 && toggle.implicitWidth > root.width - Widget.textPx(160)

  Layout.fillWidth: true
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  // What a click on the row outside the toggle does (two options only:
  // with three, the row can't say which)
  function activate() {
    if (root.options.length === 2)
      root.picked(root.options[1 - Math.max(0, root.options.indexOf(root.currentValue))]);
  }

  GridLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    columns: root.stacked ? 1 : 2
    rowSpacing: Widget.spacing
    columnSpacing: Widget.spacing * 2

    FieldHeader {
      label: root.label
      description: root.description
      trailing: root.headerExtra
    }

    // Centred on the label and description together
    StyledToggle {
      id: toggle
      Layout.alignment: root.stacked ? Qt.AlignLeft | Qt.AlignVCenter : Qt.AlignVCenter
      options: root.options
      labels: root.optionLabels
      value: root.currentValue
      onPicked: value => root.picked(value)
    }
  }
}
