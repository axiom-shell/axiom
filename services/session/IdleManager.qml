pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.apps

// Idle: what happens when you step away (the Idle section), run by the
// axiom daemon (idle.state: docs/dev/features/idle.md), and the caffeine
// switch that keeps the session awake. The Wayland idle inhibitor itself
// needs a mapped surface, so shell/IdleInhibit holds one while `caffeine`
// is on; the daemon is told too, as notifications that ignore inhibitors
// (Idle.respectInhibitors off) would ignore that surface. Caffeine goes on
// until turned off, or for a set time (a StopwatchClock timer it turns off
// at the end of, paused it stays on). Both are kept across QML reloads
// (a DeadlineTicker), but a restart always starts with idle allowed.
// Created from shell.qml's `_services`.
//
//   axiom ipc idleInhibit toggle
//   axiom ipc idleInhibit timer 30m
Singleton {
  id: root

  readonly property bool caffeine: root._ticker.values.caffeine === true
  // Caffeine's timer (StopwatchClock's), set while it's on for a set time
  readonly property var caffeineTimer: StopwatchClock.normalizeTimer(root._ticker.values.timer)
  readonly property bool caffeineTimed: !StopwatchClock.timerIdle(root.caffeineTimer)
  // The time left and how far it's gone, as of a `now` ticking while
  // something has acquire()d it
  readonly property string caffeineText: StopwatchClock.format(StopwatchClock.remaining(root.caffeineTimer, root._ticker.now), false, true)
  readonly property real caffeineProgress: StopwatchClock.timerProgress(root.caffeineTimer, root._ticker.now)

  // "off" | "running" | "inhibited" (an app holds idle off) |
  // "unsupported" (the compositor has no idle notifications) |
  // "unavailable" (no daemon to run it)
  readonly property string status: {
    if (!Idle.enabled)
      return "off";
    const state = root._state;
    if (!state || !state.enabled)
      return "unavailable";
    if (!state.notifier)
      return "unsupported";
    return state.inhibited ? "inhibited" : "running";
  }
  // What holds idle off: [{ source: "screensaver" | "logind" | "caffeine",
  // app, reason }]
  readonly property var inhibitors: root._state?.inhibitors ?? []
  // The program holding org.freedesktop.ScreenSaver instead of axiom, ""
  // when axiom or the compositor (which applies them itself) does: apps
  // asking it to keep the screen on aren't seen
  readonly property string screensaverHolder: {
    const ss = root._state?.screensaver;
    if (!ss || !ss.serving || ss.owned || ss.compositor || !ss.owner)
      return "";
    return ss.owner.name || I18n.tr("another program");
  }

  property var _state: null

  // On until turned off (the timer, if any, dropped), or off
  function setCaffeine(on) {
    root._ticker.set({
      "caffeine": on,
      "timer": StopwatchClock.resetTimer(root.caffeineTimer)
    });
  }

  function toggle() {
    root.setCaffeine(!root.caffeine);
  }

  // On for a time from text ("30m", "1h30m"); false when it isn't one
  function startCaffeineText(text) {
    const parsed = StopwatchClock.parse(text);
    if (parsed.ms <= 0)
      return false;
    root._ticker.set({
      "caffeine": true,
      "timer": StopwatchClock.startTimer(root.caffeineTimer, parsed.ms, Date.now(), "")
    });
    return true;
  }

  // Pause ↔ resume the timer (paused, caffeine stays on); an idle one
  // starts its last duration again
  function toggleCaffeineTimer() {
    const timer = root.caffeineTimer;
    const now = Date.now();
    root._ticker.set({
      "caffeine": true,
      "timer": timer.running ? StopwatchClock.pauseTimer(timer, now) : root.caffeineTimed ? StopwatchClock.resumeTimer(timer, now) : StopwatchClock.startTimer(timer, timer.duration, now, "")
    });
  }

  function addCaffeineTime(ms) {
    root._ticker.set({
      "timer": StopwatchClock.addTime(root.caffeineTimer, ms)
    });
  }

  // The time left at this moment, for a reader holding no acquire
  function caffeineTextNow() {
    return StopwatchClock.format(StopwatchClock.remaining(root.caffeineTimer, Date.now()), false, true);
  }

  // `interval`: ms between updates of caffeineText this owner wants
  function acquire(owner, interval) {
    root._ticker.acquire(owner, interval);
  }

  function release(owner) {
    root._ticker.release(owner);
  }

  property DeadlineTicker _ticker: DeadlineTicker {
    name: "caffeine"
    keeps: false
    deadline: root.caffeineTimer
    ticks: root.caffeineTimer.running
    restore: () => ({
          "caffeine": false,
          "timer": StopwatchClock.idleTimer
        })
    onEnded: root.setCaffeine(false)
  }

  onCaffeineChanged: root._report()

  function _report() {
    BackendManager.call("idle.caffeine", {
      "on": root.caffeine
    }, null);
  }

  // Caffeine to the daemon, and its state back
  function _sync() {
    root._report();
    BackendManager.call("idle.get", {}, (error, state) => {
      if (!error)
        root._state = state;
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root._sync();
    }
  }

  Component.onCompleted: {
    BackendManager.listen("idle.state", state => root._state = state);
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._sync();
  }

  property IpcTarget _ipc: IpcTarget {
    target: "idleInhibit"

    function toggle(): void {
      root.toggle();
    }

    function enable(): void {
      root.setCaffeine(true);
    }

    function disable(): void {
      root.setCaffeine(false);
    }

    // On for a time: "30m", "1h30m", "90s"
    function timer(text: string): bool {
      return root.startCaffeineText(text);
    }

    function status(): bool {
      return root.caffeine;
    }
  }
}
