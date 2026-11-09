pragma Singleton
import QtQuick
import Quickshell
import qs.services.core

/*
 * The machine's clock, for Settings › System › Date & time: its time zone,
 * network time (on, synchronized) and setting the time by hand, through
 * systemd-timedated in axiom (datetime.*, backend/internal/timedate).
 * Each setter asks polkit, whose prompt is the user's agent's (axiom's own,
 * PolkitManager). A change made anywhere (timedatectl, another desktop's
 * settings) comes as datetime.state. `available` is false without
 * timedated (no systemd): the card then only shows the time.
 */
Singleton {
  id: root

  readonly property bool available: _state.available === true
  // The IANA zone ("Europe/Berlin"); "" unset (UTC)
  readonly property string timezone: _state.timezone ?? ""
  // A time sync service is installed, it's on, and it has synchronized
  readonly property bool canNtp: _state.canNtp === true
  readonly property bool ntp: _state.ntp === true
  readonly property bool ntpSynchronized: _state.ntpSynchronized === true
  // The hardware clock keeps local time (a dual boot with Windows)
  readonly property bool localRtc: _state.localRtc === true
  // A setter is waiting (polkit's prompt included)
  readonly property bool busy: _busy
  // The last setter's error ("" when it worked)
  readonly property string error: _error

  function refresh() {
    BackendManager.call("datetime.get", {}, (error, result) => {
      if (!error)
        root._state = result;
    }, {
      "repeatable": true
    });
  }

  function setTimezone(zone) {
    root._set("datetime.setTimezone", {
      "timezone": String(zone ?? "")
    });
  }

  function setNtp(on) {
    root._set("datetime.setNtp", {
      "on": !!on
    });
  }

  // `at`: a Date, or ms since the epoch
  function setTime(at) {
    root._set("datetime.setTime", {
      "at": at instanceof Date ? at.getTime() : Number(at)
    });
  }

  // rpc: datetime.setTimezone, datetime.setNtp, datetime.setTime
  function _set(method, params) {
    if (root._busy)
      return;
    root._busy = true;
    root._error = "";
    BackendManager.call(method, params, (error, result) => {
      root._busy = false;
      if (error) {
        root._error = SystemInfoManager.errorText(error);
        return;
      }
      root._state = result;
    });
  }

  property var _state: ({})
  property bool _busy: false
  property string _error: ""

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root.refresh();
    }
  }

  Component.onCompleted: {
    BackendManager.listen("datetime.state", state => root._state = state);
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root.refresh();
  }
}
