pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
import qs.components.reusable

// The editor of a field that holds the id of something defined elsewhere
// (`x-ref`, `kind`: "specialWorkspace"): a dropdown of those that exist
// (SettingsManager.refOptions, each with the name it was given) that also
// takes a new id typed, which commits (`committed`) only when it is valid for
// the kind (SettingsManager.refValid). Anything else typed shows the value
// again. A field in a schema form (SchemaField) and the Keybinds inspector
// use it.
StyledComboEntry {
  id: root

  property string kind: ""

  // A valid id, picked or typed
  signal committed(string value)

  editable: true
  placeholderText: I18n.tr("New special workspace id")
  options: {
    const labels = SettingsManager.refLabels(root.kind);
    return SettingsManager.refOptions(root.kind).map(id => ({
          "value": id,
          "label": labels[id] !== undefined ? id + "  ·  " + labels[id] : id
        }));
  }

  onPicked: value => {
    if (SettingsManager.refValid(root.kind, value))
      root.committed(value);
  }
}
