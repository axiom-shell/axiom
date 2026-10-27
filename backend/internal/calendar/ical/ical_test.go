package ical

import (
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func TestParse(t *testing.T) {
	t.Parallel()
	c, err := Parse("BEGIN:VCALENDAR\r\nX-WR-CALNAME:Team\\, Berlin\r\nBEGIN:VEVENT\r\nSUMMARY;LANGUAGE=en;X-A=\"a:b;c\":Long\r\n  title\\nnext\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
	if err != nil {
		t.Fatal(err)
	}
	if c.Name != "VCALENDAR" || c.Text("X-WR-CALNAME") != "Team, Berlin" || c.Text("MISSING") != "" || len(c.Children) != 1 {
		t.Errorf("calendar %+v", c)
	}
	p := c.Children[0].Get("SUMMARY")
	if p.Text() != "Long title\nnext" || p.Param("X-A") != "a:b;c" || p.Param("LANGUAGE") != "en" {
		t.Errorf("summary %+v", p)
	}
	for _, bad := range []string{"", "not a calendar", "BEGIN:VCALENDAR\nEND:VEVENT\n", "BEGIN:VCALENDAR\nX;A=\"open:x\n"} {
		if _, err := Parse(bad); err == nil {
			t.Errorf("%q parsed", bad)
		}
	}
}

func TestDurations(t *testing.T) {
	t.Parallel()
	for value, want := range map[string]time.Duration{"PT15M": 15 * time.Minute, "-P1DT2H": -26 * time.Hour, "P2W": 14 * day, "+PT1S": time.Second, "PT0S": 0, "-PT1H30M": -90 * time.Minute} {
		got, err := ParseDuration(value)
		if err != nil || got != want {
			t.Errorf("%s: %v %v", value, got, err)
		}
		if again, _ := ParseDuration(FormatDuration(got)); again != got {
			t.Errorf("%s: written as %s", value, FormatDuration(got))
		}
	}
	if FormatDuration(-30*time.Minute) != "-PT30M" || FormatDuration(day) != "P1D" || FormatDuration(0) != "PT0S" {
		t.Error("durations aren't written as icalendar does")
	}
}

// Encoding keeps what it read (unknown properties, quoted parameters)
// and folds long lines without splitting a character
func TestEncode(t *testing.T) {
	t.Parallel()
	text := "BEGIN:VCALENDAR\r\nX-UNKNOWN;X-P=\"a:b\":kept\\, as is\r\nBEGIN:VEVENT\r\nSUMMARY:" + strings.Repeat("é", 60) + "\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
	c, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	out := c.Encode()
	for _, l := range strings.Split(out, "\r\n") {
		if len(l) > 75 || !utf8.ValidString(l) {
			t.Errorf("line %q", l)
		}
	}
	again, err := Parse(out)
	if err != nil || again.Encode() != out || again.Children[0].Text("SUMMARY") != strings.Repeat("é", 60) || again.Get("X-UNKNOWN").Value != `kept\, as is` {
		t.Errorf("round trip:\n%s", out)
	}
}
