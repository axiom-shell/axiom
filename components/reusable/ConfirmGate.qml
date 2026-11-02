pragma ComponentBehavior: Bound
import QtQuick

// The press-twice gate of a destructive action: pass(key, true) arms the
// key and refuses; the same key again within `timeout` passes. Arming
// another key moves it; it disarms by itself after `timeout`.
QtObject {
  id: root

  // The key waiting for its second press, "" for none
  property string armed: ""
  // How long a key stays armed, in ms
  property int timeout: 3000

  // Whether the action keyed `key` runs now
  function pass(key, needsConfirm) {
    if (needsConfirm && root.armed !== key) {
      root.armed = key;
      root._timer.restart();
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
    onTriggered: root.armed = ""
  }
}
