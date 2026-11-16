import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.forms

// A stand-in for a SchemaPropertiesForm (the real one needs the services):
// what FieldGroup reads of it, `leads` and `allHidden`, and rows placed at
// the given indent levels, as RowTree gives them to the form
ColumnLayout {
  id: form

  property bool leads: false
  property bool allHidden: false
  property var levels: []

  Layout.fillWidth: true
  spacing: 0

  Repeater {
    model: form.levels

    FormRow {
      required property int modelData
      required property int index
      level: modelData
      first: index === 0
      bodyHeight: Widget.height

      Item {
        objectName: "probe"
        width: 10
        height: 10
      }
    }
  }
}
