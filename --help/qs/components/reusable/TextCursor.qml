pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The text fields' cursor: an accent bar blinking while its input (the
// parent a cursorDelegate is given) has focus, steady with animations off.
// StyledTextEntry's and StyledTextArea's cursorDelegate.
Rectangle {
  id: root

  readonly property bool _focused: root.parent ? root.parent.activeFocus : false

  width: 2
  color: Theme.accent
  visible: root._focused

  SequentialAnimation on opacity {
    loops: Animation.Infinite
    running: root._focused && Appearance.animations
    // A stop leaves it mid-blink: show it whole
    onStopped: root.opacity = 1
    PropertyAnimation {
      to: 1
      duration: 500 // behaviour timing: the cursor blink
    }
    PropertyAnimation {
      to: 0
      duration: 500 // behaviour timing: the cursor blink
    }
  }
}
