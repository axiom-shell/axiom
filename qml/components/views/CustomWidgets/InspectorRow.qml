pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.forms
import qs.components.reusable

// A hand-built row of the custom widgets inspectors: its label (and
// description) above its control at full width, as SchemaField draws a field
// in a narrow form, or with `beside` the label on the left and the control on
// the right, as the settings page draws a dropdown, a toggle or a number (the
// description then goes under both). It sits in a FormRow so it shares the
// left edge, the padding and the divider of the SchemaPropertiesForm rows
// around it. The control (a child) sets its own Layout.fillWidth; captions
// and editors that need the whole width go in `below`. Put the rows of one
// group in a ColumnLayout with no spacing and mark the first `first`.
FormRow {
  id: root

  property string label: ""
  property string description: ""
  // The label to the left of the control (ignored for a row with no label)
  property bool beside: false
  default property alias control: controls.data
  // Items under the label and control, at full width
  property alias below: belowColumn.data

  readonly property bool _beside: root.beside && root.label !== ""
  readonly property real _labelWidth: Math.round(root.width * 0.36) - root.indent

  tinted: false
  bodyHeight: column.implicitHeight

  ColumnLayout {
    id: column
    width: parent.width
    spacing: Widget.spacing / 2

    GridLayout {
      Layout.fillWidth: true
      columns: root._beside ? 2 : 1
      rowSpacing: Widget.spacing / 2
      columnSpacing: Widget.spacing * 2

      FieldHeader {
        label: root.label
        description: root._beside ? "" : root.description
        Layout.fillWidth: !root._beside
        Layout.preferredWidth: root._beside ? root._labelWidth : -1
        Layout.maximumWidth: root._beside ? root._labelWidth : Number.POSITIVE_INFINITY
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: controls
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Widget.spacing / 2
      }
    }

    ClampedText {
      Layout.fillWidth: true
      text: root._beside && root.description !== "" ? I18n.tr(root.description) : ""
    }

    ColumnLayout {
      id: belowColumn
      Layout.fillWidth: true
      spacing: Widget.spacing / 2
      visible: belowColumn.children.length > 0
    }
  }
}
