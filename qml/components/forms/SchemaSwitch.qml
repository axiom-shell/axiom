pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A boolean setting: its label and description, the switch at the row's
// right end, centred on them; a click anywhere on the row toggles it (the
// FormRow's `rowClicked`, routed to `activate` by SchemaField)
Item {
  id: root
  required property string label
  required property bool checked
  property string description: ""
  // After the label (FieldHeader.trailing)
  property Component headerExtra: null

  signal toggled(bool newValue)

  Layout.fillWidth: true
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  // What a click on the row outside the switch does
  function activate() {
    root.toggled(!root.checked);
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
    StyledSwitch {
      checked: root.checked
      Layout.alignment: Qt.AlignVCenter
      onToggled: root.toggled(checked)
    }
  }
}
