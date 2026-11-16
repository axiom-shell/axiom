pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.components.methods

// A choice from a list: the box on its label's line when that fits beside
// it, else under it (a FieldLine, kind flex)
FieldLine {
  id: root
  required property var options
  required property string currentValue
  // Options are color names (Style.resolve): each row is painted in the
  // color it names (an empty one, automatic, shows its label)
  property bool swatches: false
  // value -> label shown for it; values without one are shown translated
  property var optionLabels: ({})
  function optionLabel(value) {
    return root.optionLabels?.[value] ?? I18n.tr(value);
  }
  // A swatch shows its color's name unless it's labelled (Auto, the default)
  function swatchLabel(value) {
    return root.swatches && value && !root.optionLabels?.[value] ? value : root.optionLabel(value);
  }

  // The choices as StyledComboEntry takes them; a swatch's label ink is
  // picked here once per option, never per delegate
  readonly property var _entries: root.options.map(value => {
    const named = root.swatches && value !== "";
    return {
      "value": value,
      "label": root.swatchLabel(value),
      "swatch": named ? value : "",
      "swatchInk": named ? String(Tone.bestOn(Style.resolve(value))) : "" // style-exempt: a swatch row shows the colour it names, its ink is picked once per option, here
    };
  })

  // What a click on the whole row does (SchemaField.rowClicked)
  function activate() {
    entry.toggleFromRow();
  }

  signal selectionChanged(string newValue)

  kind: "flex"

  StyledComboEntry {
    id: entry
    Layout.fillWidth: true
    options: root._entries
    value: root.currentValue
    onPicked: value => root.selectionChanged(value)
  }
}
