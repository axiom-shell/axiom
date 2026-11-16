pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.forms

// One field of the bind inspector as a form row (the hover tint, padding and
// divider of every settings row, indented under its group): a label with its
// description over the control, which sets its own Layout.fillWidth. A row of
// a schema control that draws its own label (SchemaComboBox) is a plain
// FormRow instead.
FormRow {
  id: root

  property string label: ""
  property string description: ""
  default property alias control: controls.data

  bodyHeight: column.implicitHeight

  ColumnLayout {
    id: column
    width: parent.width
    spacing: Widget.spacing

    FieldHeader {
      label: root.label
      description: root.description
    }

    ColumnLayout {
      id: controls
      Layout.fillWidth: true
      spacing: 0
    }
  }
}
