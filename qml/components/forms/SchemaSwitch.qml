pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable

// A boolean setting: its label and description, the switch at the row's
// right end, centred on them; a click anywhere on the row toggles it (the
// FormRow's `rowClicked`, routed to `activate` by SchemaField). A FieldLine,
// kind switch: always beside the label
FieldLine {
  id: root
  required property bool checked

  signal toggled(bool newValue)

  kind: "switch"

  // What a click on the row outside the switch does
  function activate() {
    root.toggled(!root.checked);
  }

  StyledSwitch {
    checked: root.checked
    onToggled: root.toggled(checked)
  }
}
