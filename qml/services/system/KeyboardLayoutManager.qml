pragma Singleton
import QtQuick
import qs.services.compositor

// Active xkb layout of the main keyboard, shared by every KeyboardLayout
// widget. Read once (CompositorManager.withKeyboard), then again whenever
// Hyprland reports a layout switch or a config reload (no polling).
QtObject {
  id: root

  property var layouts: []
  property int layoutIndex: 0
  property string keymapName: ""

  function refresh() {
    CompositorManager.withKeyboard(keyboard => {
      if (!keyboard)
        return;
      root.layouts = keyboard.layouts;
      root.layoutIndex = keyboard.index;
      root.keymapName = keyboard.keymap;
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

  Component.onCompleted: refresh()
}
