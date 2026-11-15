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
// the lock screen, a preview). It keeps its own height in a taller box and
// sits Down by `valign`.
CustomElementBase {
  id: root

  StyledTextEntry {
    id: field
    width: parent.width
    height: Math.min(parent.height, implicitHeight)
    y: root.placeY(height)
    placeholderText: root.text("placeholder")
    enabled: root.actionsEnabled && root.keysHost && root.allowed
    onAccepted: {
      const refused = root.runTrigger("submit", field.text);
      if (refused === "" && root.options.clear)
        field.text = "";
    }
  }
}
