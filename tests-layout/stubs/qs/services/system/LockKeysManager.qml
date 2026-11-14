pragma Singleton
import QtQuick

// Stand-in for the shell's LockKeysManager in the layout harness (a text
// entry loads its Caps Lock hint): no lock key is reported.
QtObject {
  readonly property bool available: false
  readonly property bool capsLock: false
}
