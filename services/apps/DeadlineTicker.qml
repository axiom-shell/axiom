pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services.core
import qs.services.system

// The plumbing StopwatchManager and PomodoroManager share (each owns one):
// their saved state, an alarm at a deadline, a ticking `now` for displays,
// and the notification they send. `values` (an object of JSON values) is
// kept across a QML reload (PersistentProperties, keyed by `name`) and a
// restart (StateManager `name`); `set(changes)` merges into it. `ended`
// fires once when `deadline` (an object with `running` and `endsAt`, in ms)
// runs out, with nothing showing it; displays acquire(owner, interval) a
// `now` ticking at the shortest interval asked while `ticks` holds. Nothing
// is restored or written in greeter mode.
QtObject {
  id: root

  // The StateManager file and the reload key
  required property string name
  // The values on a restart from what the state file held (null for none)
  required property var restore
  // { running, endsAt }: the alarm's deadline
  property var deadline: null
  // Whether something runs that displays tick for
  property bool ticks: false
  // Notifications go out under it; clicking one fires notificationClicked
  property string desktopEntry: ""

  readonly property var values: root._parse(_run.values) ?? ({})
  property real now: Date.now()

  // The deadline ran out: `late` when it ended long ago, with axiom not
  // running
  signal ended(bool late)
  signal notificationClicked

  // Merges `changes` into `values`, and saves them
  function set(changes) {
    if (Paths.greeter)
      return;
    const next = Object.assign({}, root.values, changes);
    _run.values = JSON.stringify(next);
    root.now = Date.now();
    root._store.save(next);
  }

  // `interval`: ms between updates of `now` this owner wants
  function acquire(owner, interval) {
    root._registry.acquire(owner, interval ?? 1000);
    root.now = Date.now();
  }

  function release(owner) {
    root._registry.release(owner);
  }

  function notify(summary, body) {
    NotificationManager.sendNotification("axiom", summary, body, {
      "desktopEntry": root.desktopEntry,
      "icon": "appointment-soon"
    });
  }

  // -- Private --

  readonly property var _store: StateManager.createStateHandler(root.name)
  property ConsumerRegistry _registry: ConsumerRegistry {}

  property PersistentProperties _persisted: PersistentProperties {
    id: _run
    reloadableId: "axiomTicker-" + root.name
    // `values` as JSON ("" until restored from the state file)
    property string values: ""
    property bool restored: false
  }

  function _parse(text) {
    try {
      return JSON.parse(text || "null");
    } catch (e) {
      return null;
    }
  }

  // Once per end: a second call queued by another _arm before the first
  // ran finds the deadline moved on
  function _end(late) {
    if (!root.deadline?.running || root.deadline.endsAt > Date.now())
      return;
    root.ended(late);
  }

  // To the deadline, at most an hour at a time
  function _arm() {
    _alarm.stop();
    if (!root.deadline?.running)
      return;
    const left = root.deadline.endsAt - Date.now();
    if (left <= 0) {
      Qt.callLater(() => root._end(left < -5 * 60000));
      return;
    }
    _alarm.interval = Math.min(left + 50, 3600000);
    _alarm.start();
  }

  onDeadlineChanged: if (root._started)
    root._arm()

  property bool _started: false

  property Timer _alarmTimer: Timer {
    id: _alarm
    repeat: false
    onTriggered: root._arm()
  }

  property Timer _tick: Timer {
    interval: Math.max(50, Math.min(...root._registry.requests.concat([1000])))
    repeat: true
    running: root.ticks && root._registry.active
    onTriggered: root.now = Date.now()
  }

  Component.onCompleted: {
    if (Paths.greeter)
      return;
    // A restart (not a reload): back from the state file
    if (!_run.restored) {
      _run.values = JSON.stringify(root.restore(root._store.load(null)));
      _run.restored = true;
    }
    root._started = true;
    root._arm();
    if (root.desktopEntry !== "")
      NotificationManager.registerHandler(root.desktopEntry, () => root.notificationClicked());
  }
}
