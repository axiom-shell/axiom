package ical

import (
	"cmp"
	"encoding/binary"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

// With is z, a TZID it doesn't know (a Windows name, Outlook's) read from
// the calendar's own VTIMEZONE, as the Python icalendar library this
// replaces did.
func (z Zones) With(cal *Component) Zones {
	zones := map[string]*Component{}
	for _, tz := range cal.Walk("VTIMEZONE") {
		zones[tz.Text("TZID")] = tz
	}
	if len(zones) == 0 {
		return z
	}
	built := map[string]*time.Location{}
	lookup := z.Lookup
	z.Lookup = func(tzid string) *time.Location {
		if lookup != nil {
			if loc := lookup(tzid); loc != nil {
				return loc
			}
		}
		if loc, ok := built[tzid]; ok {
			return loc
		}
		var loc *time.Location
		if tz := zones[tzid]; tz != nil {
			loc = fromVTimezone(tzid, tz)
		}
		built[tzid] = loc
		return loc
	}
	return z
}

// fromVTimezone builds a location from a VTIMEZONE's onsets (each
// STANDARD's and DAYLIGHT's DTSTART, RDATEs and RRULE, from 1970 to
// 2100), nil when it has none
func fromVTimezone(name string, tz *Component) *time.Location {
	type change struct {
		at     int64
		offset int
		dst    bool
	}
	var changes []change
	first, last := time.Date(1970, 1, 1, 0, 0, 0, 0, time.UTC), time.Date(2100, 1, 1, 0, 0, 0, 0, time.UTC)
	for _, part := range tz.Children {
		from, okFrom := parseOffset(part.Text("TZOFFSETFROM"))
		to, okTo := parseOffset(part.Text("TZOFFSETTO"))
		if part.Name != "STANDARD" && part.Name != "DAYLIGHT" || !okFrom || !okTo {
			continue
		}
		// Onsets are local times in the offset before them
		local := Zones{Local: time.FixedZone("", from)}
		start, err := local.When(part.Text("DTSTART"), "", false)
		if err != nil {
			continue
		}
		onsets := []time.Time{start.Time}
		// rrule-go expands nothing from before 1678 (Outlook starts its
		// rules in 1601): the same yearly rule from 1970 is the same onsets
		if t := start.Time; t.Before(first) {
			start.Time = time.Date(first.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), 0, t.Location())
		}
		for _, p := range part.All("RDATE") {
			periods, _ := local.List(p)
			for _, period := range periods {
				onsets = append(onsets, period.Start.Time)
			}
		}
		if rules, err := local.rules(part, start); err == nil {
			for _, r := range rules {
				onsets = append(onsets, r.Between(first, last, true)...)
			}
		}
		for _, t := range onsets {
			changes = append(changes, change{t.Unix(), to, part.Name == "DAYLIGHT"})
		}
	}
	if len(changes) == 0 {
		return nil
	}
	slices.SortFunc(changes, func(a, b change) int { return cmp.Compare(a.at, b.at) })
	changes = slices.CompactFunc(changes, func(a, b change) bool { return a.at == b.at })
	// TZif version 2: an empty version 1 block, then the 64-bit data
	type kind struct {
		offset int
		dst    bool
	}
	var kinds []kind
	var times, indexes []byte
	for _, c := range changes {
		i := slices.Index(kinds, kind{c.offset, c.dst})
		if i < 0 {
			i = len(kinds)
			kinds = append(kinds, kind{c.offset, c.dst})
		}
		times = binary.BigEndian.AppendUint64(times, uint64(c.at))
		indexes = append(indexes, byte(i))
	}
	header := func(counts ...int) []byte {
		b := append([]byte("TZif2"), make([]byte, 15)...)
		for _, n := range counts { // isut, isstd, leap, time, type, char
			b = binary.BigEndian.AppendUint32(b, uint32(n))
		}
		return b
	}
	data := append(header(0, 0, 0, 0, 0, 0), header(0, 0, 0, len(changes), len(kinds), 1)...)
	data = append(append(data, times...), indexes...)
	for _, k := range kinds {
		data = binary.BigEndian.AppendUint32(data, uint32(int32(k.offset)))
		dst := byte(0)
		if k.dst {
			dst = 1
		}
		data = append(data, dst, 0)
	}
	data = append(data, 0, '\n', '\n')
	loc, err := time.LoadLocationFromTZData(name, data)
	if err != nil {
		return nil
	}
	return loc
}

// parseOffset reads ±HHMM[SS] as seconds east of UTC
func parseOffset(s string) (int, bool) {
	if len(s) != 5 && len(s) != 7 || (s[0] != '+' && s[0] != '-') {
		return 0, false
	}
	n := 0
	for i, unit := range []int{3600, 60, 1}[:(len(s)-1)/2] {
		v, err := strconv.Atoi(s[1+2*i : 3+2*i])
		if err != nil {
			return 0, false
		}
		n += v * unit
	}
	if s[0] == '-' {
		n = -n
	}
	return n, true
}

// VTimezone describes loc (named name) as a VTIMEZONE: each change of
// offset from 1970 to 2038, grouped by kind and offsets (a DTSTART and
// RDATEs), as the icalendar library's add_missing_timezones did.
func VTimezone(name string, loc *time.Location) *Component {
	tz := &Component{Name: "VTIMEZONE"}
	tz.Add("TZID", name)
	type key struct {
		dst      bool
		abbr     string
		from, to int
	}
	var order []key
	onsets := map[key][]string{}
	end := time.Date(2038, 1, 1, 0, 0, 0, 0, time.UTC)
	for t := time.Date(1970, 1, 1, 0, 0, 0, 0, time.UTC); t.Before(end); {
		_, next := t.In(loc).ZoneBounds()
		if next.IsZero() || !next.Before(end) {
			break
		}
		_, from := next.Add(-time.Second).In(loc).Zone()
		abbr, to := next.In(loc).Zone()
		k := key{next.In(loc).IsDST(), abbr, from, to}
		if onsets[k] == nil {
			order = append(order, k)
		}
		onsets[k] = append(onsets[k], next.In(time.FixedZone("", from)).Format("20060102T150405"))
		t = next
	}
	if len(order) == 0 {
		abbr, offset := time.Date(1970, 1, 1, 0, 0, 0, 0, loc).Zone()
		k := key{false, abbr, offset, offset}
		order, onsets[k] = []key{k}, []string{"19700101T000000"}
	}
	for _, k := range order {
		part := &Component{Name: "STANDARD"}
		if k.dst {
			part.Name = "DAYLIGHT"
		}
		part.Add("DTSTART", onsets[k][0])
		if len(onsets[k]) > 1 {
			part.Add("RDATE", strings.Join(onsets[k][1:], ","))
		}
		part.Add("TZNAME", k.abbr)
		part.Add("TZOFFSETFROM", formatOffset(k.from))
		part.Add("TZOFFSETTO", formatOffset(k.to))
		tz.Children = append(tz.Children, part)
	}
	return tz
}

func formatOffset(east int) string {
	sign := "+"
	if east < 0 {
		sign, east = "-", -east
	}
	out := fmt.Sprintf("%s%02d%02d", sign, east/3600, east/60%60)
	if east%60 != 0 {
		out += fmt.Sprintf("%02d", east%60)
	}
	return out
}

// AddMissingTimezones adds a VTIMEZONE for every TZID the calendar uses
// without one, when z knows the zone.
func (z Zones) AddMissingTimezones(cal *Component) {
	have := map[string]bool{}
	for _, tz := range cal.Walk("VTIMEZONE") {
		have[tz.Text("TZID")] = true
	}
	var added []*Component
	var walk func(c *Component)
	walk = func(c *Component) {
		for _, p := range c.Props {
			tzid := p.Param("TZID")
			if tzid == "" || have[tzid] || z.Lookup == nil {
				continue
			}
			have[tzid] = true
			if loc := z.Lookup(tzid); loc != nil {
				added = append(added, VTimezone(tzid, loc))
			}
		}
		for _, child := range c.Children {
			walk(child)
		}
	}
	walk(cal)
	cal.Children = append(added, cal.Children...)
}
