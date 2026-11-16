pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.forms

// A hand-built row of the custom widgets editor, for a field no schema
// control draws (a text field with a { } button, a typed key, a colour with
// its swatch): a FormRow (the hover tint, padding, divider and fold of every
// schema row) holding a FieldLine and the control, laid out as SchemaField
// lays its fields out (FieldFit): the control under its label, or with
// `shortControl` (a dropdown) on the label's line whenever it fits beside it,
// as SchemaComboBox. The control (a child) sets its own Layout.fillWidth.
// Captions and editors that belong to the row but not
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
  // The label beside the control whatever the width, the control filling the
  // rest (a row that lines up with a one-line row beside it)
  property bool besideLabel: false
  default property alias control: controls.data
  // Items under the field, at full width
  property alias below: belowColumn.data
  // Whether anything in `below` shows
  property bool belowShown: false
  // The row's dropdown (a StyledComboEntry), if its control is one: a click
  // on the row off the control opens or closes it, as SchemaComboBox's row
  property var dropdown: null

  hoverable: root.dropdown !== null
  onRowClicked: root.dropdown.activate()

  bodyHeight: column.implicitHeight
  // The tint and the row click cover the field, not what's under it
  hitHeight: root.belowShown ? field.implicitHeight : root.bodyHeight

  ColumnLayout {
    id: column
    width: parent.width
    spacing: Widget.spacing

    // Placed against the row's body width (indent excluded): FieldLine reads
    // its own
    FieldLine {
      id: field
      label: root.label
      description: root.description
      kind: root.besideLabel ? "fill" : root.shortControl ? "flex" : "block"

      ColumnLayout {
        id: controls
        Layout.fillWidth: true
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
