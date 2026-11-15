pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// One text field of the selected element (its `bind.<slot>`, the Shows
// group): a field to type text in, or a {value} of the output, and a { }
// button picking a path of the output to insert at the cursor (or over the
// selection). Under it what a format reads as in the previewed sample
// ("now: CPU 42%"), or a warning when a {path} in it reads nothing there.
// Empty: the slot falls back to the output's own key (`placeholder` says
// what that is). An InspectorRow: its label above the field, as a schema
// text field's; put the rows of one group in a ColumnLayout with no spacing
// and mark the first `first`.
InspectorRow {
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
  // Where the picked path goes: the cursor (or selection) when the { } button was pressed
  property int insertFrom: 0
  property int insertTo: 0

  belowShown: root.unknown.length > 0 || root.now !== ""

  // Writes the typed text; an empty field removes the key
  function write(text) {
    root.editor.setElement(["bind", root.slot], text === "" ? undefined : text);
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextEntry {
      id: entry
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      placeholderText: root.placeholder
      onTextEdited: root.write(entry.text)

      Binding {
        target: entry
        property: "text"
        value: root.current
        when: !entry.input.activeFocus
        restoreMode: Binding.RestoreNone
      }
    }

    SquareIconButton {
      id: pick
      Layout.alignment: Qt.AlignVCenter
      iconText: "data_object"
      tooltipText: I18n.tr("Insert a value from the output")
      enabled: root.editor.bindPaths.length > 0
      onClicked: {
        root.insertFrom = Math.min(entry.input.selectionStart, entry.input.selectionEnd);
        root.insertTo = Math.max(entry.input.selectionStart, entry.input.selectionEnd);
        picker.openAt(entry);
      }
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

  // A pick is inserted as {path}; an insert isn't `textEdited`, so it writes
  // itself. Labels are the paths as they are
  TypePickerPopup {
    id: picker
    parent: root
    matchWidth: true
    types: root.editor.bindPaths.map(p => ({
          "type": p.path,
          "label": p.path,
          "detail": p.type === "array" ? I18n.tr("a list of {0}", p.value) : p.preview
        }))
    labelOf: type => type.label
    onTypeSelected: path => {
      const insert = "{" + path + "}";
      const text = entry.text.slice(0, root.insertFrom) + insert + entry.text.slice(root.insertTo);
      entry.text = text;
      entry.input.cursorPosition = root.insertFrom + insert.length;
      root.write(text);
    }
  }
}
