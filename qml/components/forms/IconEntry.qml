pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.services.ui
import qs.components.reusable

// An icon picked by name from the icon font or pasted as a glyph: a
// searchable box with the icon drawn in it, and a note under it while the
// value reads as a name the font doesn't have (it then shows as text). The
// value is pushed in (`value`); picking one emits `picked` (the icon
// fields of SchemaField, and each row of the special workspaces' list).
ColumnLayout {
  id: root

  property string value: ""
  // Shown in the empty box
  property string placeholderText: I18n.tr("Search icons, or paste a glyph")

  // The value is a symbol name the font has, or a single glyph
  readonly property bool drawsIcon: Utils.isSymbolName(root.value) ? IconManager.isKnown(root.value) : Array.from(root.value).length === 1

  signal picked(string value)

  spacing: Widget.spacing

  StyledComboEntry {
    Layout.fillWidth: true
    editable: true
    icon: root.drawsIcon ? root.value : ""
    placeholderText: root.placeholderText
    search: query => IconManager.search(query, 60).map(name => ({
            "value": name,
            "label": name,
            "icon": name
          }))
    value: root.value
    onPicked: value => root.picked(value)
  }

  StyledText {
    // Reads as a name, but the font has none by it: drawn as text
    visible: Utils.isSymbolName(root.value) && !IconManager.isKnown(root.value)
    text: I18n.tr("No icon is named \"{0}\": it shows as text", root.value)
    color: Theme.warning
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }
}
