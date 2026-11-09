pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.system

// Plumbing: a password field's Caps Lock warning (StyledTextEntry loads it
// while a hidden-text field has focus), the one reusable piece that reads
// LockKeysManager: the key is polled only while one exists. A warning
// icon that pops in while Caps Lock is on, saying so on hover.
IssueIcon {
  id: root

  readonly property bool shown: LockKeysManager.available && LockKeysManager.capsLock

  property real _reveal: root.shown ? 1 : 0
  Glide on _reveal {}

  text: "keyboard_capslock"
  level: "warning"
  tip: I18n.tr("Caps Lock is on")
  textSize: Appearance.fontSizeBy(1)
  visible: root._reveal > 0
  opacity: root._reveal
  scale: 0.6 + 0.4 * root._reveal

  Component.onCompleted: LockKeysManager.acquire(root)
  Component.onDestruction: LockKeysManager.release(root)
}
