pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Focus leaving a surface, seen without taking anything: while `active`,
// `left` once keyboard focus has left every one of `windows` after one of
// them held it (a click on a window or another surface takes it), and,
// with `windowFocus`, once the compositor focuses a window
// (CompositorManager.activeWindowId changing to one: a click on a window
// focuses it, wherever the keyboard was). It holds no grab, so the click
// reaches what it lands on. FocusGrab watches the keyboard through it
// where the compositor has no grab of its own; a free menu closes on an
// outside click through it (FreeMenu). Not a singleton: each surface
// makes its own.
Scope {
  id: root

  property var windows: []
  property bool active: false
  // Also left when the compositor focuses a window
  property bool windowFocus: false
  signal left

  // The compositor focusing a window (not its focus going to none: a
  // layer surface taking the keyboard, one of `windows` included)
  property Connections _windowFocus: Connections {
    target: CompositorManager
    enabled: root.active && root.windowFocus
    function onActiveWindowIdChanged() {
      if (CompositorManager.activeWindowId !== "")
        root.left();
    }
  }

  // Each window's keyboard focus: its content's `Window.active` (attached,
  // which follows the item into whichever backing window it's in). Not
  // Quickshell's `_backingWindow`: it doesn't notify, and a PanelWindow
  // (an interface around the real window) has none
  Instantiator {
    id: _watchers
    model: root.windows

    delegate: QtObject {
      id: watcher

      required property var modelData
      // Read once: the attached object is the content item's for good
      property var attached: null
      readonly property bool focused: watcher.attached?.active === true
      onFocusedChanged: root._recheck()

      Component.onCompleted: watcher.attached = watcher.modelData?.contentItem?.Window ?? null
    }

    onObjectAdded: root._recheck()
    onObjectRemoved: root._recheck()
  }

  // Whether one of the windows has keyboard focus while active
  property bool _focused: false
  // Whether one of the windows has had keyboard focus since it went active
  property bool _held: false

  function _recheck() {
    let focused = false;
    for (let i = 0; i < _watchers.count; i++)
      focused = focused || root._focusedOf(_watchers.objectAt(i));
    root._focused = root.active && focused;
  }

  // A watcher's `focused` (untyped: objectAt hands back a QObject)
  function _focusedOf(watcher) {
    return watcher?.focused === true;
  }

  on_FocusedChanged: {
    if (root._focused)
      root._held = true;
    else if (root._held)
      _lost.restart();
  }
  onActiveChanged: {
    if (!root.active) {
      root._held = false;
      _lost.stop();
    }
    root._recheck();
  }

  // Focus moving between two of the windows passes through none
  Timer {
    id: _lost
    interval: 100
    onTriggered: {
      if (root.active && root._held && !root._focused) {
        root._held = false;
        root.left();
      }
    }
  }
}
