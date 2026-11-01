import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "StopwatchClock"

  readonly property int minute: 60000

  function test_stopwatch() {
    let s = StopwatchClock.idleStopwatch;
    verify(StopwatchClock.stopwatchIdle(s));
    s = StopwatchClock.startStopwatch(s, 1000);
    compare(StopwatchClock.elapsed(s, 4000), 3000);
    s = StopwatchClock.lap(s, 3000);
    s = StopwatchClock.pauseStopwatch(s, 6000);
    compare(StopwatchClock.elapsed(s, 99000), 5000, "paused time doesn't count");
    compare(StopwatchClock.lap(s, 7000), s, "no laps while paused");
    s = StopwatchClock.startStopwatch(s, 10000);
    s = StopwatchClock.lap(s, 12000);
    compare(StopwatchClock.elapsed(s, 12000), 7000);
    compare(StopwatchClock.lapRows(s), [
      {
        "number": 2,
        "split": 5000,
        "total": 7000,
        "fastest": false,
        "slowest": false
      },
      {
        "number": 1,
        "split": 2000,
        "total": 2000,
        "fastest": false,
        "slowest": false
      }
    ]);
    compare(StopwatchClock.normalizeStopwatch({
      "running": true,
      "startedAt": 0,
      "laps": [5, -1, "x"]
    }), Object.assign({}, StopwatchClock.idleStopwatch, {
      "laps": [5]
    }));
  }

  function test_timer() {
    let t = StopwatchClock.startTimer(StopwatchClock.idleTimer, 5 * minute, 0, "tea");
    compare([t.running, t.endsAt, t.label], [true, 5 * minute, "tea"]);
    compare(StopwatchClock.remaining(t, minute), 4 * minute);
    compare(StopwatchClock.timerProgress(t, minute), 0.2);
    t = StopwatchClock.pauseTimer(t, 2 * minute);
    compare(StopwatchClock.remaining(t, 50 * minute), 3 * minute);
    t = StopwatchClock.addTime(t, minute);
    compare([t.remaining, t.duration], [4 * minute, 6 * minute]);
    t = StopwatchClock.resumeTimer(t, 10 * minute);
    compare(t.endsAt, 14 * minute);
    compare(StopwatchClock.remaining(t, 20 * minute), 0, "never negative");
    t = StopwatchClock.resetTimer(t);
    verify(StopwatchClock.timerIdle(t));
    compare([t.duration, t.label, StopwatchClock.remaining(t, 0)], [6 * minute, "tea", 6 * minute]);
    compare(StopwatchClock.startTimer(t, 0, 0), t, "no duration, no timer");
  }

  function test_parse() {
    const ms = text => StopwatchClock.parse(text).ms;
    compare(ms("5m"), 5 * minute);
    compare(ms("90s"), 90000);
    compare(ms("1h30m"), 90 * minute);
    compare(ms("1h 30m 10s"), 90 * minute + 10000);
    compare(ms("1.5 min"), 90000);
    compare(ms("25"), 25 * minute, "a plain number is minutes");
    compare(ms("1:30"), 90000);
    compare(ms("1:02:03"), 3723000);
    compare(StopwatchClock.parse("10m tea"), {
      "ms": 10 * minute,
      "label": "tea"
    });
    compare(StopwatchClock.parse("3 pasta water"), {
      "ms": 3 * minute,
      "label": "pasta water"
    });
    compare(ms("tea"), 0);
    compare(ms(""), 0);
  }

  function test_format() {
    compare(StopwatchClock.format(65400, false, false), "01:05");
    compare(StopwatchClock.format(65400, true, false), "01:05.4");
    compare(StopwatchClock.format(64100, false, true), "01:05", "a countdown rounds up");
    compare(StopwatchClock.format(3723000, false, false), "1:02:03");
    compare(StopwatchClock.format(-1, false, true), "00:00");
    compare(StopwatchClock.format(3605000, false, true), "1:00:05", "a countdown from an hour");
  }

  function test_laps() {
    const s = Object.assign({}, StopwatchClock.idleStopwatch, {
      "laps": [3000, 4000, 9000]
    });
    const rows = StopwatchClock.lapRows(s);
    compare(rows.map(r => [r.number, r.fastest, r.slowest]), [[3, false, true], [2, true, false], [1, false, false]]);
    compare(StopwatchClock.lapsText(rows, n => "Lap " + n), "Lap 1\t00:03.0\t00:03.0\nLap 2\t00:01.0\t00:04.0\nLap 3\t00:05.0\t00:09.0");
  }

  function test_addTimeLess() {
    let t = StopwatchClock.startTimer(StopwatchClock.idleTimer, 5 * minute, 0, "");
    t = StopwatchClock.addTime(t, -minute, minute);
    compare([t.endsAt, t.duration], [4 * minute, 4 * minute]);
    t = StopwatchClock.addTime(t, -10 * minute, 2 * minute);
    compare([t.endsAt, t.duration], [2 * minute + 1000, 2 * minute + 1000], "a second left at least");
    compare(StopwatchClock.addTime(t, -minute), t, "less needs now");
    let p = StopwatchClock.pauseTimer(StopwatchClock.startTimer(StopwatchClock.idleTimer, 5 * minute, 0, ""), minute);
    p = StopwatchClock.addTime(p, -10 * minute);
    compare([p.remaining, p.duration], [1000, minute + 1000]);
  }

  function test_recent() {
    let list = StopwatchClock.pushRecent([], 5 * minute, "", 3);
    list = StopwatchClock.pushRecent(list, 10 * minute, "tea", 3);
    list = StopwatchClock.pushRecent(list, 5 * minute, "", 3);
    compare(list, [
      {
        "ms": 5 * minute,
        "label": ""
      },
      {
        "ms": 10 * minute,
        "label": "tea"
      }
    ], "again moves it first, once");
    list = StopwatchClock.pushRecent(list, minute, "", 3);
    list = StopwatchClock.pushRecent(list, 2 * minute, "", 3);
    compare(list.map(e => e.ms), [2 * minute, minute, 5 * minute], "capped");
    compare(StopwatchClock.pushRecent(list, 0, "", 3), list);
    compare(StopwatchClock.normalizeRecent([
      {
        "ms": 5,
        "label": "a"
      },
      {
        "ms": -1,
        "label": ""
      },
      null, "x"]), [
      {
        "ms": 5,
        "label": "a"
      }
    ]);
    compare(StopwatchClock.normalizeRecent(null), []);
  }

  function test_parseClock() {
    // 14:00 local, so the hours below are local too
    const now = new Date(2026, 10, 1, 14, 0, 0, 0).getTime();
    const ms = text => StopwatchClock.parse(text, now).ms;
    compare(ms("at 17:30"), 3.5 * 60 * minute);
    compare(ms("until 5pm"), 3 * 60 * minute);
    compare(ms("@5:15pm"), 3.25 * 60 * minute);
    compare(ms("at 15"), 60 * minute);
    compare(ms("until 12pm"), 22 * 60 * minute, "past: tomorrow");
    compare(ms("at 13:00"), 23 * 60 * minute);
    compare(ms("at 2am"), 12 * 60 * minute);
    compare(StopwatchClock.parse("until 17:00 meeting", now), {
      "ms": 3 * 60 * minute,
      "label": "meeting",
      "clock": true
    });
    compare(ms("at 25:00"), 0);
    compare(ms("at 13pm"), 0);
    compare(StopwatchClock.parse("at 17:30").ms, 0, "needs now");
    compare(ms("5:30"), 5 * minute + 30000, "no prefix: m:s");
  }

  function test_formatShort() {
    compare(StopwatchClock.formatShort(90 * minute), "1h30m");
    compare(StopwatchClock.formatShort(5 * minute), "5m");
    compare(StopwatchClock.formatShort(90000), "1m30s");
    compare(StopwatchClock.formatShort(45000), "45s");
    compare(StopwatchClock.formatShort(3605000), "1h5s");
    compare(StopwatchClock.formatShort(0), "0s");
  }
}
