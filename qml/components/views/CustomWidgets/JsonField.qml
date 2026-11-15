pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// Custom widgets page: a JSON value of the selected definition at `path`
// (a key, or a path of keys), typed in a monospace area and written to it
// once it parses (CustomWidgetsEditor.set). Read once, as it's built: the
// page builds it again for each definition it shows.
ColumnLayout {
  id: root

  required property var editor
  // The selected definition (CustomWidgetsEditor.selected)
  property var definition: null
  property string label
  property string description
  // Where the value is in the definition: a key, or a list of keys
  property var path: ""
  property bool bad: false

  readonly property var _keys: Array.isArray(root.path) ? root.path : [root.path]

  Layout.fillWidth: true
  spacing: Widget.spacing / 2

  StyledText {
    text: root.label
  }
  StyledTextArea {
    id: area
    Layout.fillWidth: true
    expandable: true
    input.font.family: "monospace"
    onTextEdited: {
      try {
        const value = JSON.parse(area.text.trim() || "{}");
        root.bad = false;
        root.editor.set(root._keys, value);
      } catch (e) {
        root.bad = true;
      }
    }
    Component.onCompleted: area.text = JSON.stringify(root._keys.reduce((node, key) => node?.[key], root.definition) ?? {})
  }
  StyledText {
    Layout.fillWidth: true
    text: root.bad ? I18n.tr("Not valid JSON yet.") : root.description
    tone: root.bad ? "warning" : "faint"
    role: "caption"
    overflow: "wrap"
  }
}
