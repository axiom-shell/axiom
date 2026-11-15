pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.forms

// A hand-built row of the custom widgets inspectors: its label (and
// description) above its control at full width, as SchemaField draws a field
// in a narrow form, in a FormRow so it shares the left edge, the padding and
// the divider of the SchemaPropertiesForm rows around it. The control (a
// child) sets its own Layout.fillWidth. Put the rows of one group in a
// ColumnLayout with no spacing and mark the first `first`.
FormRow {
  id: root

  property string label: ""
  property string description: ""
  default property alias control: controls.data

  tinted: false
  bodyHeight: column.implicitHeight

  ColumnLayout {
    id: column
    width: parent.width
    spacing: Widget.spacing / 2

    FieldHeader {
      label: root.label
      description: root.description
    }

    ColumnLayout {
      id: controls
      Layout.fillWidth: true
      spacing: Widget.spacing / 2
    }
  }
}
