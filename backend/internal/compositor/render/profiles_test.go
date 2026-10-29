package render

import (
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The profile picker's cases, and its rules for the outputs
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
		{"niri's PNP(XXX) make matches the bare code, and is written as niri spells it", profiles, []Output{{Name: "DP-1", Description: "PNP(AOC) CU34G4Z XJ9R7HA000231"}}, 0, []string{"desc:PNP(AOC) CU34G4Z XJ9R7HA000231"}},
		{"and the bare code a profile saved under niri", parse(t, `[{"outputs": [{"output": "desc:PNP(AOC) CU34G4Z XJ9R7HA000231"}]}]`), []Output{aoc}, 0, []string{"desc:AOC CU34G4Z XJ9R7HA000231"}},
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
	// Dell was last seen on DP-3, which Dock names by connector; DP-4 is
	// another monitor's connector
	seenOn := parse(t, `[
		{"name": "Laptop", "outputs": [{"output": "eDP-1", "mode": "1920x1200@60"}]},
		{"name": "Desk", "outputs": [{"output": "eDP-1", "disabled": true}, {"output": "desc:Dell", "label": "DP-3", "mode": "2560x1440@60", "x": 1920}]},
		{"name": "Dock", "outputs": [{"output": "eDP-1", "disabled": true}, {"output": "DP-3", "mode": "1920x1080@60"}, {"output": "DP-4", "mode": "1920x1080@60"}]}
	]`)
	tests := []struct {
		name     string
		profiles any
		outputs  []Output
		want     []string
	}{
		{"the Dell and the TV agree everywhere; the LG doesn't", nil, []Output{laptop}, []string{
			`hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
			`hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
		{"a connected output keeps the matched rule", nil, []Output{laptop, dell, lg}, []string{
			`hl.monitor({ output = "eDP-1", disabled = true })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
			`hl.monitor({ output = "desc:LG", mode = "3840x2160@60", position = "0x0", scale = 2 })`,
			`hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
		{"a connected output the match leaves out gets the agreed rule", nil, []Output{laptop, dell, {Name: "DP-3"}}, []string{
			`hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
			`hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
		{"an output the match names by description gets no second rule by connector", nil, []Output{laptop, {Name: "DP-3", Description: "Dell"}}, []string{
			`hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
		}},
		{"no profile matches: none", nil, []Output{{Name: "HDMI-A-1"}}, nil},
		{"an unplugged monitor named by description and by the connector it was seen on, disagreeing: neither", seenOn, []Output{laptop}, []string{
			`hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "DP-4", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
		{"plugged in elsewhere, known apart: both", seenOn, []Output{laptop, {Name: "DP-1", Description: "Dell"}}, []string{
			`hl.monitor({ output = "eDP-1", disabled = true })`,
			`hl.monitor({ output = "desc:Dell", mode = "2560x1440@60", position = "1920x0", scale = 1 })`,
			`hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "DP-4", mode = "1920x1080@60", position = "0x0", scale = 1 })`,
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if tt.profiles == nil {
				tt.profiles = profiles
			}
			if got := MonitorCalls(jsonx.Arr(HyprlandRules(tt.profiles, tt.outputs)...), MirrorNames(nil)); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %q\nwant %q", got, tt.want)
			}
		})
	}
}

// A profile saved under another compositor is written in the running one's
// spelling: the connected output's description, or for a monitor not
// connected (Hyprland's rules only) the bare make code
func TestProfileSpelling(t *testing.T) {
	t.Parallel()
	underNiri := parse(t, `[
		{"outputs": [{"output": "desc:PNP(AOC) CU34G4Z X1", "mode": "3440x1440@100"}]},
		{"outputs": [{"output": "eDP-1"}, {"output": "desc:PNP(GSM) LG Y2", "mode": "3840x2160@60"}]}
	]`)
	underHyprland := parse(t, `[{"outputs": [{"output": "desc:AOC CU34G4Z X1", "mode": "3440x1440@100"}]}]`)
	bare := []Output{{Name: "DP-1", Description: "AOC CU34G4Z X1"}}
	tests := []struct {
		name string
		got  any
		want any
	}{
		{"Hyprland", MonitorCalls(jsonx.Arr(HyprlandRules(underNiri, bare)...), MirrorNames(nil)), []string{
			`hl.monitor({ output = "desc:AOC CU34G4Z X1", mode = "3440x1440@100", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })`,
			`hl.monitor({ output = "desc:GSM LG Y2", mode = "3840x2160@60", position = "0x0", scale = 1 })`,
		}},
		{"sway", SwayOutputCommands(jsonx.Arr(SavedRules(underNiri, bare)...)),
			`output "AOC CU34G4Z X1" enable mode 3440x1440@100Hz pos 0 0 scale 1 transform normal adaptive_sync off render_bit_depth 8`},
		{"niri", items(get(items(NiriOutputNodes(jsonx.Arr(SavedRules(underHyprland, []Output{{Name: "DP-1", Description: "PNP(AOC) CU34G4Z X1"}})...)))[0], "args"))[0],
			"PNP(AOC) CU34G4Z X1"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if !reflect.DeepEqual(tt.got, tt.want) {
				t.Errorf("got %q\nwant %q", tt.got, tt.want)
			}
		})
	}
	if saved := str(get(items(get(items(underNiri)[0], "outputs"))[0], "output")); saved != "desc:PNP(AOC) CU34G4Z X1" {
		t.Errorf("the saved profile changed: %q", saved)
	}
}
