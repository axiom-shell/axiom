package ical

import (
	"errors"
	"strconv"
	"strings"
	"time"
)

// Event is an edited event as the shell sends it
// (CalendarEvents.payloadOf): times in epoch ms, an all-day one's days as
// "YYYY-MM-DD" (DayEnd exclusive).
type Event struct {
	Title       string `json:"title"`
	Location    string `json:"location"`
	Description string `json:"description"`
	AllDay      bool   `json:"allDay"`
	Start       int64  `json:"start"`
	End         int64  `json:"end"`
	DayStart    string `json:"dayStart"`
	DayEnd      string `json:"dayEnd"`
	// none, daily, weekly, monthly, yearly or custom
	Repeat        string `json:"repeat"`
	RepeatChanged bool   `json:"repeatChanged"`
	// Minutes before the start (-1 or absent: none)
	Reminder        *int `json:"reminder"`
	ReminderChanged bool `json:"reminderChanged"`
	// Where the edited occurrence started before the edit (absent for a
	// new event)
	OrigStart *int64 `json:"origStart"`
}

// Zone is where new times are written: the local zone and its TZID ("" to
// write UTC).
type Zone struct {
	Loc  *time.Location
	Name string
}

// ErrNoMaster is an object with no event that isn't an override.
var ErrNoMaster = errors.New("the event has no main entry")

var plainRepeats = map[string]bool{"daily": true, "weekly": true, "monthly": true, "yearly": true}

func (e Event) reminder() int {
	if e.Reminder == nil {
		return -1
	}
	return *e.Reminder
}

// at is ms in the zone new times are written in
func (tz Zone) at(ms int64) When {
	if tz.Name == "" {
		return When{Time: time.UnixMilli(ms).UTC()}
	}
	return When{Time: time.UnixMilli(ms).In(tz.Loc), TZID: tz.Name}
}

func (z Zones) date(iso string) When {
	t, err := time.ParseInLocation("2006-01-02", iso, z.Local)
	if err != nil {
		t = time.Unix(0, 0).In(z.Local)
	}
	return When{Time: t, Date: true}
}

func (z Zones) setTimes(c *Component, e Event, tz Zone) {
	var start, end When
	if e.AllDay {
		start = z.date(e.DayStart)
		end = z.add(start, day)
		if e.DayEnd != "" {
			end = z.date(e.DayEnd)
		}
		if !end.After(start.Time) {
			end = z.add(start, day)
		}
	} else {
		start, end = tz.at(e.Start), tz.at(max(e.End, e.Start))
	}
	c.Remove("DURATION")
	c.SetWhen("DTSTART", start)
	c.SetWhen("DTEND", end)
}

func setText(c *Component, e Event) {
	c.SetText("SUMMARY", e.Title)
	c.SetText("LOCATION", e.Location)
	c.SetText("DESCRIPTION", e.Description)
}

func setReminder(c *Component, minutes int, title string) {
	var kept []*Component
	for _, child := range c.Children {
		if child.Name != "VALARM" {
			kept = append(kept, child)
		}
	}
	c.Children = kept
	if minutes >= 0 {
		if title == "" {
			title = "Reminder"
		}
		alarm := &Component{Name: "VALARM"}
		alarm.Add("ACTION", "DISPLAY")
		alarm.SetText("DESCRIPTION", title)
		alarm.Add("TRIGGER", FormatDuration(-time.Duration(minutes)*time.Minute))
		c.Children = append(c.Children, alarm)
	}
}

func touch(c *Component, now time.Time) {
	stamp := now.UTC().Format("20060102T150405Z")
	c.Set("DTSTAMP", stamp)
	c.Set("LAST-MODIFIED", stamp)
	if p := c.Get("SEQUENCE"); p != nil {
		n, _ := strconv.Atoi(strings.TrimSpace(p.Value))
		p.Value = strconv.Itoa(n + 1)
	} else {
		c.Add("SEQUENCE", "1")
	}
}

// ridValue is the RECURRENCE-ID / EXDATE for rid, typed like the
// master's start
func (z Zones) ridValue(rid string, like When, tz Zone) When {
	kind, raw, _ := strings.Cut(rid, ":")
	if kind == "D" {
		return z.date(raw)
	}
	secs, _ := strconv.ParseInt(raw, 10, 64)
	moment := time.Unix(secs, 0)
	switch {
	case like.Date:
		return z.dayOf(When{Time: moment.In(tz.Loc)})
	case like.Floating:
		return When{Time: moment.In(z.Local), Floating: true}
	default:
		return When{Time: moment.In(like.Location()), TZID: like.TZID}
	}
}

func (z Zones) sameRid(c *Component, rid string) bool {
	p := c.Get("RECURRENCE-ID")
	if p == nil {
		return false
	}
	w, err := z.Prop(p)
	return err == nil && ridOf(w) == rid
}

func master(cal *Component) *Component {
	for _, ev := range cal.Walk("VEVENT") {
		if ev.Get("RECURRENCE-ID") == nil {
			return ev
		}
	}
	return nil
}

// dropOverrides removes the calendar's RECURRENCE-ID events
func dropOverrides(cal *Component) {
	var kept []*Component
	for _, c := range cal.Children {
		if c.Name != "VEVENT" || c.Get("RECURRENCE-ID") == nil {
			kept = append(kept, c)
		}
	}
	cal.Children = kept
}

// shiftSeries moves a recurring series by how far its edited occurrence
// moved, along with its overrides' RECURRENCE-IDs and its EXDATEs, so
// they keep matching
func (z Zones) shiftSeries(cal, m *Component, e Event, tz Zone) error {
	oldStart, err := z.Prop(m.Get("DTSTART"))
	if err != nil {
		return err
	}
	var newStart, newEnd When
	var delta time.Duration
	if e.AllDay {
		origDay := z.date(e.DayStart)
		if e.OrigStart != nil {
			origDay = z.dayOf(When{Time: time.UnixMilli(*e.OrigStart).In(z.Local), Floating: true})
		}
		delta, _ = z.sub(z.date(e.DayStart), origDay)
		length := day
		if e.DayEnd != "" {
			length, _ = z.sub(z.date(e.DayEnd), z.date(e.DayStart))
		}
		baseDay := oldStart
		if !oldStart.Date {
			baseDay = z.Day(oldStart.Year(), oldStart.Month(), oldStart.Day())
		}
		newStart = z.add(baseDay, delta)
		newEnd = z.add(newStart, max(length, day))
	} else {
		newLocal := tz.at(e.Start)
		length := time.Duration(max(0, e.End-e.Start)) * time.Millisecond
		if oldStart.Date {
			newStart = newLocal
			newStart.Time = time.Date(oldStart.Year(), oldStart.Month(), oldStart.Day(), newLocal.Hour(), newLocal.Minute(), newLocal.Second(), 0, newLocal.Location())
		} else {
			orig := e.Start
			if e.OrigStart != nil {
				orig = *e.OrigStart
			}
			delta = wall(newLocal.Time, time.UTC).Sub(wall(tz.at(orig).Time, time.UTC))
			newStart = z.add(oldStart, delta)
		}
		newEnd = z.add(newStart, length)
	}
	m.Remove("DURATION")
	m.SetWhen("DTSTART", newStart)
	m.SetWhen("DTEND", newEnd)
	switch {
	case oldStart.Date != e.AllDay:
		// A series turned all-day (or back): old overrides and exceptions
		// no longer name occurrences
		m.Remove("EXDATE")
		dropOverrides(cal)
	case delta != 0:
		for _, ev := range cal.Walk("VEVENT") {
			if p := ev.Get("RECURRENCE-ID"); ev != m && p != nil {
				if w, err := z.Prop(p); err == nil {
					p.Value, _ = z.add(w, delta).Value()
				}
			}
		}
		for i := range m.Props {
			if p := &m.Props[i]; p.Name == "EXDATE" {
				periods, err := z.List(*p)
				if err != nil {
					continue
				}
				values := make([]string, len(periods))
				for j, period := range periods {
					values[j], _ = z.add(period.Start, delta).Value()
				}
				p.Value = strings.Join(values, ",")
			}
		}
	}
	return nil
}

// NewEvent is a calendar holding one new event (uid its UID), in tz.
func (z Zones) NewEvent(e Event, tz Zone, uid string, now time.Time) *Component {
	cal := &Component{Name: "VCALENDAR"}
	cal.Add("PRODID", "-//axiom//calendar//EN")
	cal.Add("VERSION", "2.0")
	ev := &Component{Name: "VEVENT"}
	ev.Add("UID", uid)
	setText(ev, e)
	z.setTimes(ev, e, tz)
	if plainRepeats[e.Repeat] {
		ev.Add("RRULE", "FREQ="+strings.ToUpper(e.Repeat))
	}
	setReminder(ev, e.reminder(), e.Title)
	touch(ev, now)
	cal.Children = append(cal.Children, ev)
	return cal
}

// ApplySeries edits the whole event (a recurring one moved by how far
// the edited occurrence moved).
func (z Zones) ApplySeries(cal *Component, e Event, tz Zone, now time.Time) error {
	z = z.With(cal)
	m := master(cal)
	if m == nil {
		return ErrNoMaster
	}
	recurring := m.Get("RRULE") != nil || m.Get("RDATE") != nil
	setText(m, e)
	if recurring && e.Repeat != "none" {
		if err := z.shiftSeries(cal, m, e, tz); err != nil {
			return err
		}
	} else {
		z.setTimes(m, e, tz)
	}
	if e.RepeatChanged {
		m.Remove("RRULE")
		if plainRepeats[e.Repeat] {
			m.Add("RRULE", "FREQ="+strings.ToUpper(e.Repeat))
		} else {
			m.Remove("RDATE")
			m.Remove("EXDATE")
			dropOverrides(cal)
		}
	}
	if e.ReminderChanged {
		setReminder(m, e.reminder(), e.Title)
	}
	touch(m, now)
	return nil
}

// ApplyOccurrence edits the occurrence at rid only: its RECURRENCE-ID
// override, made from the master when there's none.
func (z Zones) ApplyOccurrence(cal *Component, e Event, rid string, tz Zone, now time.Time) error {
	z = z.With(cal)
	m := master(cal)
	var override *Component
	for _, ev := range cal.Walk("VEVENT") {
		if z.sameRid(ev, rid) {
			override = ev
			break
		}
	}
	if override == nil {
		if m == nil {
			return ErrNoMaster
		}
		start, err := z.Prop(m.Get("DTSTART"))
		if err != nil {
			return err
		}
		copied := m.Clone()
		override = &Component{Name: "VEVENT", Children: copied.Children}
		for _, p := range copied.Props {
			switch p.Name {
			case "RRULE", "RDATE", "EXDATE", "RECURRENCE-ID", "DTSTART", "DTEND", "DURATION":
			default:
				override.Props = append(override.Props, p)
			}
		}
		override.AddWhen("RECURRENCE-ID", z.ridValue(rid, start, tz))
		cal.Children = append(cal.Children, override)
	}
	setText(override, e)
	z.setTimes(override, e, tz)
	if e.ReminderChanged {
		setReminder(override, e.reminder(), e.Title)
	}
	touch(override, now)
	return nil
}

// ExcludeOccurrence drops the occurrence at rid (an EXDATE, its override
// removed); false when no event is left.
func (z Zones) ExcludeOccurrence(cal *Component, rid string, tz Zone, now time.Time) bool {
	z = z.With(cal)
	m := master(cal)
	var kept []*Component
	for _, c := range cal.Children {
		if c.Name != "VEVENT" || !z.sameRid(c, rid) {
			kept = append(kept, c)
		}
	}
	cal.Children = kept
	if m != nil {
		if start, err := z.Prop(m.Get("DTSTART")); err == nil {
			m.AddWhen("EXDATE", z.ridValue(rid, start, tz))
		}
		touch(m, now)
		return true
	}
	return len(cal.Walk("VEVENT")) > 0
}
