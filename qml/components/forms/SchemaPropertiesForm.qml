pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

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
  // The form sits under another row of the same box, so its top row keeps
  // its divider (a hand-built row above it: the custom widgets' Command)
  property bool follows: false
  // A hook giving a field an action, drawn as a link under it
  // (SettingsLink's `run`): given its path ([key], or [key, field] in a
  // nested object) and schema, { text, icon, run } or null for none (the
  // edge menu pickers' New menu…)
  property var fieldAction: null

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
  // The rows' indent tree (RowTree)
  readonly property var tree: RowTree.plan(root.rows)
  // Behind a shut fold row (FoldFormRow): every row hidden
  property bool folded: false

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

  // Every row is known hidden (a row still streaming in counts as shown):
  // its FieldGroup hides with it. Read through `count` as `_firstRow` is
  readonly property bool allHidden: {
    if (root.rows.length === 0)
      return true;
    if (fields.count <= 0)
      return false;
    for (let i = 0; i < fields.count; i++) {
      if (fields.itemAt(i)?.shown !== false)
        return false;
    }
    return true;
  }

  // The top row drawn (FormRow.first)
  readonly property int _firstRow: root.follows ? -1 : Utils.firstFormRow(fields.count, i => fields.itemAt(i))

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    // The rows pad themselves (FormRow: Style.rowPadding)
    rowSpacing: 0

    Repeater {
      id: fields
      model: root.rows

      // The field, then its `x-link`s and action, as a FormRow
      delegate: SchemaFormRow {
        id: cell
        required property var modelData
        required property int index
        row: cell.modelData
        form: root
        stream: true
        // Unknown until the field streams in, so it takes its height then
        // rather than folding open
        shown: root.folded ? false : cell.fieldShown
        level: root.tree.levels[index]
        beside: _beside && half
        // The form is gone (null) a moment before its fields
        changed: root?.changedAt ? root.changedAt(cell.modelData.path) : false
        reset: root?.changedAt ? value => root.edit(cell.modelData.path, value) : null
        discard: root?.changedAt ? () => root.discardAt(cell.modelData.path) : null
        action: root?.fieldAction ? root.fieldAction(cell.modelData.path, cell.modelData.schema) : null
        readonly property bool _beside: modelData.schema?.["x-beside"] === true
        // Read again once every field exists (`count` changes after the
        // Repeater made them): itemAt doesn't notify, and the field after
        // this one doesn't exist yet when it's made
        readonly property var _partner: fields.count < 0 ? null : _beside ? fields.itemAt(index - 1) : root.rows[index + 1]?.schema?.["x-beside"] === true ? fields.itemAt(index + 1) : null
        // The left half of a pair (its body is indented by its depth; the
        // right half is `beside`: none of its own)
        readonly property var _left: _beside ? _partner : cell
        // Side by side only while both halves keep their least width
        // (FieldFit.pairFits); else each takes the whole width
        readonly property bool half: root.pairs && _partner?.shown === true && FieldFit.pairFits(root.width - 2 * (_left?.indent ?? 0), Widget.spacing * 2, cell.leastWidth, _partner?.leastWidth ?? 0)
        // Beside the top row, it's on the top line too
        first: index === root._firstRow || (half && _beside && index - 1 === root._firstRow)
        Layout.columnSpan: half ? 1 : 2
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
      }
    }
  }
}
