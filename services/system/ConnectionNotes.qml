pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// Silent notes (the notifications' Quiet section) of what connects and
// disconnects, while NotificationsConfig.quietConnectivity is on: a
// default child of NetworkingManager (the primary connection),
// BluetoothManager (each device) and TailscaleManager. The owner binds
// `connected`, what's connected now as { key: label }; a change that
// holds for `settle` ms (a device reconnecting, Wi-Fi roaming) is noted,
// one entry per key ("<prefix>:<key>"). What's there in the first
// `startGrace` ms is the start's, never a change.
QtObject {
  id: root

  property var connected: ({})
  // The notes' key prefix and icon (a name)
  property string prefix: ""
  property string icon: ""
  property int settle: 3000
  property int startGrace: 10000

  property var _last: ({})
  property real _since: Date.now()

  onConnectedChanged: _settle.restart()
  Component.onCompleted: {
    root._last = Object.assign({}, root.connected);
    // A click on one opens nothing
    NotificationManager.registerHandler(root._desktopEntry, () => {});
  }

  readonly property string _desktopEntry: "axiom-connectivity"

  property Timer _settle: Timer {
    interval: root.settle
    onTriggered: root._compare()
  }

  function _compare() {
    const now = root.connected;
    const before = root._last;
    root._last = Object.assign({}, now);
    if (Paths.greeter || !NotificationsConfig.quietConnectivity || Date.now() - root._since < root.startGrace)
      return;
    for (const key of Object.keys(now)) {
      if (!(key in before))
        root._note(key, I18n.tr("{0} connected", now[key]));
    }
    for (const key of Object.keys(before)) {
      if (!(key in now))
        root._note(key, I18n.tr("{0} disconnected", before[key]));
    }
  }

  function _note(key, summary) {
    NotificationManager.sendNotification("axiom", summary, "", {
      "icon": root.icon,
      "desktopEntry": root._desktopEntry,
      "key": root.prefix + ":" + key,
      "silent": true
    });
  }
}
