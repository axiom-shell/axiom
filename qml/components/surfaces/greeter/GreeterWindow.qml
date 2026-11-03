pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config

// The greeter on one screen (shell/Greeter): a full-screen Overlay-layer
// window, the only thing greetd's Hyprland shows. The target screen's
// (Greeter.monitor) takes the keyboard for its login box.
PanelWindow {
  id: root

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-greeter"
  WlrLayershell.keyboardFocus: surface.isTarget ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  color: Theme.background
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  GreeterSurface {
    id: surface
    screen: root.screen
  }
}
