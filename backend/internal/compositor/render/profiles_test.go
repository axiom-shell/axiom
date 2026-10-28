package render

import (
	"reflect"
	"testing"
)

// The profile picker's cases (tst_MonitorLayout's matchProfile and
// savedRules)
func TestProfiles(t *testing.T) {
	t.Parallel()
	profiles := parse(t, `[
		{"name": "Desk", "outputs": [{"output": "desc:AOC CU34G4Z XJ9R7HA000231"}, {"output": "HDMI-A-1", "disabled": true}]},
		{"name": "TV", "outputs": [{"output": "desc:AOC CU34G4Z XJ9R7HA000231"}, {"output": "desc:LG TV"}]}
	]`)
	aoc := Output{Name: "DP-1", Description: "AOC CU34G4Z XJ9R7HA000231"}
	tv := Output{Name: "HDMI-A-1", Description: "LG TV"}
	offTV := Output{Name: "HDMI-A-1", Description: "LG TV", Disabled: true}
	other := Output{Name: "DP-3", Description: "Other"}
	tests := []struct {
		name     string
		profiles any
		outputs  []Output
		match    int
		rules    []string // the saved rules' outputs
	}{
		{"a disabled output may be missing", profiles, []Output{aoc}, 0, []string{"desc:AOC CU34G4Z XJ9R7HA000231"}},
		{"exact match wins", profiles, []Output{aoc, tv}, 1, []string{"desc:AOC CU34G4Z XJ9R7HA000231", "desc:LG TV"}},
		{"most covered", profiles, []Output{tv}, 1, []string{"desc:LG TV"}},
		{"a disabled output doesn't pick the profile, but keeps its rule", profiles, []Output{aoc, offTV}, 0, []string{"desc:AOC CU34G4Z XJ9R7HA000231", "HDMI-A-1"}},
		{"a description matches trimmed", profiles, []Output{{Name: "DP-2", Description: " LG TV "}}, 1, []string{"desc:LG TV"}},
		{"nothing known", profiles, []Output{other}, -1, nil},
		{"no profiles", parse(t, `[]`), []Output{aoc}, -1, nil},
		{"ties go to the earlier", parse(t, `[{"outputs": [{"output": "DP-1"}, {"output": "DP-9"}]}, {"outputs": [{"output": "DP-1"}, {"output": "DP-8"}]}]`), []Output{aoc}, 0, []string{"DP-1"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := MatchProfile(tt.profiles, tt.outputs); got != tt.match {
				t.Errorf("MatchProfile = %d, want %d", got, tt.match)
			}
			var got []string
			for _, rule := range SavedRules(tt.profiles, tt.outputs) {
				got = append(got, str(get(rule, "output")))
			}
			if !reflect.DeepEqual(got, tt.rules) {
				t.Errorf("SavedRules = %q, want %q", got, tt.rules)
			}
		})
	}
}
