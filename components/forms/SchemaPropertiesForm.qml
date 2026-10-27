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

  // Emitted with the key ([key]) of the edited field and its value: a
  // nested object's field as the whole object
  signal edited(var path, var value)

  // Depends on the schema only, so edits update the rows in place
  readonly property var rows: Object.keys(root.propertiesSchema ?? {}).sort((a, b) => {
    const rank = key => {
      const index = (root.order ?? []).indexOf(key);
      return index < 0 ? Infinity : index;
    };
    return rank(a) - rank(b);
  }).reduce((rows, key) => rows.concat(SchemaLayout.rows({
      "properties": {
        [key]: root.propertiesSchema[key]
      }
    }, []).filter(row => row.kind !== "group")), [])

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

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    rowSpacing: root.spacing

    Repeater {
      id: fields
      model: root.rows

      // The field, then its `x-link`s
      delegate: ColumnLayout {
        id: cell
        required property var modelData
        required property int index
        // SchemaField hides itself for `x-showIf`; follow it so the layout
        // doesn't keep its space (`shown`, not `visible`: that would read
        // false forever once this cell hides)
        readonly property bool shown: field.item?.shown ?? false
        readonly property bool _beside: modelData.schema?.["x-beside"] === true
        // Read again once every field exists (`count` changes after the
        // Repeater made them): itemAt doesn't notify, and the field after
        // this one doesn't exist yet when it's made
        readonly property var _partner: fields.count < 0 ? null : _beside ? fields.itemAt(index - 1) : root.rows[index + 1]?.schema?.["x-beside"] === true ? fields.itemAt(index + 1) : null
        readonly property bool half: root.pairs && (_partner?.shown ?? false)
        Layout.fillWidth: true
        Layout.columnSpan: half ? 1 : 2
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        visible: shown
        spacing: Widget.spacing / 2

        // Loaded by URL: SchemaField (through SchemaObjectArray and
        // SchemaArrayItem) instantiates this type, so naming it here would
        // make the types depend on each other. Streamed: a page's forms
        // fill in over the frames after it opens
        StreamedLoader {
          id: field
          Layout.fillWidth: true
          label: "form field"
          Component.onCompleted: setSource(Qt.resolvedUrl("SchemaField.qml"), {
            "row": cell.modelData,
            "form": root
          })
        }

        FieldLinks {
          Layout.fillWidth: true
          links: cell.modelData.schema?.["x-link"]
        }
      }
    }
  }
}
