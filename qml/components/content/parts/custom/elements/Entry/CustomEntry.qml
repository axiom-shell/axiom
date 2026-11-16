pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable
import qs.services.apps
import qs.components.content.parts.custom

// A custom widget's Entry element: a text field that runs its submit action
// with the typed text on Return ({value} the text, already quoted); an empty
// Return does nothing. The text is cleared once it ran (an action that waits:
// once it finished without failing; kept when no action is picked), unless
// `clear` is off; a refused run (a hold, a failing script, an action the
// sample turned off) or a failed one keeps it and the focus. It stays enabled
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
      if (field.text.trim() === "")
        return;
      const action = root.actionFor("submit");
      const refused = root.runTrigger("submit", field.text);
      if (refused !== "" || !root.options.clear)
        return;
      if (action.kind === "axiom" || !action.wait)
        field.text = "";
      else
        root._clearAfter = Date.now();
    }
  }

  // When the accepted run that waits started, until it finished: the text is
  // cleared by its success (0: none waiting)
  property real _clearAfter: 0
  Connections {
    target: CustomWidgetsManager
    function onLastActionChanged() {
      if (root._clearAfter <= 0)
        return;
      const last = CustomWidgetsManager.lastAction[root.widgetId];
      if (!last || last.action !== root.actionFor("submit")?.id || last.at < root._clearAfter)
        return;
      if (!last.failed)
        field.text = "";
      root._clearAfter = 0;
    }
  }
}
