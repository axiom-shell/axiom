pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.services.compositor
import qs.components.surfaces.osd.engine

// Keyboard layout's state for the OSD: the input sources, the one in use
// (its label and icon), when the focused window last changed and when
// axiom last switched (its definition's focus-follow reads both). Holds
// InputSourceManager, so a switch made in fcitx5 itself is heard without
// a tray too
OSDWatch {
  id: root

  // When the focused window last changed (ms, 0 for not yet)
  property double focusedAt: 0

  holds: [InputSourceManager]

  state: ({
      "keyboardLayout": {
        "ids": InputSourceManager.sources.map(s => s.id),
        "value": InputSourceManager.current,
        "label": InputSourceManager.labelFor(InputSourceManager.current, "short"),
        "icon": InputSourceManager.iconFor(InputSourceManager.current),
        "focusedAt": root.focusedAt,
        "switchedAt": InputSourceManager.switchedAt
      }
    })

  Connections {
    target: CompositorManager
    function onActiveWindowIdChanged() {
      root.focusedAt = Date.now();
    }
  }
}
