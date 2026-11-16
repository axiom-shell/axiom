pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.services.ui
import qs.components.methods

// Settings by dotted config path ("Apps.networkEditor"), each a SchemaFormRow
// as on the settings page (reset button, `x-link`s), saved as they change
// (SettingsManager.commitValues), for pages that apply as the user goes
// (the onboarder, the Themes page). Edits are gathered for a moment, so
// typing doesn't write config.json per key. Acts as the rows' `form`.
ColumnLayout {
  id: root

  // Dotted config paths
  property var paths: []
  // Titles to show instead of the schema's, by path (English, translated)
  property var titles: ({})

  signal edited(var path, var value)
  // A row's edit (SchemaField's form)
  function edit(path, value) {
    root.edited(path, value);
  }

  readonly property var rows: root.paths.map(dotted => {
    const path = dotted.split(".");
    const schema = SettingsManager.schemaAt(path) ?? {};
    return {
      "kind": schema.type === "array" && schema.items?.properties ? "array" : "field",
      "title": root.titles[dotted] ?? schema.title ?? path[path.length - 1],
      "path": path,
      "schema": schema
    };
  })

  // Edits not saved yet, by dotted path: shown as the value meanwhile
  property var _pending: ({})

  function valueAt(path) {
    const dotted = path.join(".");
    return dotted in root._pending ? root._pending[dotted] : SettingsManager.configValueAt(dotted);
  }

  function flush() {
    if (Object.keys(root._pending).length === 0)
      return;
    const values = root._pending;
    root._pending = {};
    SettingsManager.commitValues(values);
  }

  onEdited: (path, value) => {
    const next = Object.assign({}, root._pending);
    next[path.join(".")] = value;
    root._pending = next;
    saveTimer.restart();
  }

  Component.onDestruction: root.flush()

  Timer {
    id: saveTimer
    interval: 600
    onTriggered: root.flush()
  }

  // The rows pad themselves (FormRow: Style.rowPadding)
  spacing: 0

  // The rows' indent tree (RowTree)
  readonly property var tree: RowTree.plan(root.rows)

  // The top row drawn (FormRow.first)
  readonly property int _firstRow: Utils.firstFormRow(rowItems.count, i => rowItems.itemAt(i))

  Repeater {
    id: rowItems
    model: root.rows

    delegate: SchemaFormRow {
      id: rowItem
      required property var modelData
      required property int index
      row: rowItem.modelData
      form: root
      first: index === root._firstRow
      level: root.tree.levels[index]
      // The reset to default, as on the settings page; its edits save at
      // once, so no dot
      reset: value => root.edit(rowItem.modelData.path, value)
    }
  }
}
