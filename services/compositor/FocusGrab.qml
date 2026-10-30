pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services.ui

// A focus grab, for surfaces that close (or drop keyboard focus) on a click
// outside them: while `active`, keyboard focus stays in `windows` and a
// click anywhere else ends the grab (`cleared`). Hyprland's focus grab
// (HyprlandGrab) where the compositor has one (CompositorManager.supports.
// focusGrab); elsewhere the grab ends once keyboard focus has left every
// one of `windows` (a click on another window or surface takes it), or a
// click lands on a screen's backdrop window, which covers every screen
// under the surfaces while such a grab is active (BackdropManager.
// catching). The newest such grab's surface asks for Exclusive keyboard
// focus meanwhile (`exclusive`): a layer surface asking on demand gets the
// keyboard only once clicked. Not a singleton: each surface makes its own.
Scope {
  id: root

  property var windows: []
  property bool active: false
  signal cleared
  // A click on a screen's backdrop ended it (no native grab): a real
  // click, never just focus leaving. Sent before `cleared`
  signal clickedOutside

  readonly property bool _native: CompositorManager.supports.focusGrab === true
  // Active without a native grab: a click outside clears it. In
  // BackdropManager's newest-first order, kept while a modal is up (no
  // click is caught then: BackdropManager.catching), so the newest grab
  // gets the keyboard back after it
  readonly property bool _catching: !root._native && root.active
  // The surface's own window should take the keyboard exclusively
  // (WlrKeyboardFocus.Exclusive) while this is on: only the newest such
  // grab's, never while a modal is up (SurfaceManager.modalShown). Of two
  // exclusive surfaces on one layer niri keeps the older, so a popout
  // opened over the overlay, or the prompt, would never get the keyboard
  readonly property bool exclusive: root._catching && !SurfaceManager.modalShown && BackdropManager.newestCatcher === root._uid

  // A click caught outside every surface (BackdropManager.catching)
  property int _uid: 0
  // Not before it has its id: a catcher reported under 0 would never clear
  on_CatchingChanged: {
    if (root._uid > 0)
      BackdropManager.catchClicks(root._uid, root._catching);
  }
  Component.onCompleted: {
    root._uid = BackdropManager.register();
    BackdropManager.catchClicks(root._uid, root._catching);
  }
  Component.onDestruction: {
    if (root._uid > 0)
      BackdropManager.catchClicks(root._uid, false);
  }
  property Connections _outside: Connections {
    target: BackdropManager
    enabled: root._catching
    function onClickedOutside() {
      root.clickedOutside();
      root.cleared();
    }
  }

  LazyLoader {
    active: root._native
    HyprlandGrab {
      windows: root.windows
      active: root.active
      onCleared: root.cleared()
    }
  }

  // --- Without a native grab: watch keyboard focus ---

  // Each window's keyboard focus: its content's `Window.active` (attached,
  // which follows the item into whichever backing window it's in). Not
  // Quickshell's `_backingWindow`: it doesn't notify, and a PanelWindow
  // (an interface around the real window) has none
  Instantiator {
    id: _watchers
    model: root._native ? [] : root.windows

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

  // Whether one of the windows has keyboard focus while the grab is on
  property bool _focused: false
  // Whether one of the windows has had keyboard focus since the grab began
  property bool _held: false

  function _recheck() {
    let focused = false;
    for (let i = 0; i < _watchers.count; i++)
      focused = focused || root._focusedOf(_watchers.objectAt(i));
    root._focused = !root._native && root.active && focused;
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
        root.cleared();
      }
    }
  }
}
