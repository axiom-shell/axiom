pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

// One one-off timer and one stopwatch, for every Stopwatch widget and
// module, both able to run at once. Their states (StopwatchClock's) hold
// absolute times, kept across a QML reload and a restart (StateManager
// "stopwatch", through DeadlineTicker). A timer's end notifies (with
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
  readonly property real now: root._ticker.now

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
    root._ticker.acquire(owner, interval);
  }

  function release(owner) {
    root._ticker.release(owner);
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

  readonly property var _timer: StopwatchClock.normalizeTimer(root._ticker.values.timer)
  readonly property var _stopwatch: StopwatchClock.normalizeStopwatch(root._ticker.values.stopwatch)

  property DeadlineTicker _ticker: DeadlineTicker {
    name: "stopwatch"
    desktopEntry: "axiom-stopwatch"
    deadline: root._timer
    ticks: root._timer.running || root._stopwatch.running
    // StopwatchClock's states
    restore: saved => ({
          "timer": StopwatchClock.normalizeTimer(saved?.timer),
          "stopwatch": StopwatchClock.normalizeStopwatch(saved?.stopwatch)
        })
    onEnded: late => root._finish(late)
    onNotificationClicked: root.openModule()
  }

  function _setTimer(state) {
    root._ticker.set({
      "timer": state
    });
  }

  function _setStopwatch(state) {
    root._ticker.set({
      "stopwatch": state
    });
  }

  // The timer ran out: back to idle (its duration kept), and notify unless
  // it ended long ago, with axiom not running
  function _finish(late) {
    const label = root._timer.label;
    const duration = root._timer.duration;
    root._setTimer(StopwatchClock.resetTimer(root._timer));
    if (!StopwatchConfig.notify || late)
      return;
    root._ticker.notify(label !== "" ? label : I18n.tr("Timer done"), label !== "" ? I18n.tr("Your {0} timer is done.", StopwatchClock.format(duration, false, true)) : I18n.tr("{0} are up.", StopwatchClock.format(duration, false, true)));
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
