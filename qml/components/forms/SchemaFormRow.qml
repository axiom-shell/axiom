pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A schema field as a row of a card (a FoldFormRow with `fold` off, so a
// FormRow that draws the field): the SchemaField for `row` in the form
// `form`, with its change marks after the label (a button putting it back to
// the schema default, a dot while it has an unsaved edit: FieldChangeMarks)
// and under it the field's `x-link`s and `action` (FieldLinks, a
// SettingsLink). SchemaPropertiesForm's cells, SettingRows' rows and the
// settings page's SettingsField are all this, so the marks and links are the
// same everywhere. The field is built by URL (SchemaField, through
// SchemaObjectArray and SchemaArrayItem, instantiates this type, so naming it
// here would make the types depend on each other) and streamed only where a
// host asks (`stream`: SchemaPropertiesForm's cells; the others build the
// field with the row). `shown` is the host's: `fieldShown` is the field's own
// (undefined until it streams in, when `stream` is on).
FoldFormRow {
  id: root

  required property var row
  required property var form
  // An unsaved edit: the dot
  property bool changed: false
  // Hooks for the marks: `reset(value)` writes the schema default back,
  // `discard()` drops the unsaved edit. Both null hides the marks
  property var reset: null
  property var discard: null
  // { text, icon, run } for a link under the field (SettingsLink), or null
  property var action: null
  // Off: the field draws nothing (the host draws the row itself); its
  // `fieldShown` still holds
  property bool fieldActive: true
  // The field fills in from the build queue: a long form's rows; off, it is
  // built with the row, so `shown` is known at once
  property bool stream: false
  // What the host puts under the field, and its height (SettingsField's
  // integration hookup and footprint line)
  property real extraHeight: 0
  property alias below: extra.data

  // The field's own: whether it shows (undefined until it is built), its
  // value, its height and its least width (FieldFit.least)
  readonly property var fieldItem: field.item
  readonly property var fieldShown: root.fieldItem ? root.fieldItem.shown : undefined
  readonly property var current: root.form?.valueAt(root.row.path)
  readonly property real fieldHeight: field.implicitHeight
  readonly property real leastWidth: root.fieldItem?.leastWidth ?? 0

  fold: false
  shown: root.fieldShown
  bodyHeight: root.fieldHeight + root.extraHeight
  railHeight: root.fieldHeight
  hitHeight: root.fieldHeight
  // A click on a switch, toggle or dropdown row acts (SchemaField)
  tinted: root.fieldItem?.tinted ?? false
  hoverable: root.fieldItem?.hoverable ?? false
  onRowClicked: root.fieldItem?.rowClicked()

  StreamedLoader {
    id: field
    width: parent.width
    rise: false
    stream: root.stream
    label: "form field"
    // Kept drawn while the row folds shut (the row hides once it has)
    Component.onCompleted: setSource(Qt.resolvedUrl("SchemaField.qml"), {
      "row": root.row,
      "form": root.form,
      "headerExtra": Qt.binding(() => root.reset !== null || root.discard !== null ? marks : null),
      "headerBelow": Qt.binding(() => root.row.schema?.["x-link"] || root.action !== null ? linksComp : null),
      "active": Qt.binding(() => root.fieldActive),
      "visible": true
    })
  }

  Item {
    id: extra
    y: root.fieldHeight
    width: parent.width
    height: root.extraHeight
  }

  Component {
    id: marks
    FieldChangeMarks {
      readonly property var _field: root.fieldItem
      schema: root.row.schema
      current: _field?.current
      optionLabels: _field?.optionLabels ?? ({})
      changed: root.changed
      onReset: value => root.reset?.(value)
      onDiscard: root.discard?.()
    }
  }

  // The field's `x-link`s and action, read with its label (FieldHeader.below)
  Component {
    id: linksComp
    ColumnLayout {
      readonly property bool shows: links.shows || actionLink.active
      spacing: Widget.spacing / 2

      FieldLinks {
        id: links
        Layout.fillWidth: true
        links: root.row.schema?.["x-link"]
      }

      // Made only for a field with an action, not under every field
      Loader {
        id: actionLink
        readonly property var action: root.action
        Layout.fillWidth: true
        active: actionLink.action !== null
        visible: active
        sourceComponent: SettingsLink {
          text: actionLink.action?.text ?? ""
          icon: actionLink.action?.icon ?? ""
          run: actionLink.action?.run ?? null
        }
      }
    }
  }
}
