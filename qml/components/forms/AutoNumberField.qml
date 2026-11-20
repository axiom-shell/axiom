pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// An integer with an automatic value (a schema's `x-auto`): a switch for
// setting it by hand, then the number (a SchemaNumberField) while it is set.
// `auto` is { value, start }: turning the switch on commits `start`, off
// `value`, which may be null (an inheriting setting's); the number shows while
// `current` is neither undefined nor `auto.value`. `fieldSchema` gives the
// number's bounds (`maximum` may narrow it), step (`multipleOf`), unit and, unless `numberMode` is set
// (the form's choice: "stepper"), its `x-control`. `label`, `description`,
// `headerExtra` and `headerBelow` are the switch's FieldHeader's. SchemaField
// and the bar editor's LayoutOverrideField are this; `activate()` is what a
// click on the row off the controls does (the switch).
ColumnLayout {
  id: root

  property string label: ""
  property string description: ""
  property Component headerExtra: null
  property Component headerBelow: null
  property var fieldSchema: ({})
  // The number's maximum: the schema's unless the host narrows it
  // (SchemaField: SchemaLayout.maximum)
  property real maximum: root.fieldSchema.maximum ?? 9999
  // The value as stored (undefined: none)
  property var current: undefined
  // (While a row is torn down its schema can go first)
  property var auto: ({
      "value": 0,
      "start": 0
    })
  property string numberMode: ""

  readonly property bool custom: root.current !== undefined && root.current !== root.auto.value

  // The number as typed, before it is committed
  signal typed(var value)
  // A value to store: the switch's, or the number's (`typed`: from typing)
  signal committed(var value, bool typed)

  // What a click on the row outside its controls does (rowClicked)
  function activate() {
    autoSwitch.activate();
  }

  spacing: Widget.spacing

  SchemaSwitch {
    id: autoSwitch
    label: root.label
    description: root.description
    headerExtra: root.headerExtra
    headerBelow: root.headerBelow
    checked: root.custom
    onToggled: value => root.committed(value ? root.auto.start : root.auto.value, false)
  }

  SchemaNumberField {
    visible: root.custom
    label: ""
    currentConfigValue: root.custom ? root.current : root.auto.start
    // (A null automatic value leaves the whole range to the number)
    minimum: root.auto.value === null ? (root.fieldSchema.minimum ?? 0) : Math.max(root.fieldSchema.minimum ?? 0, root.auto.value + 1)
    maximum: root.maximum
    stepSize: root.fieldSchema.multipleOf ?? 1
    unit: root.fieldSchema["x-unit"] ?? ""
    unitScale: SchemaLayout.unitScale(unit)
    mode: root.numberMode || (root.fieldSchema["x-control"] ?? "auto")
    onValueTyped: value => root.typed(value)
    onCommitted: (value, typed) => root.committed(value, typed)
  }
}
