// Package ical is iCalendar (RFC 5545) for the calendars: content lines
// read into components and written back (unknown properties kept as
// they were), their dates, times, durations and periods, recurrences
// expanded into occurrences (expand.go), time zones (zone.go) and the
// edits saving an event makes (edit.go). Pure: zones come from a lookup
// the caller passes, so a test (or the daemon) decides where they're read
// from.
package ical

import (
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

// Param is a property parameter, its value unquoted.
type Param struct {
	Name, Value string
}

// Prop is one content line: NAME;PARAM=…:value (the value still escaped).
type Prop struct {
	Name   string
	Params []Param
	Value  string
}

// Param is the named parameter's value ("" when absent).
func (p Prop) Param(name string) string {
	for _, param := range p.Params {
		if param.Name == name {
			return param.Value
		}
	}
	return ""
}

// Text is a TEXT value unescaped.
func (p Prop) Text() string {
	if !strings.Contains(p.Value, `\`) {
		return p.Value
	}
	var b strings.Builder
	for i := 0; i < len(p.Value); i++ {
		c := p.Value[i]
		if c == '\\' && i+1 < len(p.Value) {
			i++
			switch p.Value[i] {
			case 'n', 'N':
				b.WriteByte('\n')
			default:
				b.WriteByte(p.Value[i])
			}
			continue
		}
		b.WriteByte(c)
	}
	return b.String()
}

// Component is BEGIN:NAME … END:NAME, with its properties in order.
type Component struct {
	Name     string
	Props    []Prop
	Children []*Component
}

// Get is the first property named name, nil without one.
func (c *Component) Get(name string) *Prop {
	for i := range c.Props {
		if c.Props[i].Name == name {
			return &c.Props[i]
		}
	}
	return nil
}

// All is every property named name.
func (c *Component) All(name string) []Prop {
	var out []Prop
	for _, p := range c.Props {
		if p.Name == name {
			out = append(out, p)
		}
	}
	return out
}

// Text is the first property named name as text ("" without one).
func (c *Component) Text(name string) string {
	if p := c.Get(name); p != nil {
		return p.Text()
	}
	return ""
}

// Walk is c and every component under it named name, depth first.
func (c *Component) Walk(name string) []*Component {
	var out []*Component
	if c.Name == name {
		out = append(out, c)
	}
	for _, child := range c.Children {
		out = append(out, child.Walk(name)...)
	}
	return out
}

// Remove drops every property named name.
func (c *Component) Remove(name string) {
	c.Props = slices.DeleteFunc(c.Props, func(p Prop) bool { return p.Name == name })
}

// Add appends a property.
func (c *Component) Add(name, value string, params ...Param) {
	c.Props = append(c.Props, Prop{Name: name, Params: params, Value: value})
}

// Set replaces every property named name with one (none for "").
func (c *Component) Set(name, value string, params ...Param) {
	c.Remove(name)
	if value != "" {
		c.Add(name, value, params...)
	}
}

// SetText is Set with a TEXT value, escaped.
func (c *Component) SetText(name, text string) {
	c.Set(name, strings.NewReplacer(`\`, `\\`, ";", `\;`, ",", `\,`, "\n", `\n`).Replace(text))
}

// Clone is a deep copy.
func (c *Component) Clone() *Component {
	out := &Component{Name: c.Name}
	for _, p := range c.Props {
		p.Params = append([]Param(nil), p.Params...)
		out.Props = append(out.Props, p)
	}
	for _, child := range c.Children {
		out.Children = append(out.Children, child.Clone())
	}
	return out
}

// Parse reads the first top-level component of text (normally a
// VCALENDAR). Lines are unfolded first; an unclosed component ends with
// the text.
func Parse(text string) (*Component, error) {
	text = strings.ReplaceAll(strings.ReplaceAll(text, "\r\n", "\n"), "\r", "\n")
	text = strings.NewReplacer("\n ", "", "\n\t", "").Replace(text)
	var root *Component
	var stack []*Component
	for n, line := range strings.Split(text, "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		prop, err := parseLine(line)
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", n+1, err)
		}
		switch prop.Name {
		case "BEGIN":
			c := &Component{Name: strings.ToUpper(strings.TrimSpace(prop.Value))}
			if len(stack) > 0 {
				top := stack[len(stack)-1]
				top.Children = append(top.Children, c)
			} else if root == nil {
				root = c
			} else {
				return root, nil
			}
			stack = append(stack, c)
		case "END":
			if len(stack) == 0 || stack[len(stack)-1].Name != strings.ToUpper(strings.TrimSpace(prop.Value)) {
				return nil, fmt.Errorf("line %d: END:%s without its BEGIN", n+1, prop.Value)
			}
			stack = stack[:len(stack)-1]
		default:
			if len(stack) == 0 {
				return nil, fmt.Errorf("line %d: %s outside a component", n+1, prop.Name)
			}
			top := stack[len(stack)-1]
			top.Props = append(top.Props, prop)
		}
	}
	if root == nil {
		return nil, errors.New("no BEGIN line")
	}
	return root, nil
}

// parseLine splits NAME *(;PARAM=VALUE[,VALUE]) : VALUE, quotes allowed
// around parameter values
func parseLine(line string) (Prop, error) {
	end := strings.IndexAny(line, ";:")
	if end <= 0 {
		return Prop{}, fmt.Errorf("not a content line: %q", line)
	}
	p := Prop{Name: strings.ToUpper(line[:end])}
	i := end
	for line[i] == ';' {
		eq := strings.IndexByte(line[i:], '=')
		if eq < 0 {
			return Prop{}, fmt.Errorf("parameter without a value: %q", line)
		}
		name := strings.ToUpper(line[i+1 : i+eq])
		i += eq + 1
		var value strings.Builder
		for i < len(line) && line[i] != ';' && line[i] != ':' {
			if line[i] == '"' {
				close := strings.IndexByte(line[i+1:], '"')
				if close < 0 {
					return Prop{}, fmt.Errorf("unclosed quote: %q", line)
				}
				value.WriteString(line[i+1 : i+1+close])
				i += close + 2
				continue
			}
			value.WriteByte(line[i])
			i++
		}
		p.Params = append(p.Params, Param{Name: name, Value: value.String()})
		if i >= len(line) {
			return Prop{}, fmt.Errorf("no value: %q", line)
		}
	}
	p.Value = line[i+1:]
	return p, nil
}

// Encode writes c as iCalendar text: CRLF lines folded at 75 octets.
func (c *Component) Encode() string {
	var b strings.Builder
	c.encode(&b)
	return b.String()
}

func (c *Component) encode(b *strings.Builder) {
	line(b, "BEGIN:"+c.Name)
	for _, p := range c.Props {
		var l strings.Builder
		l.WriteString(p.Name)
		for _, param := range p.Params {
			l.WriteString(";" + param.Name + "=")
			if strings.ContainsAny(param.Value, ":;,") {
				l.WriteString(`"` + param.Value + `"`)
			} else {
				l.WriteString(param.Value)
			}
		}
		l.WriteString(":" + p.Value)
		line(b, l.String())
	}
	for _, child := range c.Children {
		child.encode(b)
	}
	line(b, "END:"+c.Name)
}

// line writes one content line, folded without splitting a character
func line(b *strings.Builder, s string) {
	limit := 75
	for len(s) > limit {
		cut := limit
		for cut > 0 && s[cut]&0xC0 == 0x80 {
			cut--
		}
		b.WriteString(s[:cut] + "\r\n ")
		s, limit = s[cut:], 74
	}
	b.WriteString(s + "\r\n")
}

// When is a DATE (Date, at local midnight) or a DATE-TIME: in a zone
// (TZID, as written), in UTC, or floating (Floating, read as local time).
type When struct {
	time.Time
	Date     bool
	Floating bool
	TZID     string
}

// Zones turns a TZID into a location (nil when unknown: the time is then
// read as local), and says what local time is.
type Zones struct {
	Local  *time.Location
	Lookup func(tzid string) *time.Location
}

// Day is a date at local midnight.
func (z Zones) Day(year int, month time.Month, day int) When {
	return When{Time: time.Date(year, month, day, 0, 0, 0, 0, z.Local), Date: true}
}

// When reads one DATE or DATE-TIME value, tzid its zone ("" none).
func (z Zones) When(value, tzid string, date bool) (When, error) {
	value = strings.TrimSpace(value)
	if date || len(value) == 8 {
		t, err := time.ParseInLocation("20060102", value, z.Local)
		if err != nil {
			return When{}, fmt.Errorf("bad date %q", value)
		}
		return When{Time: t, Date: true}, nil
	}
	if utc, ok := strings.CutSuffix(value, "Z"); ok {
		t, err := time.ParseInLocation("20060102T150405", utc, time.UTC)
		if err != nil {
			return When{}, fmt.Errorf("bad time %q", value)
		}
		return When{Time: t}, nil
	}
	w := When{Floating: true}
	loc := z.Local
	if tzid != "" && z.Lookup != nil {
		if found := z.Lookup(tzid); found != nil {
			loc, w.Floating, w.TZID = found, false, tzid
		}
	}
	t, err := time.ParseInLocation("20060102T150405", value, loc)
	if err != nil {
		return When{}, fmt.Errorf("bad time %q", value)
	}
	w.Time = t
	return w, nil
}

// Prop reads a property's (first) DATE or DATE-TIME value.
func (z Zones) Prop(p *Prop) (When, error) {
	first, _, _ := strings.Cut(p.Value, ",")
	return z.When(first, p.Param("TZID"), p.Param("VALUE") == "DATE")
}

// Value is w as a property value and its parameters.
func (w When) Value() (string, []Param) {
	switch {
	case w.Date:
		return w.Format("20060102"), []Param{{"VALUE", "DATE"}}
	case w.Floating:
		return w.Format("20060102T150405"), nil
	case w.TZID != "":
		return w.Format("20060102T150405"), []Param{{"TZID", w.TZID}}
	default:
		return w.UTC().Format("20060102T150405Z"), nil
	}
}

// SetWhen replaces every property named name with one holding w.
func (c *Component) SetWhen(name string, w When) {
	value, params := w.Value()
	c.Set(name, value, params...)
}

// AddWhen appends a property holding w.
func (c *Component) AddWhen(name string, w When) {
	value, params := w.Value()
	c.Add(name, value, params...)
}

// Period is an RDATE's value: a start, and for a period its End or its
// Length (HasLength).
type Period struct {
	Start     When
	End       *When
	Length    time.Duration
	HasLength bool
}

// List reads every value of a property that may hold several (RDATE,
// EXDATE), periods included.
func (z Zones) List(p Prop) ([]Period, error) {
	var out []Period
	tzid, date := p.Param("TZID"), p.Param("VALUE") == "DATE"
	for _, value := range strings.Split(p.Value, ",") {
		start, rest, isPeriod := strings.Cut(value, "/")
		s, err := z.When(start, tzid, date)
		if err != nil {
			return nil, err
		}
		period := Period{Start: s}
		if isPeriod {
			if strings.HasPrefix(strings.TrimLeft(rest, "+-"), "P") {
				d, err := ParseDuration(rest)
				if err != nil {
					return nil, err
				}
				period.Length, period.HasLength = d, true
			} else {
				e, err := z.When(rest, tzid, false)
				if err != nil {
					return nil, err
				}
				period.End = &e
			}
		}
		out = append(out, period)
	}
	return out, nil
}

// ParseDuration reads a DURATION: [+-]P[nW][nD][T[nH][nM][nS]].
func ParseDuration(value string) (time.Duration, error) {
	s := strings.ToUpper(strings.TrimSpace(value))
	sign := time.Duration(1)
	if rest, ok := strings.CutPrefix(s, "-"); ok {
		s, sign = rest, -1
	}
	s = strings.TrimPrefix(s, "+")
	s, ok := strings.CutPrefix(s, "P")
	if !ok || s == "" {
		return 0, fmt.Errorf("bad duration %q", value)
	}
	var total time.Duration
	inTime := false
	units := map[bool]map[byte]time.Duration{
		false: {'W': 7 * 24 * time.Hour, 'D': 24 * time.Hour},
		true:  {'H': time.Hour, 'M': time.Minute, 'S': time.Second},
	}
	for s != "" {
		if s[0] == 'T' {
			inTime, s = true, s[1:]
			continue
		}
		i := 0
		for i < len(s) && s[i] >= '0' && s[i] <= '9' {
			i++
		}
		if i == 0 || i == len(s) {
			return 0, fmt.Errorf("bad duration %q", value)
		}
		n, _ := strconv.Atoi(s[:i])
		unit, ok := units[inTime][s[i]]
		if !ok {
			return 0, fmt.Errorf("bad duration %q", value)
		}
		total += time.Duration(n) * unit
		s = s[i+1:]
	}
	return sign * total, nil
}

// FormatDuration writes d as a DURATION: -PT30M, P1D, PT0S.
func FormatDuration(d time.Duration) string {
	sign := ""
	if d < 0 {
		sign, d = "-", -d
	}
	days, rest := d/(24*time.Hour), d%(24*time.Hour)
	out := sign + "P"
	if days > 0 {
		out += strconv.Itoa(int(days)) + "D"
	}
	if rest > 0 || days == 0 {
		out += "T"
		h, m, s := int(rest/time.Hour), int(rest%time.Hour/time.Minute), int(rest%time.Minute/time.Second)
		if h > 0 {
			out += strconv.Itoa(h) + "H"
		}
		if m > 0 {
			out += strconv.Itoa(m) + "M"
		}
		if s > 0 || (h == 0 && m == 0) {
			out += strconv.Itoa(s) + "S"
		}
	}
	return out
}
