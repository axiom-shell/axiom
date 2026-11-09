pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.reusable

// A form for one object, generated from its `properties` schema: one
// SchemaField per key (keys marked `x-settings: false` skipped), a nested
// object's (a screen target, a shadow) in its place, valued from `values`
// with schema defaults for what's missing. Used for array items, bar
// widget options and overlay module options; it acts as the `form` for
// its SchemaField rows.
ColumnLayout {
  id: root

  // { key: propertySchema }
  required property var propertiesSchema
  property var values: ({})
  // What `$` keys in an `x-showIf` read, by key (a bar widget's
  // `$bar.<key>`: BarsConfig.lookContext)
  property var context: ({})
  // Keys to put first, in this order (the schema's `x-order`): the schema
  // reaches QML as a map, whose keys come out sorted
  property var order: []
  // Forces every integer row's control ("slider" or "stepper"), over the
  // schema's `x-control`; empty leaves it to each field
  property string numberMode: ""
  // Puts a field marked `x-beside` beside the one before it, each half wide,
  // while both are shown; off, every field takes the whole width
  property bool pairs: false
  // Keeps its main rows in place: a field marked `x-keepsPlace` whose
  // `x-showIf` fails is greyed, saying why on hover (its `x-tileHint`),
  // instead of hidden, so they never move under the pointer
  // (SchemaField.placeKept; the Bar style block). Other fields hide
  property bool keepsPlace: false
  // A hook giving a tiles field's previews: given its path ([key]),
  // { component, properties }, each tile's preview made from `component`
  // with the option's `value` and `properties` (ChoiceTiles.preview,
  // previewProperties), or null for none (the Bar style block's samples)
  property var tilePreview: null
  // Gives each field its change marks (FieldChangeMarks: reset to the
  // default, and a dot while it has an unsaved edit) when set: a hook
  // telling whether the field at a path ([key]) has one. null: no marks
  property var changedAt: null

  // Emitted with the key ([key]) of the edited field and its value: a
  // nested object's field as the whole object
  signal edited(var path, var value)
  // A field's unsaved-edit dot was clicked (with `changedAt`)
  signal discardAt(var path)

  // Keys an icon field draws in its own row (`x-iconText`): no rows of
  // their own. Not `x-rowDraws`, nor an `x-row` object's own row: an
  // `x-row` is drawn only on the settings page, so here the keys it names,
  // and the fields of an object it draws, keep their own rows
  readonly property var _drawn: Object.values(root.propertiesSchema ?? {}).reduce((keys, prop) => keys.concat(SchemaLayout.iconTextKeys(prop)), [])
  // Depends on the schema only, so edits update the rows in place
  readonly property var rows: Object.keys(root.propertiesSchema ?? {}).filter(key => !root._drawn.includes(key)).sort((a, b) => {
    const rank = key => {
      const index = (root.order ?? []).indexOf(key);
      return index < 0 ? Infinity : index;
    };
    return rank(a) - rank(b);
  }).reduce((rows, key) => rows.concat(SchemaLayout.rows({
      "properties": {
        [key]: root.propertiesSchema[key]
      }
    }, []).filter(row => row.kind !== "group" && row.kind !== "object")), [])

  function valueAt(path) {
    return Utils.valueAt(root.values, path) ?? SchemaLayout.defaultAt({
      "properties": root.propertiesSchema
    }, path);
  }

  // A row's edit (SchemaField's form): a nested field's as its whole
  // top-level object
  function edit(path, value) {
    if (path.length === 1) {
      root.edited(path, value);
      return;
    }
    const top = Utils.clone(root.valueAt([path[0]]) ?? {});
    let node = top;
    for (const key of path.slice(1, -1)) {
      node[key] = node[key] ?? {};
      node = node[key];
    }
    node[path[path.length - 1]] = value;
    root.edited([path[0]], top);
  }

  spacing: Widget.spacing

  // The top row drawn (FormRow.first)
  readonly property int _firstRow: Utils.firstFormRow(fields.count, i => fields.itemAt(i))

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    // The rows keep their gaps themselves (FormRow.dividerGap)
    rowSpacing: 0

    Repeater {
      id: fields
      model: root.rows

      // The field, then its `x-link`s, as a FormRow
      delegate: FormRow {
        id: cell
        required property var modelData
        required property int index
        // Unknown until the field streams in, so it takes its height then
        // rather than folding open
        shown: field.item ? field.item.shown : undefined
        indented: field.item?.followsSibling ?? false
        bodyHeight: column.implicitHeight
        readonly property bool _beside: modelData.schema?.["x-beside"] === true
        // Read again once every field exists (`count` changes after the
        // Repeater made them): itemAt doesn't notify, and the field after
        // this one doesn't exist yet when it's made
        readonly property var _partner: fields.count < 0 ? null : _beside ? fields.itemAt(index - 1) : root.rows[index + 1]?.schema?.["x-beside"] === true ? fields.itemAt(index + 1) : null
        readonly property bool half: root.pairs && _partner?.shown === true
        // Beside the top row, it's on the top line too
        first: index === root._firstRow || (half && _beside && index - 1 === root._firstRow)
        Layout.columnSpan: half ? 1 : 2
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop

        ColumnLayout {
          id: column
          width: parent.width
          spacing: Widget.spacing / 2

          // Loaded by URL: SchemaField (through SchemaObjectArray and
          // SchemaArrayItem) instantiates this type, so naming it here would
          // make the types depend on each other. Streamed: a page's forms
          // fill in over the frames after it opens. Kept drawn while the
          // row folds shut (the row hides once it has)
          StreamedLoader {
            id: field
            Layout.fillWidth: true
            label: "form field"
            Component.onCompleted: setSource(Qt.resolvedUrl("SchemaField.qml"), {
              "row": cell.modelData,
              "form": root,
              "headerExtra": root.changedAt ? marks : null,
              "visible": true
            })
          }

          Component {
            id: marks
            FieldChangeMarks {
              readonly property var _field: field.item
              schema: cell.modelData.schema
              current: _field?.current
              optionLabels: _field?.optionLabels ?? ({})
              // The form is gone (null) a moment before its fields
              changed: root?.changedAt ? root.changedAt(cell.modelData.path) : false
              onReset: value => root.edit(cell.modelData.path, value)
              onDiscard: root.discardAt(cell.modelData.path)
            }
          }

          FieldLinks {
            Layout.fillWidth: true
            links: cell.modelData.schema?.["x-link"]
          }
        }
      }
    }
  }
}
