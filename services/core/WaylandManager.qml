pragma Singleton
import QtQuick
import Quickshell

// What the axiom daemon's own Wayland connection can do for the shell
// (wayland.state: docs/dev/backend/wayland.md): typing into the focused
// window, … . Services gate on these, never on a compositor. All false
// without a daemon, and until it has said.
Singleton {
  id: root

  // Virtual keyboards: EmojiManager.type (input.type)
  readonly property bool typing: root._state?.typing === true

  property var _state: null

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      BackendManager.call("wayland.get", {}, (error, state) => {
        if (!error)
          root._state = state;
      });
    }
  }

  Component.onCompleted: BackendManager.listen("wayland.state", state => root._state = state)
}
