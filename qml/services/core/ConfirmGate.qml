pragma ComponentBehavior: Bound
import QtQuick

// The press-twice gate of a destructive action: pass(key, true) arms the
// key and refuses; the same key again within `timeout` passes. Arming
// another key moves it; it disarms by itself after `timeout` (`expired`).
// `timeout` <= 0 never lapses: it stays armed until another key, `pass` or
// `disarm` (a confirm with a hint to read first).
// Each owner builds its own: the power menu, the QuickActions and Power
// modules, and LauncherManager's commands.
QtObject {
  id: root

  // The key waiting for its second press, "" for none
  property string armed: ""
  // How long a key stays armed, in ms
  property int timeout: 3000

  // The armed key ran out of time
  signal expired

  // Whether the action keyed `key` runs now
  function pass(key, needsConfirm) {
    if (needsConfirm && root.armed !== key) {
      root.armed = key;
      if (root.timeout > 0)
        root._timer.restart();
      else
        root._timer.stop();
      return false;
    }
    root.disarm();
    return true;
  }

  function disarm() {
    root._timer.stop();
    root.armed = "";
  }

  property Timer _timer: Timer {
    interval: root.timeout
    onTriggered: {
      root.armed = "";
      root.expired();
    }
  }
}
