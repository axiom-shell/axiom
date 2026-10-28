package render

import (
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The profile picker's cases (the shell's matchProfile had them, and the
// savedRules it had before the daemon switched profiles)
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

// Hyprland's rules (HyprlandRules, as MonitorCalls writes them): the
// matched profile's, then those for monitors it leaves out, connected or
// not, that every profile naming them sets the same way
func TestHyprlandRules(t *testing.T) {
	t.Parallel()
	profiles := parse(t, `[
		{"name": "Laptop", "outputs": [{"output": "eDP-1", "mode": "1920x1200@60"}, {"output": "desc:Dell", "mode": "2560x1440@60", "x": 1920}]},
		{"name": "Dock", "outputs": [{"output": "eDP-1", "disabled": true}, {"output": "desc:Dell", "mode": "2560x1440@60", "x": 1920}, {"output": "desc:LG", "mode": "3840x2160@60", "scale": 2}]},
		{"name": "Away", "outputs": [{"output": "eDP-1", "mode": "1920x1200@60"}, {"output": "desc:LG", "mode": "3840x2160@30", "scale": 2}]},
		{"name": "TV", "outputs": [{"output": "DP-3", "mode": "1920x1080@60"}]}
	]`)
	laptop := Output{Name: "eDP-1"}
	dell := Output{Name: "DP-1", Description: "Dell"}
	lg := Output{Name: "DP-2", Description: "LG"}
	tests := []struct {
		name    string
		outputs []Output
		want    []string
	}{
		{"the Dell and the TV agree everywhere; the LG doesn't", []Output{laptop}, []string{
			`hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
			`hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
		{"a connected output keeps the matched rule", []Output{laptop, dell, lg}, []string{
			`hl.monitor({ output = "eDP-1", disabled = true })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
			`hl.monitor({ output = "desc:LG", mode = "3840x2160@60", position = "0x0", scale = 2 })`,
			`hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
		{"a connected output the match leaves out gets the agreed rule", []Output{laptop, dell, {Name: "DP-3"}}, []string{
			`hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
			`hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
		{"an output the match names by description gets no second rule by connector", []Output{laptop, {Name: "DP-3", Description: "Dell"}}, []string{
			`hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
		}},
		{"no profile matches: none", []Output{{Name: "HDMI-A-1"}}, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := MonitorCalls(jsonx.Arr(HyprlandRules(profiles, tt.outputs)...), MirrorNames(nil)); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %q\nwant %q", got, tt.want)
			}
		})
	}
}
