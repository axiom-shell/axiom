pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Entry element: a text field that runs its submit action
// with the typed text on Return ({value} the text, already quoted). The text is cleared once it
// ran (kept when no action is picked), unless `clear` is off; a refused run (a hold, a failing script, an
// action the sample turned off) keeps it and the focus. It stays enabled
// during a hold, so the text can still be edited, and never takes its text
// from a sample. Off where the host can't take the keyboard (the desktop,
// the lock screen, a preview).
CustomElementBase {
  id: root

  StyledTextEntry {
    id: field
    anchors.fill: parent
    placeholderText: root.bind.placeholder ? root.text("placeholder") : root.options.placeholder
    enabled: root.actionsEnabled && root.keysHost
    onAccepted: {
      const refused = root.runTrigger("submit", field.text);
      if (refused === "" && root.options.clear)
        field.text = "";
    }
  }
}
