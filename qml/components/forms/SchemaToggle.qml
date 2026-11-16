pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.reusable

// A setting of two or three values (`x-control: toggle`): its label and
// description, a StyledToggle with the options at the row's right end,
// centred on them (a FieldLine, kind fixed: stacked under a label it would
// crowd, the toggle then fills the width); a click on the row off the toggle
// cycles to the next option (the FormRow's `rowClicked`, routed to
// `activate` by SchemaField)
FieldLine {
  id: root
  required property var options
  required property var optionLabels
  property var currentValue

  signal picked(var value)

  kind: "fixed"
  controlLeast: toggle.implicitWidth
  readonly property bool stacked: root.width > 0 && !root.fit.inline

  // What a click on the row outside the toggle does: the next option, the
  // first after the last
  function activate() {
    const index = Math.max(0, root.options.indexOf(root.currentValue));
    root.picked(root.options[(index + 1) % root.options.length]);
  }

  StyledToggle {
    id: toggle
    // Stacked: the segments share the width, as a dropdown under its label
    Layout.fillWidth: root.stacked
    options: root.options
    labels: root.optionLabels
    value: root.currentValue
    onPicked: value => root.picked(value)
  }
}
