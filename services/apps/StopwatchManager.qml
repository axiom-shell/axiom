pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.system
import qs.services.ui

// One one-off timer and one stopwatch, for every Stopwatch widget and
// module, both able to run at once. Their states (StopwatchClock's) hold
// absolute times, kept across a QML reload (PersistentProperties) and a
// restart (StateManager "stopwatch"). A timer's end notifies (with
// Stopwatch.notify) and runs with nothing showing it; displays
// acquire(owner, interval) a `now` ticking at the shortest interval asked
// (a stopwatch's tenths want 100 ms), only while one runs.
//
//   axiom ipc stopwatch timer "10m tea"
Singleton {
  id: root

  readonly property var timer: root._timer
  readonly property var stopwatch: root._stopwatch
  readonly property bool timerRunning: root._timer.running
  readonly property bool timerIdle: StopwatchClock.timerIdle(root._timer)
  readonly property bool stopwatchRunning: root._stopwatch.running
  readonly property bool stopwatchIdle: StopwatchClock.stopwatchIdle(root._stopwatch)
  // Ms, as of `now`
  readonly property real timerRemaining: StopwatchClock.remaining(root._timer, root.now)
  readonly property real timerProgress: StopwatchClock.timerProgress(root._timer, root.now)
  readonly property real elapsed: StopwatchClock.elapsed(root._stopwatch, root.now)
  readonly property string timerText: StopwatchClock.format(root.timerRemaining, false, true)
  readonly property string elapsedText: StopwatchClock.format(root.elapsed, false, false)
  readonly property var laps: StopwatchClock.lapRows(root._stopwatch)
  property real now: Date.now()

  // The times as of this moment, for a reader holding no acquire (the
  // launcher, IPC): `timerText` and `elapsedText` follow `now`, which ticks
  // only while something has acquired it
  function timerTextNow() {
    return StopwatchClock.format(StopwatchClock.remaining(root._timer, Date.now()), false, true);
  }

  function elapsedTextNow() {
    return StopwatchClock.format(StopwatchClock.elapsed(root._stopwatch, Date.now()), false, false);
  }

  // `interval`: ms between updates of `now` this owner wants
  function acquire(owner, interval) {
    root._registry.acquire(owner, interval ?? 1000);
    root.now = Date.now();
  }

  function release(owner) {
    root._registry.release(owner);
  }

  // -- Timer --

  // Starts a timer from text ("10m", "1h30m tea", "1:30"); false when it
  // doesn't start with a duration
  function startTimerText(text) {
    const parsed = StopwatchClock.parse(text);
    if (parsed.ms <= 0)
      return false;
    root.startTimer(parsed.ms, parsed.label);
    return true;
  }

  function startTimer(ms, label) {
    root._setTimer(StopwatchClock.startTimer(root._timer, ms, Date.now(), label ?? ""));
  }

  // Pause ↔ resume; an idle timer starts its last duration again
  function toggleTimer() {
    if (root._timer.running)
      root._setTimer(StopwatchClock.pauseTimer(root._timer, Date.now()));
    else if (root.timerIdle)
      root.startTimer(root._timer.duration, root._timer.label);
    else
      root._setTimer(StopwatchClock.resumeTimer(root._timer, Date.now()));
  }

  function addTimer(ms) {
    root._setTimer(StopwatchClock.addTime(root._timer, ms));
  }

  function resetTimer() {
    root._setTimer(StopwatchClock.resetTimer(root._timer));
  }

  // -- Stopwatch --

  function toggleStopwatch() {
    const now = Date.now();
    root._setStopwatch(root._stopwatch.running ? StopwatchClock.pauseStopwatch(root._stopwatch, now) : StopwatchClock.startStopwatch(root._stopwatch, now));
  }

  function lap() {
    root._setStopwatch(StopwatchClock.lap(root._stopwatch, Date.now()));
  }

  function resetStopwatch() {
    root._setStopwatch(StopwatchClock.idleStopwatch);
  }

  // A page or edge menu with a Stopwatch module; false with none
  function openModule() {
    return !Paths.greeter && ShellManager.openModule(["Stopwatch"]);
  }

  // -- Private --

  readonly property var _timer: StopwatchClock.normalizeTimer(root._parse(_run.timer))
  readonly property var _stopwatch: StopwatchClock.normalizeStopwatch(root._parse(_run.stopwatch))
  readonly property string _desktopEntry: "axiom-stopwatch"
  readonly property var _store: StateManager.createStateHandler("stopwatch")
  property ConsumerRegistry _registry: ConsumerRegistry {}

  PersistentProperties {
    id: _run
    reloadableId: "axiomStopwatch"
    // StopwatchClock's states as JSON ("" until restored)
    property string timer: ""
    property string stopwatch: ""
    property bool restored: false
  }

  function _parse(text) {
    try {
      return JSON.parse(text || "null");
    } catch (e) {
      return null;
    }
  }

  function _setTimer(state) {
    if (Paths.greeter)
      return;
    _run.timer = JSON.stringify(state);
    root._changed();
  }

  function _setStopwatch(state) {
    if (Paths.greeter)
      return;
    _run.stopwatch = JSON.stringify(state);
    root._changed();
  }

  function _changed() {
    root.now = Date.now();
    root._store.save({
      "timer": root._timer,
      "stopwatch": root._stopwatch
    });
  }

  // The timer ran out: back to idle (its duration kept), and notify unless
  // it ended long ago, with axiom not running. Once per end: a second call
  // queued by another _arm before the first ran finds the timer idle
  function _finish(late) {
    if (!root._timer.running || root._timer.endsAt > Date.now())
      return;
    const label = root._timer.label;
    const duration = root._timer.duration;
    root._setTimer(StopwatchClock.resetTimer(root._timer));
    if (!StopwatchConfig.notify || late)
      return;
    NotificationManager.sendNotification("axiom", label !== "" ? label : I18n.tr("Timer done"), label !== "" ? I18n.tr("Your {0} timer is done.", StopwatchClock.format(duration, false, true)) : I18n.tr("{0} are up.", StopwatchClock.format(duration, false, true)), {
      "desktopEntry": root._desktopEntry,
      "icon": "appointment-soon"
    });
  }

  // To the timer's end, at most an hour at a time
  function _arm() {
    _alarm.stop();
    if (!root._timer.running)
      return;
    const left = root._timer.endsAt - Date.now();
    if (left <= 0) {
      Qt.callLater(() => root._finish(left < -5 * 60000));
      return;
    }
    _alarm.interval = Math.min(left + 50, 3600000);
    _alarm.start();
  }

  on_TimerChanged: root._arm()

  Timer {
    id: _alarm
    repeat: false
    onTriggered: root._arm()
  }

  Timer {
    interval: Math.max(50, Math.min(...root._registry.requests.concat([1000])))
    repeat: true
    running: (root._timer.running || root._stopwatch.running) && root._registry.active
    onTriggered: root.now = Date.now()
  }

  Component.onCompleted: {
    if (Paths.greeter)
      return;
    // A restart (not a reload): back from the state file
    if (!_run.restored) {
      const saved = root._store.load(null);
      _run.timer = JSON.stringify(StopwatchClock.normalizeTimer(saved?.timer));
      _run.stopwatch = JSON.stringify(StopwatchClock.normalizeStopwatch(saved?.stopwatch));
      _run.restored = true;
    }
    root._arm();
    NotificationManager.registerHandler(root._desktopEntry, () => root.openModule());
  }

  property IpcTarget _ipc: IpcTarget {
    target: "stopwatch"
    enabled: !Paths.greeter

    // Starts a timer: "10m", "1h30m", "90s", "1:30", "10m tea"
    function timer(text: string): bool {
      return root.startTimerText(text);
    }

    function toggleTimer(): void {
      root.toggleTimer();
    }

    function resetTimer(): void {
      root.resetTimer();
    }

    function toggle(): void {
      root.toggleStopwatch();
    }

    function lap(): void {
      root.lap();
    }

    function reset(): void {
      root.resetStopwatch();
    }

    // "timer <mm:ss> running|paused|stopped, stopwatch <mm:ss> …"
    function status(): string {
      const state = (running, idle) => running ? "running" : idle ? "stopped" : "paused";
      return `timer ${root.timerTextNow()} ${state(root.timerRunning, root.timerIdle)}, stopwatch ${root.elapsedTextNow()} ${state(root.stopwatchRunning, root.stopwatchIdle)}`;
    }
  }
}
