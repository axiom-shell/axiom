pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A hand-built field of a card (editors, the onboarder): a FormRow (the
// hover tint, padding, divider and fold of every schema row) holding a
// FieldLine and the control, laid out as SchemaField lays its fields out
// (FieldFit): the control under its label and description, or with
// `shortControl` (a dropdown) on the label's line whenever it fits beside it,
// `besideLabel` filling the rest of the line. The control (a child) sets its
// own Layout.fillWidth. Captions and editors that belong to the row but not
// to the field go in `below` (outside the tint, as a hookup under a setting);
// the host says whether they show (`belowShown`, from data). A row whose
// control is a schema control with its own label (SchemaComboBox) is a plain
// FormRow instead. `activates` names the control a click on the row off the
// controls acts on (a dropdown opens). Put the rows of one box in a
// FormColumn: its top row has no divider.
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
  // What is wrong with the field's value, { level, text } or null (FieldProblem),
  // shown under its label and description
  property var problem: null
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
      headerBelow: root.problem !== null ? problemLine : null

      ColumnLayout {
        id: controls
        Layout.fillWidth: true
        spacing: Widget.spacing / 2
      }
    }

    Component {
      id: problemLine
      FieldProblem {
        problem: root.problem
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
