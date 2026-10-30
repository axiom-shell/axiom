pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// i18n: keys from callers and the schema (titles, descriptions, type labels)
// A boolean setting: its label and description, the switch at the row's
// right end, centred on them; a click anywhere on the row toggles it
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

  // Under the switch, which takes its own clicks
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled(!root.checked)
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
