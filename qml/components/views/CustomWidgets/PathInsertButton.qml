pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// The { } button beside a text field of the custom widgets editor (a Shows
// field, a trigger's Argument): picks a path of the output (the editor's
// bindPaths) and inserts it as {path} at the field's cursor, or over its
// selection, then says the whole new text on `inserted` (an insert isn't
// `textEdited`, so the owner writes it). Disabled with the reason in its
// tooltip while the output has no paths yet. The list spans the entry's row
// (its parent).
SquareIconButton {
  id: root

  // The StyledTextEntry it inserts into
  required property var entry
  readonly property var editor: CustomWidgetsManager.editor
  // The row holding the entry and this button: the list opens under it, as
  // wide as it
  readonly property Item row: root.parent ?? root.entry
  // Where the picked path goes: the cursor (or selection) when the button was pressed
  property int insertFrom: 0
  property int insertTo: 0

  // The field's whole text with the path inserted
  signal inserted(string text)

  Layout.alignment: Qt.AlignVCenter
  iconText: "data_object"
  enabled: root.editor.bindPaths.length > 0
  tooltipText: root.enabled ? I18n.tr("Insert a value from the output") : I18n.tr("No output yet: run the script or keep a sample")
  onClicked: {
    root.insertFrom = Math.min(root.entry.input.selectionStart, root.entry.input.selectionEnd);
    root.insertTo = Math.max(root.entry.input.selectionStart, root.entry.input.selectionEnd);
    picker.openAt(root.row);
  }

  // Labels are the paths as they are
  TypePickerPopup {
    id: picker
    parent: root.row
    matchWidth: true
    types: root.editor.bindPaths.map(p => ({
          "type": p.path,
          "label": p.path,
          "detail": p.type === "array" ? I18n.tr("a list of {0}", p.value) : p.preview
        }))
    labelOf: type => type.label
    onTypeSelected: path => {
      const insert = "{" + path + "}";
      const text = root.entry.text.slice(0, root.insertFrom) + insert + root.entry.text.slice(root.insertTo);
      root.entry.text = text;
      root.entry.input.cursorPosition = root.insertFrom + insert.length;
      root.inserted(text);
    }
  }
}
