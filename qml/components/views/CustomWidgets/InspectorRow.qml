pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.forms

// A hand-built row of the custom widgets editor, for a field no schema
// control draws (a text field with a { } button, a typed key, a colour with
// its swatch): a FormRow (the hover tint, padding, divider and fold of every
// schema row) holding a FieldHeader and the control, laid out as SchemaField
// lays its fields out: the control under its label, or with `shortControl` (a
// dropdown) beside it on a form at least Widget.fieldInlineFrom wide, at
// Widget.fieldControlWidth, as SchemaComboBox. The control (a child) sets its
// own Layout.fillWidth. Captions and editors that belong to the row but not
// to the field go in `below` (outside the tint, as a hookup under a setting);
// the host says whether they show (`belowShown`, from data). A row whose
// control is a schema control with its own label (SchemaComboBox) leaves
// `label` empty. Put the rows of one box in a ColumnLayout with no spacing
// and mark the top one `first`.
FormRow {
  id: root

  property string label: ""
  property string description: ""
  // A short control (a dropdown): beside the label on a wide form
  property bool shortControl: false
  default property alias control: controls.data
  // Items under the field, at full width
  property alias below: belowColumn.data
  // Whether anything in `below` shows
  property bool belowShown: false
  // The row's dropdown (a StyledComboEntry), if its control is one: a click
  // on the row off the control opens or closes it, as SchemaComboBox's row
  property var dropdown: null

  hoverable: root.dropdown !== null
  onRowClicked: root.dropdown.toggleFromRow()

  readonly property bool _inline: root.shortControl && root.label !== "" && root.width >= Widget.fieldInlineFrom

  bodyHeight: column.implicitHeight
  // The tint and the row click cover the field, not what's under it
  hitHeight: root.belowShown ? field.implicitHeight : root.bodyHeight

  ColumnLayout {
    id: column
    width: parent.width
    spacing: Widget.spacing

    GridLayout {
      id: field
      Layout.fillWidth: true
      columns: root._inline ? 2 : 1
      rowSpacing: Widget.spacing
      columnSpacing: Widget.spacing * 2

      FieldHeader {
        label: root.label
        description: root.description
        // Centred on a control taller than it (a label alone)
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: controls
        Layout.fillWidth: !root._inline
        Layout.preferredWidth: root._inline ? Widget.fieldControlWidth(root.width) : -1
        Layout.alignment: Qt.AlignVCenter
        spacing: Widget.spacing / 2
      }
    }

    ColumnLayout {
      id: belowColumn
      Layout.fillWidth: true
      spacing: Widget.spacing / 2
      visible: root.belowShown
    }
  }
}
