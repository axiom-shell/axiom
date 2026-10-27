package ical

import "testing"

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
