pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.reusable

// An editor inspector's "Options" card for a bar widget's or an overlay
// module's `properties`: the form, or `emptyText` when the type has no options
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
  // Each field's change marks (SchemaPropertiesForm.changedAt)
  property var changedAt: null
  // Each field's action (SchemaPropertiesForm.fieldAction)
  property var fieldAction: null
  // Each field's note (SchemaPropertiesForm.fieldNote)
  property var fieldNote: null
  property string emptyText

  signal edited(var path, var value)
  signal discardAt(var path)

  // The pane's one group of settings: a title-less card (no heading, never
  // folds) unless its host names it (the bar editor's Popout card)
  title: ""

  SchemaPropertiesForm {
    id: form
    Layout.fillWidth: true
    propertiesSchema: root.propertiesSchema
    order: root.order
    values: root.values
    context: root.context
    numberMode: root.numberMode
    pairs: root.pairs
    changedAt: root.changedAt
    fieldAction: root.fieldAction
    fieldNote: root.fieldNote
    onEdited: (path, value) => root.edited(path, value)
    onDiscardAt: path => root.discardAt(path)
  }

  StyledText {
    visible: form.rows.length === 0
    text: root.emptyText
    tone: "faint"
    Layout.fillWidth: true
  }
}
