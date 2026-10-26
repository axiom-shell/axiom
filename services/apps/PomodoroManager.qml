pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

// The pomodoro timer: one for every widget and module, run here so it
// keeps time with nothing showing it. The state (PomodoroCycle's) holds an
// absolute end time, so it survives a QML reload and a restart
// (StateManager "pomodoro", through DeadlineTicker); a phase that ended
// while axiom wasn't running moves on quietly. A notification marks each end (with
// Pomodoro.notify); clicking it opens a page or edge menu with the timer.
// Displays acquire(owner) the once-a-second `now`; the end itself needs
// no one.
//
//   axiom ipc pomodoro toggle
Singleton {
  id: root

  readonly property var state: root._state
  readonly property string phase: root._state.phase
  readonly property bool running: root._state.running
  readonly property bool isBreak: PomodoroCycle.isBreak(root._state)
  // Neither running nor paused part way
  readonly property bool idle: PomodoroCycle.isIdle(root._state)
  readonly property int completed: root._state.completed
  // Ms left, and 0–1 through the phase, as of `now`
  readonly property real remaining: PomodoroCycle.remaining(root._state, root.now, PomodoroConfig.settings)
  readonly property real progress: PomodoroCycle.progress(root._state, root.now, PomodoroConfig.settings)
  readonly property string remainingText: PomodoroCycle.format(root.remaining)
  // Updated every second while running and acquired
  readonly property real now: root._ticker.now
  // The todo the sessions are for ("" for none), and its text
  readonly property string todoUid: root._ticker.values.todoUid ?? ""
  readonly property string todoText: TodoManager.find(root.todoUid)?.summary ?? ""
  // I18n.tr("Focus") I18n.tr("Short break") I18n.tr("Long break")
  readonly property string phaseLabel: I18n.tr(root.phase === "short" ? "Short break" : root.phase === "long" ? "Long break" : "Focus")

  // The time left as of this moment, for a reader holding no acquire
  // (the launcher, IPC): `remainingText` follows `now`, which ticks only
  // while something has acquired it
  function remainingTextNow() {
    return PomodoroCycle.format(PomodoroCycle.remaining(root._state, Date.now(), PomodoroConfig.settings));
  }

  function acquire(owner) {
    root._ticker.acquire(owner, 1000);
  }

  function release(owner) {
    root._ticker.release(owner);
  }

  function start() {
    root._set(PomodoroCycle.start(root._state, Date.now(), PomodoroConfig.settings));
  }

  function pause() {
    root._set(PomodoroCycle.pause(root._state, Date.now()));
  }

  function toggle() {
    if (root.running)
      root.pause();
    else
      root.start();
  }

  // Ends this phase now and goes to the next, without a notification
  function skip() {
    root._set(PomodoroCycle.advance(root._state, Date.now(), PomodoroConfig.settings, root._autoStart()));
  }

  // Back to a focus session not yet started (the count stays)
  function stop() {
    root._set(PomodoroCycle.reset(root._state, false));
  }

  // Stopped, and the session count back to 0
  function reset() {
    root._set(PomodoroCycle.reset(root._state, true));
  }

  function setTodo(uid) {
    root._ticker.set({
      "todoUid": uid ?? ""
    });
  }

  // A page or edge menu with a Pomodoro or Focus module; false with none
  function openTimer() {
    return !Paths.greeter && ShellManager.openModule(["Pomodoro", "Focus"]);
  }

  // -- Private --

  readonly property var _state: PomodoroCycle.normalize(root._ticker.values.state)

  property DeadlineTicker _ticker: DeadlineTicker {
    name: "pomodoro"
    desktopEntry: "axiom-pomodoro"
    deadline: root._state
    ticks: root.running
    // PomodoroCycle's state, and the todo's uid
    restore: saved => ({
          "state": PomodoroCycle.normalize(saved?.state),
          "todoUid": typeof saved?.todoUid === "string" ? saved.todoUid : ""
        })
    onEnded: late => root._finish(late)
    onNotificationClicked: root.openTimer()
  }

  function _autoStart() {
    return {
      "work": PomodoroConfig.autoStartWork,
      "breaks": PomodoroConfig.autoStartBreaks
    };
  }

  function _set(state) {
    root._ticker.set({
      "state": state
    });
  }

  // The phase ran out: notify (unless it ended long ago, with axiom not
  // running) and go on
  function _finish(late) {
    const was = root._state;
    const next = PomodoroCycle.advance(was, Date.now(), PomodoroConfig.settings, root._autoStart());
    root._set(next);
    if (!PomodoroConfig.notify || late)
      return;
    const task = root.todoText;
    let summary, body;
    if (was.phase === "work") {
      summary = next.phase === "long" ? I18n.tr("Time for a long break") : I18n.tr("Time for a break");
      body = next.running ? I18n.tr("{0} sessions done. The break has started.", next.completed) : I18n.tr("{0} sessions done.", next.completed);
    } else {
      summary = I18n.tr("Break's over");
      body = next.running ? I18n.tr("The next focus session has started.") : I18n.tr("Start the next focus session when you're ready.");
    }
    if (task !== "" && next.phase === "work")
      body += "\n" + task;
    root._ticker.notify(summary, body);
  }

  property IpcTarget _ipc: IpcTarget {
    target: "pomodoro"
    enabled: !Paths.greeter

    function start(): void {
      root.start();
    }

    function pause(): void {
      root.pause();
    }

    function toggle(): void {
      root.toggle();
    }

    function skip(): void {
      root.skip();
    }

    function stop(): void {
      root.stop();
    }

    function reset(): void {
      root.reset();
    }

    // "<phase> <mm:ss> running|paused|stopped"
    function status(): string {
      return `${root.phase} ${root.remainingTextNow()} ${root.running ? "running" : root.idle ? "stopped" : "paused"}`;
    }
  }
}
