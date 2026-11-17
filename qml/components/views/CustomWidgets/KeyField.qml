pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// The key a colour rule or Visible reads (Color by state, Visible): a typed
// choice of the output's paths (`keys`) that takes anything typed. Empty is
// what the element shows itself. The owner sets `value`, and writes on
// `picked`.
StyledComboEntry {
  id: root

  // The paths offered, as the editor lists them (editor.bindPaths)
  property var keys: []

  editable: true
  placeholderText: I18n.tr("What it shows")
  options: [
    {
      "value": "",
      "label": I18n.tr("What it shows")
    }
  ].concat(root.keys.map(key => ({
        "value": key,
        "label": key
      })))
}
