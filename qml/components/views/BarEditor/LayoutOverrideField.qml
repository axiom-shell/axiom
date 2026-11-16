pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.forms

// One optional sizing override of a bar widget (a WidgetLayout key), a form
// row in the schema's automatic-number shape (SchemaField's `x-auto`): a
// switch for setting it by hand, then the stepper. Unset leaves the widget's
// own sizing, so no number shows that would read as a real value. A null and
// an undefined `value` both mean unset; unsetting emits undefined.
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

  activates: overrideSwitch
  bodyHeight: body.implicitHeight

  ColumnLayout {
    id: body
    width: parent.width
    spacing: Widget.spacing

    SchemaSwitch {
      id: overrideSwitch
      label: root.fieldSchema.title ?? root.key
      description: root.fieldSchema.description ?? ""
      checked: root.isSet
      onToggled: value => root.edited(value ? root.initial : undefined)
    }

    SchemaNumberField {
      visible: root.isSet
      label: ""
      currentConfigValue: root.isSet ? root.value : root.initial
      minimum: root.fieldSchema.minimum ?? 0
      maximum: root.fieldSchema.maximum ?? 9999
      unit: root.fieldSchema["x-unit"] ?? ""
      unitScale: SchemaLayout.unitScale(unit)
      // The bar editor uses steppers throughout
      mode: "stepper"
      onCommitted: value => {
        if (root.isSet && value !== root.value)
          root.edited(value);
      }
    }
  }
}
