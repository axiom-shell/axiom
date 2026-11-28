import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "CalendarEvents"

  readonly property var words: ({
      "today": ["today"],
      "tomorrow": ["tomorrow", "tmr"],
      "allDay": ["all day", "all-day"],
      "weekdays": [["sunday", "sun"], ["monday", "mon"], ["tuesday", "tue"], ["wednesday", "wed"], ["thursday", "thu"], ["friday", "fri"], ["saturday", "sat"]],
      "monthFirst": true
    })

  function ms(y, mo, d, h, mi) {
    return new Date(y, mo - 1, d, h ?? 0, mi ?? 0).getTime();
  }

  function timed(title, start, end, extra) {
    return Object.assign({
      "key": title,
      "calendar": "a|cal",
      "allDay": false,
      "start": start,
      "end": end,
      "dayStart": "",
      "dayEnd": "",
      "title": title,
      "alarms": []
    }, extra ?? {});
  }

  function allDay(title, dayStart, dayEnd, extra) {
    const parts = dayStart.split("-").map(Number);
    return Object.assign({
      "key": title,
      "calendar": "a|cal",
      "allDay": true,
      "start": new Date(parts[0], parts[1] - 1, parts[2]).getTime(),
      "end": CalendarEvents.dateOf(dayEnd).getTime(),
      "dayStart": dayStart,
      "dayEnd": dayEnd,
      "title": title,
      "alarms": []
    }, extra ?? {});
  }

  function test_day_keys() {
    compare(CalendarEvents.dayKey(new Date(2026, 0, 5, 23, 59)), "2026-01-05");
    compare(CalendarEvents.addDays("2026-12-31", 1), "2027-01-01");
    compare(CalendarEvents.addDays("2026-03-01", -1), "2026-02-28");
    compare(CalendarEvents.dateOf("2026-10-05").getTime(), ms(2026, 10, 5));
    // Across a DST change (in zones with one) days stay whole
    compare(CalendarEvents.addDays("2026-03-28", 2), "2026-03-30");
    compare(CalendarEvents.addDays("2026-10-24", 3), "2026-10-27");
  }

  function test_days_of() {
    compare(CalendarEvents.daysOf(timed("a", ms(2026, 10, 5, 9), ms(2026, 10, 5, 10))), ["2026-10-05"]);
    compare(CalendarEvents.daysOf(timed("night", ms(2026, 10, 5, 22), ms(2026, 10, 6, 2))), ["2026-10-05", "2026-10-06"]);
    compare(CalendarEvents.daysOf(timed("to midnight", ms(2026, 10, 5, 22), ms(2026, 10, 6))), ["2026-10-05"], "an end at midnight stays on its day");
    compare(CalendarEvents.daysOf(timed("zero", ms(2026, 10, 5, 9), ms(2026, 10, 5, 9))), ["2026-10-05"]);
    compare(CalendarEvents.daysOf(allDay("trip", "2026-10-30", "2026-11-02")), ["2026-10-30", "2026-10-31", "2026-11-01"], "the end is exclusive");
    compare(CalendarEvents.daysOf(allDay("one", "2026-10-05", "2026-10-06")), ["2026-10-05"]);
  }

  function test_by_day_orders_and_filters() {
    const events = [timed("late", ms(2026, 10, 5, 15), ms(2026, 10, 5, 16)), timed("early", ms(2026, 10, 5, 9), ms(2026, 10, 5, 10)), allDay("holiday", "2026-10-05", "2026-10-06"), timed("hidden", ms(2026, 10, 5, 8), ms(2026, 10, 5, 9), {
        "calendar": "b|other"
      })];
    const days = CalendarEvents.byDay(events, ["a|cal"]);
    compare(days["2026-10-05"].map(e => e.title), ["holiday", "early", "late"]);
    compare(Object.keys(days), ["2026-10-05"]);
    compare(CalendarEvents.byDay(events, null)["2026-10-05"].length, 4, "no filter shows every calendar");
  }

  function test_dot_colors() {
    const colors = {
      "a|cal": "#ff0000",
      "b|cal": "#00ff00",
      "c|cal": "#0000ff"
    };
    const day = ["a|cal", "a|cal", "b|cal", "x|missing", "c|cal"].map(calendar => ({
          "calendar": calendar
        }));
    compare(CalendarEvents.dotColors(day, colors, 3), ["#ff0000", "#00ff00", "#0000ff"]);
    compare(CalendarEvents.dotColors(day, colors, 2), ["#ff0000", "#00ff00"]);
    compare(CalendarEvents.dotColors([], colors, 3), []);
    const named = {
      "a|cal": "accent",
      "b|cal": "base0D",
      "c|cal": "#ff0000"
    };
    compare(CalendarEvents.dotColors(day, named, 3), ["accent", "base0D", "#ff0000"], "colour names pass through and dedupe as strings");
  }

  function test_span_on() {
    const night = timed("night", ms(2026, 10, 5, 22), ms(2026, 10, 7, 2));
    compare(CalendarEvents.spanOn(night, "2026-10-05"), "starts");
    compare(CalendarEvents.spanOn(night, "2026-10-06"), "through");
    compare(CalendarEvents.spanOn(night, "2026-10-07"), "ends");
    compare(CalendarEvents.spanOn(timed("a", ms(2026, 10, 5, 9), ms(2026, 10, 5, 10)), "2026-10-05"), "single");
    compare(CalendarEvents.spanOn(allDay("h", "2026-10-05", "2026-10-06"), "2026-10-05"), "allDay");
  }

  function test_next_event() {
    const now = ms(2026, 10, 5, 12);
    const events = [timed("past", ms(2026, 10, 5, 9), ms(2026, 10, 5, 10)), timed("now", ms(2026, 10, 5, 11, 30), ms(2026, 10, 5, 12, 30)), timed("later", ms(2026, 10, 5, 15), ms(2026, 10, 5, 16)), allDay("today", "2026-10-05", "2026-10-06")];
    compare(CalendarEvents.nextEvent(events, now, 3600000, false).title, "now", "an event under way counts");
    compare(CalendarEvents.upcoming(events, now, now + 6 * 3600000, false).map(e => e.title), ["now", "later"]);
    compare(CalendarEvents.upcoming(events, now, now + 6 * 3600000, true).map(e => e.title), ["today", "now", "later"]);
    compare(CalendarEvents.nextEvent([events[0]], now, 3600000, false), null);
  }

  function test_next_alarm() {
    const now = ms(2026, 10, 5, 12);
    const events = [timed("a", ms(2026, 10, 5, 13), ms(2026, 10, 5, 14), {
        "alarms": [ms(2026, 10, 5, 12, 50), ms(2026, 10, 5, 11)]
      }), timed("b", ms(2026, 10, 5, 12, 30), ms(2026, 10, 5, 13), {
        "alarms": [ms(2026, 10, 5, 12, 20)]
      })];
    const next = CalendarEvents.nextAlarm(events, now, {}, 300000);
    compare(next.event.title, "b");
    compare(next.id, "b@" + ms(2026, 10, 5, 12, 20));
    const fired = {};
    fired[next.id] = true;
    compare(CalendarEvents.nextAlarm(events, now, fired, 300000).event.title, "a");
    // Missed by more than the grace: skipped
    compare(CalendarEvents.nextAlarm(events, now + 3 * 3600000, {}, 300000), null);
    // Missed within it: still due
    compare(CalendarEvents.nextAlarm(events, ms(2026, 10, 5, 12, 22), {}, 300000).event.title, "b");
  }

  function test_ranges() {
    const range = CalendarEvents.rangeFor(ms(2026, 10, 15), 2, 12);
    compare(range.from, ms(2026, 8, 1));
    compare(range.to, ms(2027, 11, 1));
    compare(CalendarEvents.widened(range, 2026, 9), range, "a month inside stays");
    const back = CalendarEvents.widened(range, 2025, 0);
    compare(back.from, ms(2024, 12, 25));
    compare(back.to, range.to);
  }

  function test_drafts() {
    const now = ms(2026, 10, 5, 14, 20);
    const fresh = CalendarEvents.newDraft("2026-10-05", now, "a|cal", 60, 10);
    compare(fresh.start, ms(2026, 10, 5, 15));
    compare(fresh.end, ms(2026, 10, 5, 16));
    compare(CalendarEvents.newDraft("2026-10-08", now, "a|cal", 30, -1).start, ms(2026, 10, 8, 9));
    compare(CalendarEvents.problems(fresh), ["title"]);
    fresh.title = "  Lunch ";
    compare(CalendarEvents.problems(fresh), []);
    const payload = CalendarEvents.payloadOf(fresh);
    compare(payload.title, "Lunch");
    compare(payload.repeatChanged, false);
    compare(payload.reminderChanged, false);
    fresh.end = fresh.start - 1;
    compare(CalendarEvents.problems(fresh), ["end"]);

    // All-day: the draft's end is the last day; the payload's is exclusive
    const trip = CalendarEvents.draftOf(allDay("trip", "2026-10-10", "2026-10-13", {
      "href": "h",
      "etag": "e",
      "rid": "",
      "recurring": false,
      "location": "",
      "description": "",
      "repeat": "none",
      "reminder": -1
    }));
    compare(CalendarEvents.dayKey(trip.end), "2026-10-12");
    compare(CalendarEvents.problems(trip), []);
    trip.repeat = "yearly";
    const tripPayload = CalendarEvents.payloadOf(trip);
    compare(tripPayload.dayStart, "2026-10-10");
    compare(tripPayload.dayEnd, "2026-10-13");
    compare(tripPayload.repeatChanged, true);
    compare(tripPayload.origStart, ms(2026, 10, 10));
    // A one-day all-day event can end on its start day
    trip.end = trip.start;
    compare(CalendarEvents.problems(trip), []);
    compare(CalendarEvents.onDay(ms(2026, 10, 5, 9, 30), "2026-12-01"), ms(2026, 12, 1, 9, 30));
  }

  function test_parse_time() {
    compare(CalendarEvents.parseTime("9"), {
      "hour": 9,
      "minute": 0
    });
    compare(CalendarEvents.parseTime("9:30"), {
      "hour": 9,
      "minute": 30
    });
    compare(CalendarEvents.parseTime("930"), {
      "hour": 9,
      "minute": 30
    });
    compare(CalendarEvents.parseTime("21.15"), {
      "hour": 21,
      "minute": 15
    });
    compare(CalendarEvents.parseTime("9pm"), {
      "hour": 21,
      "minute": 0
    });
    compare(CalendarEvents.parseTime("12 am"), {
      "hour": 0,
      "minute": 0
    });
    compare(CalendarEvents.parseTime("12:30p.m."), {
      "hour": 12,
      "minute": 30
    });
    compare(CalendarEvents.parseTime("24:00"), null);
    compare(CalendarEvents.parseTime("13pm"), null);
    compare(CalendarEvents.parseTime("9:75"), null);
    compare(CalendarEvents.parseTime("noon"), null);
  }

  function test_parse_quick_add() {
    // Monday 5 October 2026, noon
    const now = ms(2026, 10, 5, 12);
    const parse = text => CalendarEvents.parseQuickAdd(text, now, words, 60);

    const dentist = parse("tomorrow 3pm Dentist");
    compare(dentist.title, "Dentist");
    compare(dentist.allDay, false);
    compare(dentist.start, ms(2026, 10, 6, 15));
    compare(dentist.end, ms(2026, 10, 6, 16));

    const standup = parse("fri 9-10:30 Standup");
    compare(standup.title, "Standup");
    compare(standup.start, ms(2026, 10, 9, 9));
    compare(standup.end, ms(2026, 10, 9, 10, 30));

    const evening = parse("Dinner 7-9pm");
    compare(evening.start, ms(2026, 10, 5, 19), "the end's pm applies to both");
    compare(evening.end, ms(2026, 10, 5, 21));

    const monday = parse("Mon Gym at 18:00");
    compare(monday.start, ms(2026, 10, 5, 18), "today's weekday is today");
    compare(monday.title, "Gym");

    const holiday = parse("2026-12-24 all day Holiday");
    compare(holiday.allDay, true);
    compare(holiday.start, ms(2026, 12, 24));
    compare(holiday.end, ms(2026, 12, 24));

    const dayOnly = parse("10/12 Trip");
    compare(dayOnly.allDay, true, "a day without a time is all day");
    compare(dayOnly.start, ms(2026, 10, 12));

    compare(parse("1/2 Party").start, ms(2027, 1, 2), "a passed date without a year is next year's");

    const room = parse("Meet in room 5 at 3pm");
    compare(room.title, "Meet in room 5", "a bare number is part of the title");
    compare(room.start, ms(2026, 10, 5, 15));

    const late = parse("today 23:00-1:00 Party");
    compare(late.end, ms(2026, 10, 6, 1), "a range past midnight ends the next day");

    compare(parse("tomorrow 3pm"), null, "no title");
    compare(parse(""), null);
  }
}
