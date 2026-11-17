pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable

// A boolean setting: its label and description, the switch at the row's
// right end, centred on them; a click anywhere on the row toggles it (the
// FormRow's `rowClicked`, routed to `activate` by SchemaField). A FieldLine,
// kind switch: always beside the label, the description beside it (wrapping
// earlier when narrow), at any width
FieldLine {
  id: root
  required property bool checked

  signal toggled(bool newValue)

  kind: "switch"
  controlLeast: sw.implicitWidth

  // What a click on the row outside the switch does
  function activate() {
    root.toggled(!root.checked);
  }

  StyledSwitch {
    id: sw
    checked: root.checked
    onToggled: {
      root.toggled(sw.checked);
      // A click sets checked itself; it follows `checked` again, so a host
      // that refuses or answers later is shown as it is
      sw.checked = Qt.binding(() => root.checked);
    }
  }
}
