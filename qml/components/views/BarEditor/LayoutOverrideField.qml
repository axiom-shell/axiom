pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// One optional sizing override of a bar widget (a WidgetLayout key), a form
// row. Unset it leaves the widget's own sizing, so it shows an "Override" button
// rather than a number that would read as a real value.
FormRow {
  id: root

  required property string key
  required property var fieldSchema
  // The override, or undefined for none
  property var value: undefined
  // What overriding starts at
  property int initial: 0

  // Sets the override; undefined removes it
  signal edited(var value)

  readonly property bool isSet: root.value !== undefined && root.value !== null

  bodyHeight: body.implicitHeight

  Item {
    id: body
    width: parent.width
    implicitHeight: root.isSet ? setRow.implicitHeight : unsetRow.implicitHeight

    RowLayout {
      id: unsetRow
      width: parent.width
      visible: !root.isSet
      spacing: Widget.spacing

      FieldHeader {
        label: root.fieldSchema.title ?? root.key
        description: root.fieldSchema.description ?? ""
      }

      StyledTextButton {
        text: I18n.tr("Override")
        onClicked: root.edited(root.initial)
      }
    }

    RowLayout {
      id: setRow
      width: parent.width
      visible: root.isSet
      spacing: Widget.spacing

      SchemaNumberField {
        Layout.fillWidth: true
        label: root.fieldSchema.title ?? root.key
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

      SquareIconButton {
        Layout.alignment: Qt.AlignBottom
        kind: "text"
        iconText: "close"
        tooltipText: root.key === "priority" ? I18n.tr("Use its type's priority") : I18n.tr("Use the widget's own sizing")
        onClicked: root.edited(undefined)
      }
    }
  }
}
