pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// One text field of the selected element (its `bind.<slot>`, the Shows
// group): a field to type text in, or a {value} of the output, and a { }
// button (PathInsertButton) picking a path of the output to insert at the
// cursor (or over the selection). Under it what a format reads as in the previewed sample
// ("now: CPU 42%"), or a warning when a {path} in it reads nothing there.
// Empty: the slot falls back to the output's own key (`placeholder` says
// what that is). A FieldRow: its label above the field, as a schema
// text field's; put the rows of one group in a FormColumn.
FieldRow {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  // The element's key this field writes
  property string slot: ""
  property string placeholder: ""

  readonly property string current: root.editor.element?.bind?.[root.slot] ?? ""
  readonly property var sample: root.editor.previewFields
  // The {paths} in it that read nothing in the previewed sample
  readonly property var unknown: root.sample ? CustomWidgetData.unknownPaths(root.sample, root.current) : []
  // What it reads as, for a format: "" when it has no { } or reads nothing yet
  readonly property string now: root.sample && root.current.indexOf("{") >= 0 && root.unknown.length === 0 ? CustomWidgetData.asText(CustomWidgetData.elementValue(root.sample, root.current)) : ""

  belowShown: root.unknown.length > 0 || root.now !== ""

  // Writes the typed text; an empty field removes the key
  function write(text) {
    root.editor.setElement(["bind", root.slot], text === "" ? undefined : text);
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    CommitEntry {
      id: textEntry
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      live: true
      value: root.current
      placeholderText: root.placeholder
      onEdited: text => root.write(text)
    }

    PathInsertButton {
      entry: textEntry
      onInserted: text => root.write(text)
    }
  }

  below: [
    StyledText {
      visible: root.unknown.length > 0 || root.now !== ""
      Layout.fillWidth: true
      text: root.unknown.length > 0 ? I18n.tr("{0} isn't in the previewed sample", "{" + root.unknown[0] + "}") : I18n.tr("now: {0}", root.now)
      role: "caption"
      tone: root.unknown.length > 0 ? "warning" : "muted"
      textFamily: root.unknown.length > 0 ? Appearance.fontFamily : "monospace"
      overflow: "line"
    }
  ]
}
