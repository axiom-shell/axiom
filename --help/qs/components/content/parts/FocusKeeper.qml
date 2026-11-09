pragma ComponentBehavior: Bound
import QtQuick

// Keeps the keyboard on a field (the lock screen's password, the greeter's
// login box): whenever focus leaves it, `reclaim` fires on the next tick.
// A control clicked meanwhile (a calendar arrow, a power button) keeps
// focus until it's released, since a button that loses focus while
// pressed drops the click.
Item {
  id: root

  property bool active: false
  // What should hold focus
  property Item holder: null
  // Hosts may keep another of their own fields focused
  property var keeps: item => false

  signal reclaim

  // The pressed control holding focus until it's released
  property var _waitingOn: null

  function _check() {
    const item = root.Window.window?.activeFocusItem ?? null;
    if (!root.active || item === root.holder || (item && root.keeps(item)))
      return;
    // Pressed (the press sets focus first, so it shows by the next tick)
    if (item?.pressed === true) {
      root._waitingOn = item;
      return;
    }
    root.reclaim();
  }

  Connections {
    target: root.Window.window
    enabled: root.active

    function onActiveFocusItemChanged() {
      Qt.callLater(root._check);
    }
  }

  Connections {
    target: root._waitingOn
    ignoreUnknownSignals: true

    function onPressedChanged() {
      if (root._waitingOn?.pressed === true)
        return;
      root._waitingOn = null;
      Qt.callLater(root._check);
    }
  }
}
