pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// i18n: keys from the schema (WidgetLayout titles, descriptions)
// One optional sizing override of a bar widget (a WidgetLayout key). Unset
// it leaves the widget's own sizing, so it shows an "Override" button
// rather than a number that would read as a real value.
ColumnLayout {
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

  Layout.fillWidth: true
  spacing: Widget.spacing

  RowLayout {
    Layout.fillWidth: true
    visible: !root.isSet
    spacing: Widget.spacing

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2

      StyledText {
        wrapMode: Text.WordWrap
        text: I18n.tr(root.fieldSchema.title ?? root.key)
        Layout.fillWidth: true
      }

      StyledText {
        visible: !!root.fieldSchema.description
        text: root.fieldSchema.description ? I18n.tr(root.fieldSchema.description) : ""
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    StyledTextButton {
      text: I18n.tr("Override")
      textPadding: Widget.smallPadding
      onClicked: root.edited(root.initial)
    }
  }

  RowLayout {
    Layout.fillWidth: true
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
      size: Widget.height
      iconText: "close"
      hoverColor: Theme.error
      tooltipText: I18n.tr("Use the widget's own sizing")
      onClicked: root.edited(undefined)
    }
  }
}
