pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Entry element: a text field that runs the element's
// action with the typed text on Return (the named action, else its submit
// command, {value} the text, already quoted). The text is cleared once it
// ran, unless `clear` is off; a refused run (a hold, a failing script, an
// action the sample turned off) keeps it and the focus. It stays enabled
// during a hold, so the text can still be edited, and never takes its text
// from a sample. Off where the host can't take the keyboard (the desktop,
// the lock screen, a preview).
// reads: actions.submit
CustomElementBase {
  id: root

  StyledTextEntry {
    id: field
    anchors.fill: parent
    placeholderText: root.bind.placeholder ? root.text("placeholder") : root.options.placeholder
    enabled: root.actionsEnabled && root.keysHost
    onAccepted: {
      const refused = root.run("submit", field.text);
      if (refused === "" && root.options.clear)
        field.text = "";
    }
  }
}
