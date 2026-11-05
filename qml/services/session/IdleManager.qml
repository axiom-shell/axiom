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

  readonly property bool caffeine: _ticker.values.caffeine === true
  // Caffeine's timer (StopwatchClock's), set while it's on for a set time
  readonly property var caffeineTimer: StopwatchClock.normalizeTimer(_ticker.values.timer)
  readonly property bool caffeineTimed: !StopwatchClock.timerIdle(root.caffeineTimer)
  // The time left and how far it's gone, as of a `now` ticking while
  // something has acquire()d it
  readonly property real caffeineRemaining: StopwatchClock.remaining(root.caffeineTimer, _ticker.now)
  readonly property string caffeineText: StopwatchClock.format(root.caffeineRemaining, false, true)
  readonly property real caffeineProgress: StopwatchClock.timerProgress(root.caffeineTimer, _ticker.now)
  // The last caffeine timers, [{ ms, label }], the newest first (kept
  // across reloads only, as caffeine is)
  readonly property var caffeineRecent: StopwatchClock.normalizeRecent(_ticker.values.recent)

  // "off" | "running" | "inhibited" (an app holds idle off) |
  // "noLock" (running, but nothing locks: the user's own locker with no
  // lock command of theirs) | "unsupported" (the compositor has no idle
  // notifications) | "unavailable" (no daemon to run it)
  readonly property string status: {
    if (!Idle.enabled)
      return "off";
    const state = root._state;
    if (!state || !state.enabled)
      return "unavailable";
    if (!state.notifier)
      return "unsupported";
    if (state.noLocker)
      return "noLock";
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
    _ticker.set({
      "caffeine": on,
      "timer": StopwatchClock.resetTimer(root.caffeineTimer)
    });
  }

  function toggle() {
    root.setCaffeine(!root.caffeine);
  }

  // On for a time from text ("30m", "1h30m", "until 17:00"); false when
  // it isn't one
  function startCaffeineText(text) {
    const parsed = StopwatchClock.parse(text, Date.now());
    if (parsed.ms <= 0)
      return false;
    root.startCaffeine(parsed.ms, parsed.clock === true);
    return true;
  }

  // On for `ms` from now; `once` (a time of day) stays out of the recent
  // ones
  function startCaffeine(ms, once) {
    _ticker.set({
      "caffeine": true,
      "timer": StopwatchClock.startTimer(root.caffeineTimer, ms, Date.now(), ""),
      "recent": once ? root.caffeineRecent : StopwatchClock.pushRecent(root.caffeineRecent, ms, "", 3)
    });
  }

  // Pause ↔ resume the timer (paused, caffeine stays on); an idle one
  // starts its last duration again
  function toggleCaffeineTimer() {
    const timer = root.caffeineTimer;
    const now = Date.now();
    _ticker.set({
      "caffeine": true,
      "timer": timer.running ? StopwatchClock.pauseTimer(timer, now) : root.caffeineTimed ? StopwatchClock.resumeTimer(timer, now) : StopwatchClock.startTimer(timer, timer.duration, now, "")
    });
  }

  // More time, or less (a negative `ms`)
  function addCaffeineTime(ms) {
    _ticker.set({
      "timer": StopwatchClock.addTime(root.caffeineTimer, ms, Date.now())
    });
  }

  // The time left at this moment, for a reader holding no acquire
  function caffeineTextNow() {
    return StopwatchClock.format(StopwatchClock.remaining(root.caffeineTimer, Date.now()), false, true);
  }

  // `interval`: ms between updates of caffeineText this owner wants
  function acquire(owner, interval) {
    _ticker.acquire(owner, interval);
  }

  function release(owner) {
    _ticker.release(owner);
  }

  DeadlineTicker {
    id: _ticker
    name: "caffeine"
    keeps: false
    deadline: root.caffeineTimer
    ticks: root.caffeineTimer.running
    restore: () => ({
          "caffeine": false,
          "timer": StopwatchClock.idleTimer,
          "recent": []
        })
    warnBefore: Idle.caffeineWarning ? 5 * 60000 : 0
    onEnded: root.setCaffeine(false)
    onWarned: _ticker.notify(I18n.tr("Caffeine ends soon"), I18n.tr("The screen can lock again in 5 minutes."), [
      {
        "id": "more",
        "label": I18n.tr("30 more minutes")
      }
    ], id => {
      if (id === "more" && root.caffeineTimed)
        root.addCaffeineTime(30 * 60000);
    })
    // Restored: told now if the hello came first
    onReadyChanged: if (BackendManager.ready)
      root._report()
  }

  onCaffeineChanged: root._report()

  // Not before the ticker is restored: on a reload caffeine reads off
  // until then, and the daemon would see it go off and on
  function _report() {
    if (!_ticker.ready)
      return;
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

    // On for a time: "30m", "1h30m", "90s", "until 17:00"
    function timer(text: string): bool {
      return root.startCaffeineText(text);
    }

    function status(): bool {
      return root.caffeine;
    }
  }
}
