pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// An editor inspector's "Options" card for a bar widget's or an overlay
// module's `properties`: a `problem` in the error colour, the form, or
// `emptyText` when the type has no options
FieldGroup {
  id: root

  property var propertiesSchema: ({})
  // Keys shown first, in this order (the schema's `x-order`)
  property var order: []
  property var values: ({})
  // `$` keys for the form's `x-showIf` (SchemaPropertiesForm.context)
  property var context: ({})
  property string numberMode: ""
  // Fields marked `x-beside` beside the one before them (SchemaPropertiesForm)
  property bool pairs: false
  property string problem
  property string emptyText

  signal edited(var path, var value)

  title: I18n.tr("Options")

  StyledText {
    visible: root.problem !== ""
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    text: root.problem
    textColor: Theme.error
  }

  SchemaPropertiesForm {
    id: form
    Layout.fillWidth: true
    propertiesSchema: root.propertiesSchema
    order: root.order
    values: root.values
    context: root.context
    numberMode: root.numberMode
    pairs: root.pairs
    onEdited: (path, value) => root.edited(path, value)
  }

  StyledText {
    wrapMode: Text.WordWrap
    visible: form.rows.length === 0
    text: root.emptyText
    opacity: 0.6
    Layout.fillWidth: true
  }
}
