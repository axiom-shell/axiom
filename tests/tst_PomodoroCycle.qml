import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "PomodoroCycle"

  readonly property int minute: 60000
  readonly property var settings: ({
      "work": 25 * minute,
      "shortBreak": 5 * minute,
      "longBreak": 15 * minute,
      "longBreakEvery": 2
    })

  function test_start_pause_resume() {
    let state = PomodoroCycle.idle;
    verify(PomodoroCycle.isIdle(state));
    compare(PomodoroCycle.remaining(state, 0, settings), 25 * minute);
    state = PomodoroCycle.start(state, 1000, settings);
    compare([state.running, state.endsAt], [true, 1000 + 25 * minute]);
    compare(PomodoroCycle.remaining(state, 1000 + 10 * minute, settings), 15 * minute);
    compare(PomodoroCycle.progress(state, 1000 + 5 * minute, settings), 0.2);
    state = PomodoroCycle.pause(state, 1000 + 10 * minute);
    compare([state.running, state.pausedRemaining], [false, 15 * minute]);
    verify(!PomodoroCycle.isIdle(state));
    // Paused time doesn't count
    compare(PomodoroCycle.remaining(state, 99 * minute, settings), 15 * minute);
    state = PomodoroCycle.start(state, 50 * minute, settings);
    compare(state.endsAt, 65 * minute);
    compare(PomodoroCycle.remaining(state, 70 * minute, settings), 0, "never negative");
  }

  function test_advance() {
    const auto = {
      "work": false,
      "breaks": true
    };
    let state = PomodoroCycle.start(PomodoroCycle.idle, 0, settings);
    state = PomodoroCycle.advance(state, 100, settings, auto);
    compare([state.phase, state.completed, state.running, state.endsAt], ["short", 1, true, 100 + 5 * minute]);
    state = PomodoroCycle.advance(state, 200, settings, auto);
    compare([state.phase, state.completed, state.running], ["work", 1, false], "a break ends waiting");
    state = PomodoroCycle.advance(PomodoroCycle.start(state, 300, settings), 300, settings, auto);
    compare([state.phase, state.completed], ["long", 2], "every second session: a long break");
    verify(PomodoroCycle.isBreak(state));
    compare(PomodoroCycle.reset(state, false), Object.assign({}, PomodoroCycle.idle, {
      "completed": 2
    }));
    compare(PomodoroCycle.reset(state, true), PomodoroCycle.idle);
  }

  function test_advance_counts_only_started() {
    const auto = {
      "work": false,
      "breaks": false
    };
    let state = PomodoroCycle.advance(PomodoroCycle.idle, 0, settings, auto);
    compare([state.phase, state.completed], ["short", 0], "skipped unstarted: not counted");
    state = PomodoroCycle.pause(PomodoroCycle.start(PomodoroCycle.idle, 0, settings), minute);
    state = PomodoroCycle.advance(state, 2 * minute, settings, auto);
    compare([state.phase, state.completed], ["short", 1], "skipped while paused part way: counted");
  }

  function test_normalize() {
    compare(PomodoroCycle.normalize(null), PomodoroCycle.idle);
    compare(PomodoroCycle.normalize({
      "phase": "nap",
      "running": true,
      "endsAt": 0,
      "completed": 2.7
    }), Object.assign({}, PomodoroCycle.idle, {
      "completed": 2
    }));
  }
}
