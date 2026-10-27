package ical

import (
	"cmp"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/teambition/rrule-go"
)

// Occurrence is one occurrence of an event, as events.json holds it for
// the shell (CalendarEvents reads it): times in epoch ms, an all-day
// one's at local midnight, its days in DayStart / DayEnd (end exclusive).
type Occurrence struct {
	Key      string `json:"key"`
	Calendar string `json:"calendar"` // "<account>|<calendar href>"
	Href     string `json:"href"`
	Etag     string `json:"etag"`
	UID      string `json:"uid"`
	// The original start of a series' occurrence: "D:YYYY-MM-DD" or
	// "T:<epoch s>" ("" outside a series)
	Rid       string `json:"rid"`
	Recurring bool   `json:"recurring"`
	// none, daily, weekly, monthly, yearly or custom
	Repeat      string  `json:"repeat"`
	AllDay      bool    `json:"allDay"`
	Start       int64   `json:"start"`
	End         int64   `json:"end"`
	DayStart    string  `json:"dayStart"`
	DayEnd      string  `json:"dayEnd"`
	Title       string  `json:"title"`
	Location    string  `json:"location"`
	Description string  `json:"description"`
	Alarms      []int64 `json:"alarms"`
	// Minutes before the start of its first alarm relative to the start
	// (-1 for none)
	Reminder int `json:"reminder"`
}

var freqs = map[string]string{"DAILY": "daily", "WEEKLY": "weekly", "MONTHLY": "monthly", "YEARLY": "yearly"}

const day = 24 * time.Hour

// Expand is the occurrences of an object's VEVENTs overlapping
// [from, to) (epoch ms), in order of start.
func (z Zones) Expand(cal *Component, calendar, href, etag string, from, to int64) ([]Occurrence, error) {
	z = z.With(cal)
	occurrences, err := z.occurrences(cal, from, to)
	if err != nil {
		return nil, err
	}
	masters := map[string]*Component{}
	for _, ev := range cal.Walk("VEVENT") {
		if uid := ev.Text("UID"); ev.Get("RECURRENCE-ID") == nil && masters[uid] == nil {
			masters[uid] = ev
		}
	}
	out := make([]Occurrence, 0, len(occurrences))
	for _, o := range occurrences {
		uid := o.ev.Text("UID")
		start, end := o.start.UnixMilli(), o.end.UnixMilli()
		occ := Occurrence{
			Calendar: calendar, Href: href, Etag: etag, UID: uid,
			Recurring: o.rid != nil, Repeat: "none", AllDay: o.start.Date,
			Start: start, End: max(end, start),
			Title: o.ev.Text("SUMMARY"), Location: o.ev.Text("LOCATION"), Description: o.ev.Text("DESCRIPTION"),
			Alarms: z.alarms(o.ev, start, end), Reminder: reminder(o.ev),
		}
		if o.rid != nil {
			occ.Rid = ridOf(*o.rid)
			occ.Repeat = repeatOf(masters[uid])
		}
		if occ.AllDay {
			last := o.end
			if o.end.UnixMilli() <= start {
				last = z.add(o.start, day)
			}
			occ.DayStart, occ.DayEnd = iso(z.dayOf(o.start)), iso(z.dayOf(last))
		}
		occ.Key = calendar + "|" + uid + "|" + occ.Rid
		out = append(out, occ)
	}
	return out, nil
}

type occurrence struct {
	ev         *Component
	start, end When
	rid        *When // the original start, nil outside a series
}

// occurrences: a series expanded from its RRULEs, RDATEs and DTSTART, less
// its EXDATEs, with its RECURRENCE-ID overrides in place of the
// occurrences they replace. A THISANDFUTURE override applies only to its
// own occurrence.
func (z Zones) occurrences(cal *Component, from, to int64) ([]occurrence, error) {
	overlaps := func(s, e When) bool {
		a, b := s.UnixMilli(), e.UnixMilli()
		return a < to && (b > from || (a == b && a >= from))
	}
	var uids, overridden []string
	masters, overrides := map[string]*Component{}, map[string][]*Component{}
	for _, ev := range cal.Walk("VEVENT") {
		if ev.Get("DTSTART") == nil {
			continue
		}
		uid := ev.Text("UID")
		if ev.Get("RECURRENCE-ID") == nil {
			if masters[uid] == nil {
				masters[uid] = ev
				uids = append(uids, uid)
			}
		} else {
			if overrides[uid] == nil {
				overridden = append(overridden, uid)
			}
			overrides[uid] = append(overrides[uid], ev)
		}
	}
	var out []occurrence
	for _, uid := range uids {
		master := masters[uid]
		first, err := z.Prop(master.Get("DTSTART"))
		if err != nil {
			return nil, err
		}
		end, err := z.endOf(master, first)
		if err != nil {
			return nil, err
		}
		length, err := z.sub(end, first)
		if err != nil {
			return nil, err
		}
		if master.Get("RRULE") == nil && master.Get("RDATE") == nil && overrides[uid] == nil {
			if overlaps(first, z.add(first, length)) {
				out = append(out, occurrence{ev: master, start: first, end: z.add(first, length)})
			}
			continue
		}
		type slot struct {
			start When
			span  time.Duration
		}
		var keys []int64
		starts := map[int64]slot{}
		put := func(s When, span time.Duration, replace bool) {
			k := s.UnixMilli()
			if _, ok := starts[k]; !ok {
				keys = append(keys, k)
			} else if !replace {
				return
			}
			starts[k] = slot{s, span}
		}
		put(first, length, false)
		// Expanded at midnight for an all-day series; back to dates after
		base := first
		if first.Date {
			base = When{Time: first.Time, Floating: true}
		}
		rules, err := z.rules(master, base)
		if err != nil {
			return nil, err
		}
		lo := z.add(When{Time: time.UnixMilli(from).In(base.Location())}, -length).Time
		hi := time.UnixMilli(to).In(base.Location())
		for _, rule := range rules {
			for _, t := range rule.Between(lo, hi, true) {
				s := When{Time: t, Floating: base.Floating, TZID: base.TZID}
				if first.Date {
					s = z.dayOf(s)
				}
				put(s, length, false)
			}
		}
		for _, p := range master.All("RDATE") {
			periods, err := z.List(p)
			if err != nil {
				return nil, err
			}
			for _, period := range periods {
				s := z.frame(period.Start, first)
				switch {
				case period.HasLength:
					put(s, period.Length, true)
				case period.End != nil:
					span, err := z.sub(z.frame(*period.End, first), s)
					if err != nil {
						return nil, err
					}
					put(s, span, true)
				default:
					put(s, length, false)
				}
			}
		}
		excluded := map[int64]bool{}
		for _, p := range master.All("EXDATE") {
			periods, err := z.List(p)
			if err != nil {
				return nil, err
			}
			for _, period := range periods {
				k := z.frame(period.Start, first).UnixMilli()
				excluded[k] = true
				delete(starts, k)
			}
		}
		for _, ev := range overrides[uid] {
			recurrence, err := z.Prop(ev.Get("RECURRENCE-ID"))
			if err != nil {
				return nil, err
			}
			rid := z.frame(recurrence, first)
			delete(starts, rid.UnixMilli())
			s, e, err := z.span(ev)
			if err != nil {
				return nil, err
			}
			if !excluded[rid.UnixMilli()] && overlaps(s, e) {
				out = append(out, occurrence{ev: ev, start: s, end: e, rid: &rid})
			}
		}
		delete(overrides, uid)
		for _, k := range keys {
			if slot, ok := starts[k]; ok && overlaps(slot.start, z.add(slot.start, slot.span)) {
				s := slot.start
				out = append(out, occurrence{ev: master, start: s, end: z.add(s, slot.span), rid: &s})
			}
		}
	}
	// Overrides of a series this object doesn't hold
	for _, uid := range overridden {
		for _, ev := range overrides[uid] {
			s, e, err := z.span(ev)
			if err != nil {
				return nil, err
			}
			if !overlaps(s, e) {
				continue
			}
			rid, err := z.Prop(ev.Get("RECURRENCE-ID"))
			if err != nil {
				return nil, err
			}
			out = append(out, occurrence{ev: ev, start: s, end: e, rid: &rid})
		}
	}
	slices.SortStableFunc(out, func(a, b occurrence) int { return cmp.Compare(a.start.UnixMilli(), b.start.UnixMilli()) })
	return out, nil
}

// span is a component's start and end
func (z Zones) span(ev *Component) (When, When, error) {
	s, err := z.Prop(ev.Get("DTSTART"))
	if err != nil {
		return When{}, When{}, err
	}
	e, err := z.endOf(ev, s)
	return s, e, err
}

// endOf is DTEND, else the start plus DURATION, else a day after an
// all-day start (a timed one ends as it starts)
func (z Zones) endOf(ev *Component, start When) (When, error) {
	if p := ev.Get("DTEND"); p != nil {
		return z.Prop(p)
	}
	if p := ev.Get("DURATION"); p != nil {
		d, err := ParseDuration(p.Value)
		if err != nil {
			return When{}, err
		}
		return z.add(start, d), nil
	}
	if start.Date {
		return z.add(start, day), nil
	}
	return start, nil
}

// rules are the master's RRULEs starting at base. UNTIL is put in base's
// form first, and a UTC UNTIL on a floating start (invalid, but sent) is
// read as wall time.
func (z Zones) rules(master *Component, base When) ([]*rrule.RRule, error) {
	var out []*rrule.RRule
	for _, p := range master.All("RRULE") {
		var kept []string
		until := ""
		for part := range strings.SplitSeq(p.Value, ";") {
			if value, ok := strings.CutPrefix(strings.ToUpper(part), "UNTIL="); ok {
				until = value
			} else if part != "" {
				kept = append(kept, part)
			}
		}
		option, err := rrule.StrToROption(strings.Join(kept, ";"))
		if err != nil {
			return nil, fmt.Errorf("RRULE %q: %w", p.Value, err)
		}
		option.Dtstart = base.Time
		if until != "" {
			u, err := z.When(until, "", false)
			if err != nil {
				return nil, err
			}
			if !u.Date && base.Floating {
				u = When{Time: wall(u.Time, z.Local), Floating: true}
			}
			option.Until = z.frame(u, base).Time
		}
		rule, err := rrule.NewRRule(*option)
		if err != nil {
			return nil, fmt.Errorf("RRULE %q: %w", p.Value, err)
		}
		out = append(out, rule)
	}
	return out, nil
}

// frame is v (an UNTIL, RDATE, EXDATE or RECURRENCE-ID) in the form of
// the series' start like: a date for an all-day series, else a time in
// like's zone (floating when like is)
func (z Zones) frame(v, like When) When {
	if like.Date {
		return z.dayOf(v)
	}
	if v.Date {
		v = When{Time: v.Time, Floating: true}
	}
	switch {
	case like.Floating && !v.Floating:
		return When{Time: v.In(z.Local), Floating: true}
	case like.Floating:
		return v
	case v.Floating:
		return When{Time: wall(v.Time, like.Location()), TZID: like.TZID}
	default:
		return When{Time: v.In(like.Location()), TZID: like.TZID}
	}
}

// dayOf is the local date of v
func (z Zones) dayOf(v When) When {
	t := v.Time
	if !v.Date && !v.Floating {
		t = t.In(z.Local)
	}
	return z.Day(t.Year(), t.Month(), t.Day())
}

// add is v moved by d on its wall clock (whole days for a date)
func (z Zones) add(v When, d time.Duration) When {
	t := v.Time
	if v.Date {
		days := int(math.Floor(float64(d) / float64(day)))
		return z.Day(t.Year(), t.Month(), t.Day()+days)
	}
	v.Time = time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second()+int(d/time.Second), t.Nanosecond(), t.Location())
	return v
}

// sub is a - b: by the wall clock in one zone, else in real time
func (z Zones) sub(a, b When) (time.Duration, error) {
	if a.Date != b.Date {
		return 0, fmt.Errorf("a date and a time can't be compared")
	}
	if a.Date || a.Location().String() == b.Location().String() {
		return wall(a.Time, time.UTC).Sub(wall(b.Time, time.UTC)), nil
	}
	return a.Sub(b.Time), nil
}

// wall is t's wall clock read in loc
func wall(t time.Time, loc *time.Location) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), loc)
}

func iso(v When) string { return v.Format("2006-01-02") }

func ridOf(v When) string {
	if v.Date {
		return "D:" + iso(v)
	}
	return fmt.Sprintf("T:%d", v.Unix())
}

// repeatOf names a plain FREQ rule; any other rule, or RDATEs, is custom
func repeatOf(master *Component) string {
	if master == nil {
		return "none"
	}
	p := master.Get("RRULE")
	if p == nil {
		if master.Get("RDATE") != nil {
			return "custom"
		}
		return "none"
	}
	freq, plain := "", true
	for part := range strings.SplitSeq(strings.ToUpper(p.Value), ";") {
		key, value, _ := strings.Cut(part, "=")
		switch key {
		case "FREQ":
			freq = value
		case "WKST", "":
		default:
			plain = false
		}
	}
	if name, ok := freqs[freq]; ok && plain {
		return name
	}
	return "custom"
}

// trigger is an alarm's TRIGGER: a duration (relative to the start, or
// the end with RELATED=END), or an absolute time; ok false without one
func (z Zones) trigger(alarm *Component) (d time.Duration, at *When, end bool, ok bool) {
	p := alarm.Get("TRIGGER")
	if p == nil || strings.ToUpper(alarm.Text("ACTION")) == "NONE" {
		return 0, nil, false, false
	}
	value := strings.TrimLeft(p.Value, "+-")
	if strings.HasPrefix(strings.ToUpper(value), "P") {
		d, err := ParseDuration(p.Value)
		return d, nil, p.Param("RELATED") == "END", err == nil
	}
	w, err := z.Prop(p)
	if err != nil || w.Date {
		return 0, nil, false, false
	}
	return 0, &w, false, true
}

// reminder is how many minutes before the start the first alarm relative
// to the start rings (-1 for none)
func reminder(ev *Component) int {
	for _, alarm := range ev.Walk("VALARM") {
		d, at, end, ok := (Zones{Local: time.UTC}).trigger(alarm)
		if ok && at == nil && !end {
			return max(0, int(math.Floor(-d.Seconds()/60)))
		}
	}
	return -1
}

// alarms are when an occurrence's alarms ring (epoch ms, sorted, once each)
func (z Zones) alarms(ev *Component, start, end int64) []int64 {
	out := []int64{}
	for _, alarm := range ev.Walk("VALARM") {
		d, at, fromEnd, ok := z.trigger(alarm)
		switch {
		case !ok:
			continue
		case at != nil:
			out = append(out, at.UnixMilli())
		case fromEnd:
			out = append(out, end+d.Milliseconds())
		default:
			out = append(out, start+d.Milliseconds())
		}
	}
	slices.Sort(out)
	return slices.Compact(out)
}
