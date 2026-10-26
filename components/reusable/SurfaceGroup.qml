pragma ComponentBehavior: Bound
import QtQuick

import qs.services.ui

// Keeps a surface's instances on every monitor in step when its `monitors`
// mode is "all": opening or closing one opens or closes the rest
// (`syncRequested`). Only one focus grab can be active, so only the
// instance that opened on the target screen holds one (`ownsGrab`), over
// every instance's window (`windows`). In the other modes an instance is
// on its own: it owns its grab, and `windows` is just its window.
QtObject {
  id: root

  // Names the surface: instances with the same kind act together
  required property string kind
  // The surface's ScreenTarget (null is General's)
  property var target: null
  required property var screen
  // This instance's window (null while it has none)
  property var window: null
  // Whether this instance is open
  property bool shown: false

  // Open (true) or close this instance to match the others
  signal syncRequested(bool shown)

  readonly property bool everywhere: ShellManager.everywhere(root.target)
  // Set when it opens: the target screen's instance
  property bool ownsGrab: true
  // Windows the grab lets input through to
  readonly property var windows: {
    if (!root.everywhere)
      return root.window ? [root.window] : [];
    return ShellManager.surfaceWindows.filter(e => e.kind === root.kind).map(e => e.window);
  }

  onShownChanged: {
    ShellManager.setSurfaceOpen(root, root.kind, root.shown);
    if (root.shown)
      root.ownsGrab = !root.everywhere || ShellManager.isTarget(root.screen, root.target);
    if (root.everywhere)
      ShellManager.surfaceShown(root.kind, root.shown);
  }

  onWindowChanged: ShellManager.registerSurfaceWindow(root, root.kind, root.window)
  Component.onCompleted: {
    ShellManager.registerSurfaceWindow(root, root.kind, root.window);
    ShellManager.setSurfaceOpen(root, root.kind, root.shown);
  }
  Component.onDestruction: ShellManager.unregisterSurfaceWindow(root)

  property Connections _sync: Connections {
    target: ShellManager
    function onSurfaceShown(kind, shown) {
      if (kind === root.kind && root.everywhere && shown !== root.shown)
        root.syncRequested(shown);
    }
  }
}
