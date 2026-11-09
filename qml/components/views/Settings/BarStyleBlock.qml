pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services.ui
import qs.components.forms

// The Bar style card's row (Bars.style's `x-row`), drawing every style
// setting: for now one form over the style's fields, each edit, change
// mark and discard through the settings draft as the page's own rows
ColumnLayout {
  id: root

  // The settings row (SettingsField's `x-row`) and its form
  required property var row
  required property var form

  Layout.fillWidth: true

  SchemaPropertiesForm {
    Layout.fillWidth: true
    propertiesSchema: root.row.schema.properties
    order: root.row.schema["x-order"] ?? []
    pairs: true
    values: root.form.valueAt(root.row.path) ?? ({})
    changedAt: path => SettingsManager.isChanged(root.row.path.concat(path))
    onEdited: (path, value) => root.form.edit(root.row.path.concat(path), value)
    onDiscardAt: path => {
      EditsManager.discardTypingIn(root);
      SettingsManager.discard([root.row.path.concat(path)]);
    }
  }
}
