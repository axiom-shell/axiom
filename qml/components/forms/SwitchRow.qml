pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A switch line of a card: a FormRow (tint, divider, padding) holding a
// SchemaSwitch, the switch at the right end; a click anywhere on the row flips
// it (`activates`). `leading` puts something before the label (an icon, a
// colour dot). While `unavailableReason` isn't empty the row is greyed and
// says why in place of its description; a row already on can still be turned
// off. `checked` is pushed in; `toggled(bool)` says the new value.
FormRow {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false
  // Why the switch can't be used; empty while it can
  property string unavailableReason: ""
  // Before the label
  property alias leading: leadingRow.data

  signal toggled(bool newValue)

  activates: line
  enabled: root.unavailableReason === "" || root.checked
  opacity: root.unavailableReason === "" ? 1 : Style.opacityDisabled
  bodyHeight: row.implicitHeight

  RowLayout {
    id: row
    width: parent.width
    spacing: Widget.spacing

    RowLayout {
      id: leadingRow
      visible: children.length > 0
      Layout.fillWidth: false
      spacing: Widget.spacing
    }

    SchemaSwitch {
      id: line
      Layout.fillWidth: true
      label: root.label
      description: root.unavailableReason !== "" ? root.unavailableReason : root.description
      checked: root.checked
      onToggled: newValue => root.toggled(newValue)
    }
  }
}
