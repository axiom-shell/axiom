pragma Singleton
import QtQuick

// Pure helpers for calendar events (see CalendarManager): day keys, which
// days an event covers, a day's events in order, dots, what's next,
// reminders due, editing drafts and the launcher's quick add. Events are
// axiom's occurrences (ical.Occurrence in backend/internal/calendar/ical):
// { key, calendar, allDay, start, end (epoch ms), dayStart, dayEnd
// ("YYYY-MM-DD", all-day, end exclusive), title, alarms, repeat, reminder,
// … }. No file access, processes or services.
QtObject {
  id: root

  readonly property int dayMs: 86400000

  // A local date as "YYYY-MM-DD"
  function dayKey(date) {
    const d = new Date(date);
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }

  // "YYYY-MM-DD" -> its local midnight
  function dateOf(key) {
    const parts = String(key).split("-").map(Number);
    return new Date(parts[0], parts[1] - 1, parts[2]);
  }

  function addDays(key, days) {
    const d = root.dateOf(key);
    return root.dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() + days));
  }

  // The days an event shows on: an all-day one's dayStart up to (not
  // including) dayEnd; a timed one's start day through the day its end
  // falls in (an end at midnight doesn't reach the next day)
  function daysOf(event) {
    const first = event.allDay ? event.dayStart : root.dayKey(event.start);
    const last = event.allDay ? root.addDays(event.dayEnd || root.addDays(first, 1), -1) : root.dayKey(Math.max(event.start, event.end - 1));
    const days = [first];
    let key = first;
    // Capped, so a broken event can't loop for years
    while (key < last && days.length < 366) {
      key = root.addDays(key, 1);
      days.push(key);
    }
    return days;
  }

  // All-day first, then by start, then by title
  function compare(a, b) {
    if (a.allDay !== b.allDay)
      return a.allDay ? -1 : 1;
    if (a.start !== b.start)
      return a.start - b.start;
    return String(a.title).localeCompare(String(b.title));
  }

  // { "YYYY-MM-DD": [event, …] } for the events of the `shown` calendar
  // ids, each day in order
  function byDay(events, shown) {
    const days = {};
    for (const event of events ?? []) {
      if (shown && !shown.includes(event.calendar))
        continue;
      for (const key of root.daysOf(event))
        (days[key] = days[key] ?? []).push(event);
    }
    for (const key in days)
      days[key].sort(root.compare);
    return days;
  }

  // A day's dot colors: one per calendar, in the day's order, at most `max`
  function dotColors(dayEvents, colors, max) {
    const out = [];
    for (const event of dayEvents ?? []) {
      const color = colors[event.calendar];
      if (color && !out.includes(color))
        out.push(color);
      if (out.length >= max)
        break;
    }
    return out;
  }

  // How an event sits on a day: "allDay"; "single" (starts and ends that
  // day); "starts" (runs past it); "ends" (began before it); "through"
  // (covers it whole)
  function spanOn(event, key) {
    if (event.allDay)
      return "allDay";
    const starts = root.dayKey(event.start) === key;
    const ends = root.dayKey(Math.max(event.start, event.end - 1)) === key;
    return starts && ends ? "single" : starts ? "starts" : ends ? "ends" : "through";
  }

  // Events not over by `now` that start before `until`, by start; all-day
  // ones only with `allDay`
  function upcoming(events, now, until, allDay) {
    return (events ?? []).filter(event => event.end > now && event.start < until && (allDay || !event.allDay)).sort((a, b) => a.start - b.start || root.compare(a, b));
  }

  // The event on now or next within `lookahead` ms, else null
  function nextEvent(events, now, lookahead, allDay) {
    return root.upcoming(events, now, now + lookahead, allDay)[0] ?? null;
  }

  // The earliest reminder not yet fired: an alarm from `now - grace` on
  // (one missed while asleep still shows, briefly), whose id ("<event
  // key>@<time>") isn't in `fired`. { id, time, event }, or null.
  function nextAlarm(events, now, fired, grace) {
    let best = null;
    for (const event of events ?? []) {
      for (const time of event.alarms ?? []) {
        if (time < now - grace || (best && time >= best.time))
          continue;
        const id = event.key + "@" + time;
        if (fired[id])
          continue;
        best = {
          "id": id,
          "time": time,
          "event": event
        };
      }
    }
    return best;
  }

  // The range of events to keep: from the start of the month `past` months
  // back to the start of the month after `future` months ahead
  function rangeFor(now, past, future) {
    const d = new Date(now);
    return {
      "from": new Date(d.getFullYear(), d.getMonth() - past, 1).getTime(),
      "to": new Date(d.getFullYear(), d.getMonth() + future + 1, 1).getTime()
    };
  }

  // `range` widened to hold the six weeks shown for a month (or unchanged
  // when it does)
  function widened(range, year, month) {
    const from = new Date(year, month, 1 - 7).getTime();
    const to = new Date(year, month + 1, 1 + 14).getTime();
    return {
      "from": Math.min(range.from, from),
      "to": Math.max(range.to, to)
    };
  }

  // --- Editing ---

  // A new event on `key`: on today, at the next whole hour; another day at
  // 9:00. `duration` and `reminder` in minutes (reminder -1: none).
  function newDraft(key, now, calendar, duration, reminder) {
    const today = root.dayKey(now) === key;
    const day = root.dateOf(key);
    const hour = today ? new Date(now).getHours() + 1 : 9;
    const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour).getTime();
    return {
      "calendar": calendar,
      "href": "",
      "etag": "",
      "rid": "",
      "recurring": false,
      "title": "",
      "location": "",
      "description": "",
      "allDay": false,
      "start": start,
      "end": start + duration * 60000,
      "repeat": "none",
      "reminder": reminder,
      "origStart": null,
      "origRepeat": "none",
      "origReminder": reminder
    };
  }

  // A draft of an existing event; an all-day event's `end` is its last
  // day's midnight (the editor shows the end date inclusively). A changed
  // `calendar` moves it from `originalCalendar`.
  function draftOf(event) {
    return {
      "calendar": event.calendar,
      "originalCalendar": event.calendar,
      "href": event.href,
      "etag": event.etag,
      "rid": event.rid,
      "recurring": event.recurring,
      "title": event.title,
      "location": event.location,
      "description": event.description,
      "allDay": event.allDay,
      "start": event.start,
      "end": event.allDay ? root.dateOf(root.addDays(event.dayEnd, -1)).getTime() : event.end,
      "repeat": event.repeat,
      "reminder": event.reminder,
      "origStart": event.start,
      "origRepeat": event.repeat,
      "origReminder": event.reminder
    };
  }

  // Problems that stop a save: "title", "calendar", "end"
  function problems(draft) {
    const out = [];
    if (!String(draft.title ?? "").trim())
      out.push("title");
    if (!draft.calendar)
      out.push("calendar");
    if (draft.allDay ? root.dayKey(draft.end) < root.dayKey(draft.start) : draft.end < draft.start)
      out.push("end");
    return out;
  }

  // The `event` calendar.save takes (ical.Event)
  function payloadOf(draft) {
    return {
      "title": String(draft.title).trim(),
      "location": String(draft.location ?? "").trim(),
      "description": String(draft.description ?? ""),
      "allDay": draft.allDay,
      "start": draft.start,
      "end": draft.end,
      "dayStart": draft.allDay ? root.dayKey(draft.start) : "",
      "dayEnd": draft.allDay ? root.addDays(root.dayKey(draft.end), 1) : "",
      "repeat": draft.repeat,
      "repeatChanged": draft.repeat !== draft.origRepeat,
      "reminder": draft.reminder,
      "reminderChanged": draft.reminder !== draft.origReminder,
      "origStart": draft.origStart
    };
  }

  // `time` (epoch ms) on another day, at the same time of day
  function onDay(time, key) {
    const t = new Date(time);
    const d = root.dateOf(key);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), t.getHours(), t.getMinutes()).getTime();
  }

  // "9", "930", "9:30", "9.30", "21:00", "9am", "9:30 pm", "9p" ->
  // { hour, minute }, or null
  function parseTime(text) {
    const match = /^(\d{1,2})(?:[:.]?(\d{2}))?\s*([ap])?\.?m?\.?$/i.exec(String(text ?? "").trim());
    if (!match)
      return null;
    let hour = Number(match[1]);
    const minute = Number(match[2] ?? 0);
    const half = (match[3] ?? "").toLowerCase();
    if (minute > 59 || hour > 23 || (half && (hour < 1 || hour > 12)))
      return null;
    if (half === "p" && hour < 12)
      hour += 12;
    else if (half === "a" && hour === 12)
      hour = 0;
    return {
      "hour": hour,
      "minute": minute
    };
  }

  // The launcher's quick add: "tomorrow 3pm Dentist", "fri 9-10:30
  // Standup", "2026-12-24 all day Holiday", "12/3 6pm Dinner". `words`:
  // { today, tomorrow, allDay: [phrases], weekdays: [[names] for Sunday …
  // Saturday], monthFirst (12/3 is December 3rd) }, lowercase.
  // -> { title, allDay, start, end } (end inclusive for all-day, as a
  // draft's), or null without a title.
  function parseQuickAdd(text, now, words, duration) {
    let rest = " " + String(text ?? "").trim() + " ";
    const lower = () => rest.toLowerCase();
    const take = (index, length) => {
      rest = rest.slice(0, index) + " " + rest.slice(index + length);
    };
    const findWord = phrases => {
      for (const phrase of phrases ?? []) {
        const at = lower().indexOf(" " + phrase + " ");
        if (phrase && at >= 0)
          return {
            "index": at,
            "length": phrase.length + 2
          };
      }
      return null;
    };
    const today = new Date(now);
    let day = null;
    let allDay = false;

    const allDayWord = findWord(words.allDay);
    if (allDayWord) {
      allDay = true;
      take(allDayWord.index, allDayWord.length);
    }
    const todayWord = findWord(words.today);
    const tomorrowWord = findWord(words.tomorrow);
    if (tomorrowWord) {
      day = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
      take(tomorrowWord.index, tomorrowWord.length);
    } else if (todayWord) {
      day = new Date(today.getFullYear(), today.getMonth(), today.getDate());
      take(todayWord.index, todayWord.length);
    }
    if (!day) {
      for (let weekday = 0; weekday < 7 && !day; weekday++) {
        const found = findWord((words.weekdays ?? [])[weekday]);
        if (!found)
          continue;
        day = new Date(today.getFullYear(), today.getMonth(), today.getDate() + (weekday - today.getDay() + 7) % 7);
        take(found.index, found.length);
      }
    }
    if (!day) {
      const iso = / (\d{4})-(\d{1,2})-(\d{1,2}) /.exec(rest);
      const short = / (\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))? /.exec(rest);
      if (iso) {
        day = new Date(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3]));
        take(iso.index, iso[0].length);
      } else if (short) {
        const month = Number(words.monthFirst ? short[1] : short[2]) - 1;
        const date = Number(words.monthFirst ? short[2] : short[1]);
        let year = short[3] ? Number(short[3]) : today.getFullYear();
        if (year < 100)
          year += 2000;
        day = new Date(year, month, date);
        // A date without a year that has passed is next year's
        if (!short[3] && day < new Date(today.getFullYear(), today.getMonth(), today.getDate()))
          day = new Date(year + 1, month, date);
        take(short.index, short[0].length);
      }
    }
    day = day ?? new Date(today.getFullYear(), today.getMonth(), today.getDate());

    let start = null;
    let end = null;
    if (!allDay) {
      // A range ("9-10", "9am-10:30am", "15:00-16:00": a half on the end
      // only applies to both) or one time; written with an "at" or not
      const timeRe = "(\\d{1,2}(?:[:.]?\\d{2})?\\s?(?:[ap]\\.?m?\\.?)?)";
      const range = new RegExp(" " + timeRe + "\\s?[-–]\\s?" + timeRe + " ", "i").exec(rest);
      if (range) {
        const to = root.parseTime(range[2]);
        let from = root.parseTime(range[1]);
        const endHalf = /([ap])/i.exec(range[2]);
        if (from && to && !/[ap]/i.test(range[1]) && endHalf)
          from = root.parseTime(range[1] + endHalf[1]) ?? from;
        if (from && to) {
          start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), from.hour, from.minute).getTime();
          end = new Date(day.getFullYear(), day.getMonth(), day.getDate(), to.hour, to.minute).getTime();
          if (end <= start)
            end += root.dayMs;
          take(range.index, range[0].length);
        }
      }
      // A bare number counts only as a time with am/pm, a colon or an "at"
      // ("Room 5 at 3pm": 3pm)
      const singleRe = new RegExp("(?= (?:@|at )?" + timeRe + " )", "gi");
      for (let match = singleRe.exec(rest); start === null && match; match = singleRe.exec(rest)) {
        const found = new RegExp("^ (@|at )?" + timeRe + " ", "i").exec(rest.slice(match.index));
        singleRe.lastIndex = match.index + 1;
        if (!found || !(/[ap:.]/i.test(found[2]) || found[1]))
          continue;
        const at = root.parseTime(found[2]);
        if (!at)
          continue;
        start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), at.hour, at.minute).getTime();
        end = start + duration * 60000;
        take(match.index, found[0].length);
      }
      // A day without a time: all day
      if (start === null)
        allDay = true;
    }
    const title = rest.replace(/\s+/g, " ").trim();
    if (!title)
      return null;
    if (allDay) {
      start = day.getTime();
      end = start;
    }
    return {
      "title": title,
      "allDay": allDay,
      "start": start,
      "end": end
    };
  }
}
