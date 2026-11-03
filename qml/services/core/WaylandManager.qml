pragma Singleton
import QtQuick
import Quickshell

// What the axiom daemon's own Wayland connection can do for the shell
// (wayland.state: docs/dev/backend/wayland.md): typing into the focused
// window, the night light, the clipboard. Services gate on these, never
// on a compositor. All off without a daemon, and until it has said.
// Created from shell.qml's `_services`.
Singleton {
  id: root

  // Whether the daemon has said yet, with its connection's globals bound
  // (before that, everything reads off)
  readonly property bool known: root._state?.ready === true
  // Virtual keyboards: EmojiManager.type (input.type)
  readonly property bool typing: root._state?.typing === true
  // How the night light warms the screens: "ctm" (Hyprland's color
  // transform), "gamma" (gamma ramps) or "" (NightLightManager falls back
  // to wlsunset)
  readonly property string nightLight: root._state?.nightLight ?? ""
  // Clipboard control: "ext", "wlr" or "" (ClipboardManager)
  readonly property string clipboard: root._state?.clipboard ?? ""

  property var _state: null

  function _fetch() {
    BackendManager.call("wayland.get", {}, (error, state) => {
      if (!error)
        root._state = state;
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root._fetch();
    }
  }

  Component.onCompleted: {
    BackendManager.listen("wayland.state", state => root._state = state);
    // Made after the hello: no greeted to wait for
    if (BackendManager.ready)
      root._fetch();
  }
}
