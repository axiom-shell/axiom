pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.forms

// The Workspaces card's start cell row (Workspaces.startColumn's `x-row`,
// drawing startRow too): one switch, off the grid's middle (both null), on
// a column and a row stepper side by side, each from 1 to the grid's
// columns or rows (`x-maximumFrom`). Turning it on fills an unset one with
// the middle (WorkspaceGeometry.middleOf), so the start doesn't move until
// a stepper does. Edits go through the settings form.
// I18n.tr("Start cell")
// I18n.tr("Column")
// I18n.tr("Row")
ColumnLayout {
  id: root

  // The settings row (SettingsField's `x-row`) and its form
  property var row: null
  property var form: null

  Layout.fillWidth: true
  spacing: Widget.spacing

  readonly property var _parent: root.row ? root.row.path.slice(0, -1) : []
  readonly property var _columnPath: root.row ? root.row.path : []
  readonly property var _rowPath: root._parent.concat(["startRow"])
  readonly property var _valueOf: key => root.form?.valueAt(SchemaLayout.keyPath(root._parent, key))

  // As edited; null: the middle
  readonly property var column: root.form?.valueAt(root._columnPath) ?? null
  readonly property var startRow: root.form?.valueAt(root._rowPath) ?? null
  readonly property bool chosen: root.column !== null || root.startRow !== null
  readonly property int columns: root._valueOf("columns") ?? 1
  readonly property int rows: root._valueOf("rows") ?? 1

  // `x-enabledIf`, as a generated row's (SchemaField.allowed)
  readonly property bool allowed: !root.form || root.form.conditionHolds(root.row?.schema?.["x-enabledIf"], root._parent)
  enabled: root.allowed
  opacity: root.allowed ? 1 : Style.opacityDisabled

  function _set(column, row) {
    root.form.edit(root._columnPath, column);
    root.form.edit(root._rowPath, row);
  }

  SchemaSwitch {
    Layout.fillWidth: true
    label: I18n.tr("Start cell")
    description: root.row?.schema?.description ?? ""
    checked: root.chosen
    onToggled: value => value ? root._set(root.column ?? WorkspaceGeometry.middleOf(root.columns), root.startRow ?? WorkspaceGeometry.middleOf(root.rows)) : root._set(null, null)
  }

  RowLayout {
    visible: root.chosen
    Layout.fillWidth: true
    spacing: Widget.spacing * 2

    SchemaNumberField {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: I18n.tr("Column")
      currentConfigValue: root.column ?? WorkspaceGeometry.middleOf(root.columns)
      minimum: 1
      maximum: SchemaLayout.maximum(root.row?.schema, root._valueOf)
      mode: "stepper"
      onValueTyped: value => root.form.typed(root._columnPath, value)
      onCommitted: value => root.form.edit(root._columnPath, value)
    }

    SchemaNumberField {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: I18n.tr("Row")
      currentConfigValue: root.startRow ?? WorkspaceGeometry.middleOf(root.rows)
      minimum: 1
      maximum: SchemaLayout.maximum(SettingsManager.schemaAt(root._rowPath), root._valueOf)
      mode: "stepper"
      onValueTyped: value => root.form.typed(root._rowPath, value)
      onCommitted: value => root.form.edit(root._rowPath, value)
    }
  }
}
