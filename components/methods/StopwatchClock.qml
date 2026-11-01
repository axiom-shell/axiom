pragma Singleton
import QtQuick

// The one-off timer's and the stopwatch's rules, for StopwatchManager.
// Both keep absolute times, so the time shown is worked out, never counted.
// A stopwatch is { running, startedAt, elapsed (ms banked before
// startedAt), laps ([ms at each lap]) }; a timer is { running, endsAt,
// remaining (ms left while paused, 0 when not started), duration (ms it was
// set to), label }. Every function returns a new state.
QtObject {
  id: root

  readonly property var idleStopwatch: ({
      "running": false,
      "startedAt": 0,
      "elapsed": 0,
      "laps": []
    })
  readonly property var idleTimer: ({
      "running": false,
      "endsAt": 0,
      "remaining": 0,
      "duration": 0,
      "label": ""
    })

  function _positive(value) {
    return typeof value === "number" && isFinite(value) && value > 0 ? value : 0;
  }

  // -- Stopwatch --

  function normalizeStopwatch(state) {
    const s = state && typeof state === "object" ? state : {};
    const running = s.running === true && root._positive(s.startedAt) > 0;
    return {
      "running": running,
      "startedAt": running ? s.startedAt : 0,
      "elapsed": root._positive(s.elapsed),
      "laps": Array.isArray(s.laps) ? s.laps.filter(lap => root._positive(lap) > 0) : []
    };
  }

  function elapsed(state, now) {
    return state.elapsed + (state.running ? Math.max(0, now - state.startedAt) : 0);
  }

  function stopwatchIdle(state) {
    return !state.running && state.elapsed === 0;
  }

  function startStopwatch(state, now) {
    return state.running ? state : Object.assign({}, state, {
      "running": true,
      "startedAt": now
    });
  }

  function pauseStopwatch(state, now) {
    return !state.running ? state : Object.assign({}, state, {
      "running": false,
      "startedAt": 0,
      "elapsed": root.elapsed(state, now)
    });
  }

  // The total at this moment, added to the laps (only while running)
  function lap(state, now) {
    return !state.running ? state : Object.assign({}, state, {
      "laps": state.laps.concat([root.elapsed(state, now)])
    });
  }

  // [{ number, split (since the lap before), total, fastest, slowest }],
  // the latest first; fastest and slowest only from three laps on
  function lapRows(state) {
    const splits = state.laps.map((total, i) => total - (i > 0 ? state.laps[i - 1] : 0));
    const marked = splits.length >= 3;
    const fastest = marked ? splits.indexOf(Math.min(...splits)) : -1;
    const slowest = marked ? splits.indexOf(Math.max(...splits)) : -1;
    return state.laps.map((total, i) => ({
          "number": i + 1,
          "split": splits[i],
          "total": total,
          "fastest": i === fastest,
          "slowest": i === slowest
        })).reverse();
  }

  // lapRows as lines to copy, the first lap first: `name(number)`, its
  // split and its total
  function lapsText(rows, name) {
    return rows.slice().reverse().map(row => [name(row.number), root.format(row.split, true, false), root.format(row.total, true, false)].join("\t")).join("\n");
  }

  // -- Timer --

  function normalizeTimer(state) {
    const s = state && typeof state === "object" ? state : {};
    const running = s.running === true && root._positive(s.endsAt) > 0;
    return {
      "running": running,
      "endsAt": running ? s.endsAt : 0,
      "remaining": running ? 0 : root._positive(s.remaining),
      "duration": root._positive(s.duration),
      "label": typeof s.label === "string" ? s.label : ""
    };
  }

  // Ms left: to endsAt while running, what a pause left, else the duration
  function remaining(state, now) {
    if (state.running)
      return Math.max(0, state.endsAt - now);
    return state.remaining > 0 ? state.remaining : state.duration;
  }

  // Neither running nor paused part way
  function timerIdle(state) {
    return !state.running && state.remaining === 0;
  }

  // 0 at the start, 1 at the end
  function timerProgress(state, now) {
    return state.duration > 0 ? Math.max(0, Math.min(1, 1 - root.remaining(state, now) / state.duration)) : 0;
  }

  // Starts a new countdown of `duration` ms (a label to remind of it)
  function startTimer(state, duration, now, label) {
    if (!(duration > 0))
      return state;
    return {
      "running": true,
      "endsAt": now + duration,
      "remaining": 0,
      "duration": duration,
      "label": label ?? ""
    };
  }

  function pauseTimer(state, now) {
    return !state.running ? state : Object.assign({}, state, {
      "running": false,
      "endsAt": 0,
      "remaining": Math.max(1, state.endsAt - now)
    });
  }

  function resumeTimer(state, now) {
    if (state.running || root.remaining(state, now) <= 0)
      return state;
    return Object.assign({}, state, {
      "running": true,
      "endsAt": now + root.remaining(state, now),
      "remaining": 0
    });
  }

  // More time on a running or paused timer (the whole grows with it), or
  // less (a negative `ms`, as of `now`), never under a second left
  function addTime(state, ms, now) {
    if (state.running) {
      if (ms < 0 && now === undefined)
        return state;
      const endsAt = ms < 0 ? Math.max(Math.min(state.endsAt, now + 1000), state.endsAt + ms) : state.endsAt + ms;
      return Object.assign({}, state, {
        "endsAt": endsAt,
        "duration": state.duration + endsAt - state.endsAt
      });
    }
    if (state.remaining > 0) {
      const remaining = Math.max(Math.min(state.remaining, 1000), state.remaining + ms);
      return Object.assign({}, state, {
        "remaining": remaining,
        "duration": state.duration + remaining - state.remaining
      });
    }
    return state;
  }

  // When a running timer ends (epoch ms), else 0
  function endsAt(state) {
    return state.running ? state.endsAt : 0;
  }

  // Recent timers, [{ ms, label }], the newest first: `ms` and `label` put
  // first (once), at most `max`
  function pushRecent(list, ms, label, max) {
    if (!(ms > 0))
      return list;
    const entry = {
      "ms": ms,
      "label": label ?? ""
    };
    return [entry].concat((Array.isArray(list) ? list : []).filter(e => e && (e.ms !== entry.ms || e.label !== entry.label))).slice(0, max);
  }

  // Recent timers from saved state: only well-formed ones
  function normalizeRecent(list) {
    return Array.isArray(list) ? list.filter(e => e && root._positive(e.ms) > 0 && typeof e.label === "string").map(e => ({
          "ms": e.ms,
          "label": e.label
        })) : [];
  }

  // Stopped, keeping the duration (to start the same again) and label
  function resetTimer(state) {
    return Object.assign({}, root.idleTimer, {
      "duration": state.duration,
      "label": state.label
    });
  }

  // "90" (minutes), "90s", "5m", "1h30m", "1h 30m 10s", "1:30" (m:s),
  // "1:02:03" (h:m:s), and a label after it ("10m tea"): { ms, label }, ms
  // 0 when it doesn't start with a duration. With `now` (epoch ms), also a
  // time of day after at, until or @ ("at 17:30", "until 5pm", "@9:15am
  // standup"): the time until then, tomorrow's once it's past, with
  // `clock` set
  function parse(text, now) {
    const s = String(text ?? "").trim();
    let match = s.match(/^(?:at|until|@)\s*(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a|p)?(?:\s+(.*))?$/i);
    if (match) {
      let hour = Number(match[1]);
      const minute = Number(match[2] ?? 0);
      const half = (match[3] ?? "").toLowerCase();
      if (now === undefined || minute > 59 || (half !== "" ? hour < 1 || hour > 12 : hour > 23))
        return {
          "ms": 0,
          "label": ""
        };
      if (half !== "")
        hour = hour % 12 + (half.startsWith("p") ? 12 : 0);
      const target = new Date(now);
      target.setHours(hour, minute, 0, 0);
      if (target.getTime() <= now)
        target.setDate(target.getDate() + 1);
      return {
        "ms": target.getTime() - now,
        "label": (match[4] ?? "").trim(),
        "clock": true
      };
    }
    match = s.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?(?:\s+(.*))?$/);
    if (match) {
      const parts = [match[1], match[2], match[3]].filter(p => p !== undefined).map(Number);
      const ms = (parts.length === 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1]) * 1000;
      return {
        "ms": ms,
        "label": (match[4] ?? "").trim()
      };
    }
    match = s.match(/^((?:\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)\s*)+)(.*)$/i);
    if (match) {
      let ms = 0;
      const unit = /(\d+(?:\.\d+)?)\s*([a-z]+)/gi;
      let part;
      while ((part = unit.exec(match[1])) !== null) {
        const n = Number(part[1]);
        const u = part[2].toLowerCase();
        ms += n * (u.startsWith("h") ? 3600000 : u.startsWith("m") ? 60000 : 1000);
      }
      return {
        "ms": Math.round(ms),
        "label": match[2].trim()
      };
    }
    match = s.match(/^(\d+(?:\.\d+)?)(?:\s+(.*))?$/);
    if (match)
      return {
        "ms": Math.round(Number(match[1]) * 60000),
        "label": (match[2] ?? "").trim()
      };
    return {
      "ms": 0,
      "label": ""
    };
  }

  // As a duration is typed: "1h30m", "5m", "1m30s", "45s" (whole seconds)
  function formatShort(ms) {
    const total = Math.round(Math.max(0, ms) / 1000);
    const parts = [[Math.floor(total / 3600), "h"], [Math.floor(total % 3600 / 60), "m"], [total % 60, "s"]].filter(p => p[0] > 0);
    return parts.length > 0 ? parts.map(p => p[0] + p[1]).join("") : "0s";
  }

  // "mm:ss", "h:mm:ss" from an hour; `tenths` adds ".t" (a stopwatch).
  // A countdown rounds up (`up`), so 00:00 is its end
  function format(ms, tenths, up) {
    const value = Math.max(0, ms);
    const total = up ? Math.ceil(value / 1000) : Math.floor(value / 1000);
    const h = Math.floor(total / 3600);
    const m = Math.floor(total % 3600 / 60);
    const sec = total % 60;
    const pad = n => (n < 10 ? "0" : "") + n;
    const base = h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${pad(m)}:${pad(sec)}`;
    return tenths ? base + "." + Math.floor(value % 1000 / 100) : base;
  }
}
