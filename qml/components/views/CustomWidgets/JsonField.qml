pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// Custom widgets page: a JSON value of the selected definition at `path`
// (a key, or a path of keys), a form row (InspectorRow: its label and
// description above a monospace area, as a schema text field's), written to
// it once it parses (CustomWidgetsEditor.set); "Not valid JSON yet." under it
// while it doesn't. Read once, as it's built: the page builds it again for
// each definition it shows.
InspectorRow {
  id: root

  required property var editor
  // The selected definition (CustomWidgetsEditor.selected)
  property var definition: null
  // Where the value is in the definition: a key, or a list of keys
  property var path: ""
  property bool bad: false

  readonly property var _keys: Array.isArray(root.path) ? root.path : [root.path]

  belowShown: root.bad

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

  below: StyledText {
    Layout.fillWidth: true
    text: I18n.tr("Not valid JSON yet.")
    tone: "warning"
    role: "caption"
    overflow: "wrap"
  }
}
