package ical

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"
)

// zones reads TZIDs from the system's zoneinfo, local time being UTC so
// the expected values don't depend on the machine
var zones = Zones{Local: time.UTC, Lookup: func(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		return nil
	}
	return loc
}}

func ms(y int, m time.Month, d int, hm ...int) int64 {
	h, mi := 0, 0
	if len(hm) > 0 {
		h = hm[0]
	}
	if len(hm) > 1 {
		mi = hm[1]
	}
	return time.Date(y, m, d, h, mi, 0, 0, time.UTC).UnixMilli()
}

func ev(body string) string {
	return "BEGIN:VEVENT\r\n" + strings.ReplaceAll(strings.TrimSpace(body), "\n", "\r\n") + "\r\nEND:VEVENT\r\n"
}

func cal(evs ...string) string {
	return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n" + strings.Join(evs, "") + "END:VCALENDAR\r\n"
}

func expand(t *testing.T, text string, from, to int64) []Occurrence {
	t.Helper()
	c, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	out, err := zones.Expand(c, "a|cal", "h", "", from, to)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

// The expansion's hard cases, in October 2026 (checked against
// recurring-ical-events when the Python helper did this)
func TestRecurrences(t *testing.T) {
	t.Parallel()
	hour := int64(3600 * 1000)
	type row struct {
		start, end int64
		rid, day   string
	}
	timed := func(y int, m time.Month, d, h int, length int64) row {
		s := ms(y, m, d, h)
		return row{s, s + length, fmt.Sprintf("T:%d", s/1000), ""}
	}
	daily := func(from, to, h int, length int64) []row {
		var out []row
		for d := from; d <= to; d++ {
			out = append(out, timed(2026, 10, d, h, length))
		}
		return out
	}
	cases := []struct {
		name, ics string
		want      []row
	}{
		// Wall-clock time kept across Berlin's change to winter time (Oct 25)
		{"dst", cal(ev("UID:a\nDTSTART;TZID=Europe/Berlin:20261020T090000\nDTEND;TZID=Europe/Berlin:20261020T100000\nRRULE:FREQ=WEEKLY")),
			[]row{timed(2026, 10, 20, 7, hour), timed(2026, 10, 27, 8, hour)}},
		// A UTC UNTIL on a zoned start, and on a floating one (read as wall time)
		{"until", cal(ev("UID:a\nDTSTART;TZID=America/New_York:20261001T090000\nDURATION:PT1H\nRRULE:FREQ=DAILY;UNTIL=20261005T130000Z")),
			daily(1, 5, 13, hour)},
		{"floating", cal(ev("UID:a\nDTSTART:20261001T090000\nDTEND:20261001T093000\nRRULE:FREQ=DAILY;UNTIL=20261003T090000Z")),
			daily(1, 3, 9, hour/2)},
		// A DATE UNTIL counts its whole day; all-day stays all-day
		{"allDay", cal(ev("UID:a\nDTSTART;VALUE=DATE:20261001\nRRULE:FREQ=WEEKLY;UNTIL=20261015;BYDAY=TH,FR")), nil},
		// RDATEs (one a period with its own length), the start excluded
		{"rdate", cal(ev("UID:a\nDTSTART:20261002T100000Z\nDTEND:20261002T110000Z\nEXDATE:20261002T100000Z\n" +
			"RDATE:20261015T100000Z\nRDATE;VALUE=PERIOD:20261020T100000Z/20261020T140000Z")),
			[]row{timed(2026, 10, 15, 10, hour), timed(2026, 10, 20, 10, 4*hour)}},
		// An occurrence moved out of the window, and one moved into it
		{"movedOut", cal(ev("UID:a\nDTSTART:20261001T100000Z\nDTEND:20261001T110000Z\nRRULE:FREQ=DAILY;COUNT=3"),
			ev("UID:a\nRECURRENCE-ID:20261002T100000Z\nDTSTART:20261210T100000Z\nDTEND:20261210T110000Z")),
			[]row{timed(2026, 10, 1, 10, hour), timed(2026, 10, 3, 10, hour)}},
		{"movedIn", cal(ev("UID:a\nDTSTART:20260901T100000Z\nDTEND:20260901T110000Z\nRRULE:FREQ=DAILY;COUNT=10"),
			ev("UID:a\nRECURRENCE-ID:20260905T100000Z\nDTSTART:20261012T100000Z\nDTEND:20261012T110000Z")),
			[]row{{ms(2026, 10, 12, 10), ms(2026, 10, 12, 11), fmt.Sprintf("T:%d", ms(2026, 9, 5, 10)/1000), ""}}},
		// Started before the window, still running in it
		{"spanning", cal(ev("UID:a\nDTSTART:20260928T100000Z\nDTEND:20261003T100000Z\nRRULE:FREQ=WEEKLY;COUNT=2")),
			[]row{timed(2026, 9, 28, 10, 120*hour), timed(2026, 10, 5, 10, 120*hour)}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			var got []row
			var days []string
			for _, o := range expand(t, c.ics, ms(2026, 10, 1), ms(2026, 11, 1)) {
				got = append(got, row{o.Start, o.End, o.Rid, o.DayStart})
				days = append(days, o.DayStart)
			}
			if c.name == "allDay" {
				if want := []string{"2026-10-01", "2026-10-02", "2026-10-08", "2026-10-09", "2026-10-15"}; !reflect.DeepEqual(days, want) {
					t.Errorf("days %v, want %v", days, want)
				}
				return
			}
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("got %v\nwant %v", got, c.want)
			}
		})
	}
}

const feed = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
X-WR-CALNAME:Team
BEGIN:VEVENT
UID:weekly
DTSTART;TZID=Europe/Berlin:20260707T100000
DTEND;TZID=Europe/Berlin:20260707T103000
RRULE:FREQ=WEEKLY;COUNT=4
EXDATE;TZID=Europe/Berlin:20260714T100000
SUMMARY:Standup
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:weekly
RECURRENCE-ID;TZID=Europe/Berlin:20260721T100000
DTSTART;TZID=Europe/Berlin:20260721T120000
DTEND;TZID=Europe/Berlin:20260721T123000
SUMMARY:Standup (moved)
END:VEVENT
BEGIN:VEVENT
UID:trip
DTSTART;VALUE=DATE:20260710
DTEND;VALUE=DATE:20260713
SUMMARY:Trip
LOCATION:Coast
DESCRIPTION:Bring a map\, and boots\nand food
END:VEVENT
END:VCALENDAR
`

// A feed's occurrences: a weekly series with an exclusion, an override
// and an alarm, and an all-day event
func TestFeedOccurrences(t *testing.T) {
	t.Parallel()
	events := expand(t, feed, ms(2026, 7, 1), ms(2026, 8, 1))
	var got [][2]any
	for _, e := range events {
		got = append(got, [2]any{e.Title, e.Start})
	}
	want := [][2]any{
		{"Standup", ms(2026, 7, 7, 8)}, // 10:00 in Berlin's summer time
		{"Trip", ms(2026, 7, 10)},
		{"Standup (moved)", ms(2026, 7, 21, 10)}, // the override; the 14th is excluded
		{"Standup", ms(2026, 7, 28, 8)},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v\nwant %v", got, want)
	}
	first, trip, moved := events[0], events[1], events[2]
	if first.Title != "Standup" || !first.Recurring || first.Repeat != "custom" || first.Reminder != 15 ||
		!reflect.DeepEqual(first.Alarms, []int64{ms(2026, 7, 7, 7, 45)}) || first.Key != "a|cal|weekly|"+first.Rid {
		t.Errorf("first %+v", first)
	}
	if trip.Title != "Trip" || !trip.AllDay || trip.DayStart != "2026-07-10" || trip.DayEnd != "2026-07-13" ||
		trip.Location != "Coast" || trip.Recurring || trip.Rid != "" || trip.Description != "Bring a map, and boots\nand food" {
		t.Errorf("trip %+v", trip)
	}
	if moved.Title != "Standup (moved)" || moved.Rid != fmt.Sprintf("T:%d", ms(2026, 7, 21, 8)/1000) || len(moved.Alarms) != 0 {
		t.Errorf("moved %+v", moved)
	}
}

func TestRepeatOf(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"RRULE:FREQ=WEEKLY":             "weekly",
		"RRULE:FREQ=DAILY;WKST=MO":      "daily",
		"RRULE:FREQ=WEEKLY;BYDAY=MO":    "custom",
		"RRULE:FREQ=HOURLY":             "custom",
		"RDATE:20261001T100000Z":        "custom",
		"SUMMARY:once":                  "none",
		"RRULE:FREQ=MONTHLY;INTERVAL=2": "custom",
	}
	for line, want := range cases {
		c, err := Parse(cal(ev("UID:a\nDTSTART:20261001T100000Z\n" + line)))
		if err != nil {
			t.Fatal(err)
		}
		if got := repeatOf(c.Walk("VEVENT")[0]); got != want {
			t.Errorf("%s: %s, want %s", line, got, want)
		}
	}
}
