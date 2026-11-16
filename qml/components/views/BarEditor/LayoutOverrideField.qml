pragma ComponentBehavior: Bound
import QtQuick
import qs.components.forms

// One optional sizing override of a bar widget (a WidgetLayout key), a form
// row in the schema's automatic-number shape (SchemaField's `x-auto`): a
// switch for setting it by hand, then the stepper (the AutoNumberField both
// share). Unset leaves the widget's own sizing, so no number shows that would
// read as a real value. A null and an undefined `value` both mean unset;
// unsetting emits undefined.
FormRow {
  id: root

  required property string key
  required property var fieldSchema
  // The override, or undefined (or null) for none
  property var value: undefined
  // What overriding starts at
  property int initial: 0

  // Sets the override; undefined removes it
  signal edited(var value)

  readonly property bool isSet: root.value !== undefined && root.value !== null

  activates: autoNumber
  bodyHeight: autoNumber.implicitHeight

  AutoNumberField {
    id: autoNumber
    width: parent.width
    label: root.fieldSchema.title ?? root.key
    description: root.fieldSchema.description ?? ""
    fieldSchema: root.fieldSchema
    current: root.value ?? null
    auto: ({
        "value": null,
        "start": root.initial
      })
    // The bar editor uses steppers throughout
    numberMode: "stepper"
    onCommitted: value => {
      if (value === null)
        root.edited(undefined);
      else if (value !== root.value)
        root.edited(value);
    }
  }
}
