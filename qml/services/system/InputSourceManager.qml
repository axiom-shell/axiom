pragma Singleton
import QtQuick
import qs.services.compositor
import qs.services.core

// Active xkb layout of the main keyboard, shared by every KeyboardLayout
// widget. Read once (CompositorManager.withKeyboard), then again whenever
// Hyprland reports a layout switch or a config reload (no polling), and
// once the xkb registry (which names niri's and sway's layouts) is read.
QtObject {
  id: root

  property var layouts: []
  property int layoutIndex: 0
  property string keymapName: ""
  // The xkb registry (the daemon's input.layouts: { layouts: [{ name,
  // short, description, languages, variants }] }), null until read: the
  // codes of layouts niri and sway name in full
  readonly property var registry: _registry
  property var _registry: null

  function refresh() {
    CompositorManager.withKeyboard(keyboard => {
      if (!keyboard)
        return;
      root.layouts = keyboard.layouts;
      root.layoutIndex = keyboard.index;
      root.keymapName = keyboard.keymap;
    }, root._registry);
  }

  // rpc: input.layouts
  function _readRegistry() {
    BackendManager.call("input.layouts", {}, (error, result) => {
      if (error) {
        if (error.kind !== "unavailable")
          console.warn("[InputSourceManager] Could not read the xkb registry:", error.message);
        return;
      }
      root._registry = result;
      root.refresh();
    }, {
      "repeatable": true
    });
  }

  // "next" or "prev", on every keyboard
  function cycle(direction) {
    CompositorManager.cycleKeyboardLayout(direction);
  }

  property Connections _events: Connections {
    target: CompositorManager
    function onKeyboardLayoutChanged() {
      Qt.callLater(root.refresh);
    }
    function onConfigReloaded() {
      Qt.callLater(root.refresh);
    }
  }

  Component.onCompleted: {
    refresh();
    _readRegistry();
  }
}
