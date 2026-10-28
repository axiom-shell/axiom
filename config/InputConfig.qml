pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Input section: the keyboard, mouse, touchpad and cursor
// axiom sets on the compositor, a part at a time ({ keyboard: { enabled,
// layout, … }, mouse, touchpad, cursor }, each set only while `enabled`),
// by the daemon (its config layer, and greeter.compositor for the greeter's).
// Named InputConfig as the section is a whole object.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Input

  // Goes through a string so a reload that leaves it unchanged doesn't
  // apply it again
  readonly property string _inputJson: JSON.stringify(_c)
  readonly property var input: JSON.parse(_inputJson)

  // The cursor theme picked, set or not ("" for none)
  readonly property string cursorTheme: _c.cursor.theme
}
