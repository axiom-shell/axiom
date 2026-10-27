package ical

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"
)

var now = time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)

// readBack is what the sync would show of cal: written, read and expanded
func readBack(t *testing.T, cal *Component) []Occurrence {
	t.Helper()
	parsed, err := Parse(cal.Encode())
	if err != nil {
		t.Fatal(err)
	}
	out, err := zones.Expand(parsed, "a|cal", "h", "", ms(2026, 7, 1), ms(2026, 8, 1))
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func rid(y int, m time.Month, d, h int) string { return fmt.Sprintf("T:%d", ms(y, m, d, h)/1000) }

func ptr[T any](v T) *T { return &v }

// New events, a moved occurrence, an excluded one and a shifted series,
// read back through the same expansion the sync uses
func TestEdits(t *testing.T) {
	t.Parallel()
	utc := Zone{Loc: time.UTC}
	type row struct {
		title    string
		start    int64
		rid      string
		repeat   string
		reminder int
	}
	rows := func(cal *Component) []row {
		var out []row
		for _, o := range readBack(t, cal) {
			out = append(out, row{o.Title, o.Start, o.Rid, o.Repeat, o.Reminder})
		}
		return out
	}
	cal := zones.NewEvent(Event{Title: "Gym", Start: ms(2026, 7, 6, 18), End: ms(2026, 7, 6, 19), Repeat: "weekly", Reminder: ptr(30)}, utc, "uid-1", now)
	var want []row
	for _, d := range []int{6, 13, 20, 27} {
		want = append(want, row{"Gym", ms(2026, 7, d, 18), rid(2026, 7, d, 18), "weekly", 30})
	}
	if got := rows(cal); !reflect.DeepEqual(got, want) {
		t.Fatalf("new %v\nwant %v", got, want)
	}

	// The 13th moved to 20:00 under its own title, the 20th gone
	if err := zones.ApplyOccurrence(cal, Event{Title: "Gym (late)", Start: ms(2026, 7, 13, 20), End: ms(2026, 7, 13, 21)}, rid(2026, 7, 13, 18), utc, now); err != nil {
		t.Fatal(err)
	}
	if !zones.ExcludeOccurrence(cal, rid(2026, 7, 20, 18), utc, now) {
		t.Fatal("nothing left")
	}
	want = []row{{"Gym", ms(2026, 7, 6, 18), rid(2026, 7, 6, 18), "weekly", 30},
		{"Gym (late)", ms(2026, 7, 13, 20), rid(2026, 7, 13, 18), "weekly", 30},
		{"Gym", ms(2026, 7, 27, 18), rid(2026, 7, 27, 18), "weekly", 30}}
	if got := rows(cal); !reflect.DeepEqual(got, want) {
		t.Fatalf("occurrence %v\nwant %v", got, want)
	}

	// An hour earlier: the override and the exclusion move with the series
	err := zones.ApplySeries(cal, Event{Title: "Gym", Start: ms(2026, 7, 6, 17), End: ms(2026, 7, 6, 18), OrigStart: ptr(ms(2026, 7, 6, 18)), Repeat: "weekly", Reminder: ptr(30)}, utc, now)
	if err != nil {
		t.Fatal(err)
	}
	want = []row{{"Gym", ms(2026, 7, 6, 17), rid(2026, 7, 6, 17), "weekly", 30},
		{"Gym (late)", ms(2026, 7, 13, 20), rid(2026, 7, 13, 17), "weekly", 30},
		{"Gym", ms(2026, 7, 27, 17), rid(2026, 7, 27, 17), "weekly", 30}}
	if got := rows(cal); !reflect.DeepEqual(got, want) {
		t.Fatalf("shifted %v\nwant %v", got, want)
	}

	// No longer repeating: one event, no reminder, overrides dropped
	err = zones.ApplySeries(cal, Event{Title: "Gym once", Start: ms(2026, 7, 6, 17), End: ms(2026, 7, 6, 18), OrigStart: ptr(ms(2026, 7, 6, 17)),
		Repeat: "none", RepeatChanged: true, Reminder: ptr(-1), ReminderChanged: true}, utc, now)
	if err != nil {
		t.Fatal(err)
	}
	if got := rows(cal); !reflect.DeepEqual(got, []row{{"Gym once", ms(2026, 7, 6, 17), "", "none", -1}}) {
		t.Fatalf("single %v", got)
	}
	if !strings.Contains(cal.Encode(), "SEQUENCE:4\r\n") {
		t.Errorf("each edit counts in SEQUENCE:\n%s", cal.Encode())
	}

	holiday := readBack(t, zones.NewEvent(Event{Title: "Holiday", AllDay: true, DayStart: "2026-07-20", DayEnd: "2026-07-22", Repeat: "none"}, utc, "uid-2", now))
	if len(holiday) != 1 || holiday[0].DayStart != "2026-07-20" || holiday[0].DayEnd != "2026-07-22" || holiday[0].Reminder != -1 {
		t.Errorf("all-day %+v", holiday)
	}
	if zones.ApplySeries(&Component{Name: "VCALENDAR"}, Event{}, utc, now) != ErrNoMaster {
		t.Error("an object with no event was edited")
	}
}

// A new event in a named zone keeps its wall time across a DST change,
// and carries the zone's VTIMEZONE
func TestNewEventInZone(t *testing.T) {
	t.Parallel()
	berlin, _ := time.LoadLocation("Europe/Berlin")
	cal := zones.NewEvent(Event{Title: "Standup", Start: ms(2026, 10, 20, 7), End: ms(2026, 10, 20, 8), Repeat: "weekly"}, Zone{Loc: berlin, Name: "Europe/Berlin"}, "u", now)
	zones.AddMissingTimezones(cal)
	text := cal.Encode()
	if !strings.Contains(text, "DTSTART;TZID=Europe/Berlin:20261020T090000\r\n") || cal.Children[0].Name != "VTIMEZONE" {
		t.Fatalf("written:\n%s", text)
	}
	if got := expand(t, text, ms(2026, 10, 1), ms(2026, 11, 1)); len(got) != 2 || got[1].Start != ms(2026, 10, 27, 8) {
		t.Errorf("read back %+v", got)
	}
}

// A TZID the zone database doesn't know is read from the calendar's own
// VTIMEZONE (Outlook's Windows names); one generated from a zone reads
// back as that zone
func TestCustomZones(t *testing.T) {
	t.Parallel()
	windows := "BEGIN:VTIMEZONE\r\nTZID:W. Europe Standard Time\r\n" +
		"BEGIN:STANDARD\r\nDTSTART:16010101T030000\r\nTZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\nRRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10\r\nEND:STANDARD\r\n" +
		"BEGIN:DAYLIGHT\r\nDTSTART:16010101T020000\r\nTZOFFSETFROM:+0100\r\nTZOFFSETTO:+0200\r\nRRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3\r\nEND:DAYLIGHT\r\nEND:VTIMEZONE\r\n"
	events := expand(t, cal(windows, ev("UID:a\nDTSTART;TZID=W. Europe Standard Time:20261020T090000\nDURATION:PT1H\nRRULE:FREQ=WEEKLY")), ms(2026, 10, 1), ms(2026, 11, 1))
	if len(events) != 2 || events[0].Start != ms(2026, 10, 20, 7) || events[1].Start != ms(2026, 10, 27, 8) {
		t.Errorf("windows zone %+v", events)
	}
	// A rule ending at a UTC UNTIL keeps its last onset (east of UTC, the
	// UNTIL read as wall time would fall before it)
	ending, _ := Parse("BEGIN:VCALENDAR\r\nBEGIN:VTIMEZONE\r\nTZID:Ending\r\n" +
		"BEGIN:STANDARD\r\nDTSTART:19961027T030000\r\nTZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\nRRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10\r\nEND:STANDARD\r\n" +
		"BEGIN:DAYLIGHT\r\nDTSTART:19810329T020000\r\nTZOFFSETFROM:+0100\r\nTZOFFSETTO:+0200\r\nRRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3;UNTIL=20250330T010000Z\r\nEND:DAYLIGHT\r\n" +
		"END:VTIMEZONE\r\nEND:VCALENDAR\r\n")
	if built := fromVTimezone("ending", ending.Walk("VTIMEZONE")[0]); built == nil {
		t.Error("no zone from a rule with UNTIL")
	} else if _, got := time.Date(2025, 7, 15, 12, 0, 0, 0, time.UTC).In(built).Zone(); got != 7200 {
		t.Errorf("summer 2025 offset %d, want 7200", got)
	}
	for _, name := range []string{"Europe/Berlin", "America/New_York", "Asia/Kolkata", "UTC"} {
		loc, _ := time.LoadLocation(name)
		vtz := VTimezone(name, loc)
		built := fromVTimezone("custom", vtz)
		if built == nil {
			t.Fatalf("%s: no zone from\n%s", name, vtz.Encode())
		}
		for _, at := range []time.Time{time.Date(2026, 1, 15, 12, 0, 0, 0, time.UTC), time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC), time.Date(2026, 3, 29, 1, 30, 0, 0, time.UTC)} {
			_, want := at.In(loc).Zone()
			if _, got := at.In(built).Zone(); got != want {
				t.Errorf("%s at %v: offset %d, want %d", name, at, got, want)
			}
		}
	}
}
