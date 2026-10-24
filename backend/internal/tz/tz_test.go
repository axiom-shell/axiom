package tz

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestParseZi(t *testing.T) {
	t.Parallel()
	zi := `# version 2026a
R E 1981 ma - Mar lastSu 1u 1 S
Z Europe/Paris 0:9:21 - LMT 1891 Mar 16
1 E CE%sT
Z Asia/Tokyo 9:18:59 - LMT 1887 D 31 15u
9 J J%sT
L Asia/Tokyo Japan
L Europe/Paris Europe/Monaco
Z Asia/Tokyo 9 - JST
`
	want := []string{"Asia/Tokyo", "Europe/Monaco", "Europe/Paris", "Japan"}
	if got := ParseZi(strings.NewReader(zi)); !slices.Equal(got, want) {
		t.Errorf("zones %q, want %q", got, want)
	}
}

// The system's zoneinfo, where it has one: Tokyo keeps no daylight
// saving, Paris has it in July and not in January.
func TestOffsets(t *testing.T) {
	t.Parallel()
	if _, err := os.Stat(filepath.Join(DefaultDir, "Asia/Tokyo")); err != nil {
		t.Skip("no zoneinfo")
	}
	cases := []struct {
		at   time.Time
		want map[string]int
	}{
		{time.Date(2026, 1, 15, 12, 0, 0, 0, time.UTC), map[string]int{"Asia/Tokyo": 540, "Europe/Paris": 60, "America/St_Johns": -210}},
		{time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC), map[string]int{"Asia/Tokyo": 540, "Europe/Paris": 120, "America/St_Johns": -150}},
	}
	for _, tc := range cases {
		got := Offsets(DefaultDir, []string{"Asia/Tokyo", "Europe/Paris", "America/St_Johns", "Nowhere/Atlantis", "../../etc/passwd", "/etc/passwd"}, tc.at)
		if len(got) != len(tc.want) {
			t.Errorf("%s: %v", tc.at, got)
		}
		for zone, offset := range tc.want {
			if got[zone] != offset {
				t.Errorf("%s: %s %d, want %d", tc.at, zone, got[zone], offset)
			}
		}
	}
}

// Without tzdata.zi, the zones are the zoneinfo files found.
func TestZonesWithoutZi(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	write := func(name, content string) {
		path := filepath.Join(dir, name)
		os.MkdirAll(filepath.Dir(path), 0o755)
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("Asia/Tokyo", "TZif2...")
	write("UTC", "TZif2...")
	write("posix/Asia/Tokyo", "TZif2...")
	write("localtime", "TZif2...")
	write("zone1970.tab", "# not a zone")
	if got, want := Zones(dir), []string{"Asia/Tokyo", "UTC"}; !slices.Equal(got, want) {
		t.Errorf("zones %q, want %q", got, want)
	}
	write("tzdata.zi", "Z Europe/Paris 1 - CET\n")
	if got, want := Zones(dir), []string{"Europe/Paris"}; !slices.Equal(got, want) {
		t.Errorf("zones from tzdata.zi %q, want %q", got, want)
	}
}
