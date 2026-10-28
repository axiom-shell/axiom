package render

import (
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func parse(t *testing.T, text string) any {
	t.Helper()
	v, err := jsonx.Unmarshal([]byte(text))
	if err != nil {
		t.Fatal(err)
	}
	return v
}

// Monitor rules applied now (outputs.apply), as each compositor takes them;
// the cases the shell's helpers held before the daemon took the job over
func TestOutputsApplied(t *testing.T) {
	t.Parallel()
	details := parse(t, `[{"name": "DP-1", "description": "Main"}, {"name": "HDMI-A-1", "description": "TV "}]`)
	tests := []struct {
		name, rules string
		got         func(rules any) any
		want        any
	}{
		{"hyprland mirrors by description", `[{"output": "desc:TV", "mirror": "desc:Main"}]`,
			func(r any) any { return MonitorCalls(r, MirrorNames(details)) },
			[]string{`hl.monitor({ output = "desc:TV", mode = "preferred", position = "0x0", scale = 1, mirror = "DP-1" })`}},
		{"hyprland mirrors by connector", `[{"output": "DP-3", "mirror": "HDMI-A-1"}]`,
			func(r any) any { return MonitorCalls(r, MirrorNames(details)) },
			[]string{`hl.monitor({ output = "DP-3", mode = "preferred", position = "0x0", scale = 1, mirror = "HDMI-A-1" })`}},
		{"hyprland leaves out a mirror not connected", `[{"output": "DP-3", "mirror": "desc:Gone"}, {"output": "DP-3", "mirror": "DP-9"}]`,
			func(r any) any { return MonitorCalls(r, MirrorNames(details)) },
			[]string{`hl.monitor({ output = "DP-3", mode = "preferred", position = "0x0", scale = 1 })`, `hl.monitor({ output = "DP-3", mode = "preferred", position = "0x0", scale = 1 })`}},
		{"sway, by description", `[{"output": "desc:AOC CU34G4Z XJ9", "mode": "3440x1440@240", "x": 15, "y": 83, "scale": 1, "transform": 0, "vrr": 1}]`,
			func(r any) any { return SwayOutputCommands(r) },
			`output "AOC CU34G4Z XJ9" enable mode 3440x1440@240Hz pos 15 83 scale 1 transform normal adaptive_sync on render_bit_depth 8`},
		{"sway, preferred mode and 10 bits", `[{"output": "HDMI-A-1", "mode": "preferred", "x": 0, "y": 0, "scale": 1.5, "transform": 5, "bitdepth": 10}]`,
			func(r any) any { return SwayOutputCommands(r) },
			`output HDMI-A-1 enable pos 0 0 scale 1.5 transform flipped-90 adaptive_sync off render_bit_depth 10`},
		{"sway, disabled last", `[{"output": "DP-2", "disabled": true}, {"output": "DP-1", "mode": "1920x1080"}]`,
			func(r any) any { return SwayOutputCommands(r) },
			`output DP-1 enable mode 1920x1080 pos 0 0 scale 1 transform normal adaptive_sync off render_bit_depth 8; output DP-2 disable`},
		{"niri, a description nothing connected has", `[{"output": "desc:Gone", "mode": "1920x1080"}]`,
			func(r any) any { return string(jsonx.MarshalCompact(NiriOutputRequests(r, details))) },
			`[]`},
		{"niri, a make Hyprland names by its bare code", `[{"output": "desc:AOC CU34G4Z", "disabled": true}]`,
			func(r any) any {
				return string(jsonx.MarshalCompact(NiriOutputRequests(r, parse(t, `[{"name": "DP-2", "description": "PNP(AOC) CU34G4Z"}]`))))
			},
			`[{"Output":{"output":"DP-2","action":"Off"}}]`},
		{"niri, every part, disabled last", `[{"output": "HDMI-A-1", "disabled": true}, {"output": "desc:Main", "mode": "3840x2160@60", "x": 0, "y": 0, "scale": 1.5, "transform": 1, "vrr": 2}]`,
			func(r any) any { return string(jsonx.MarshalCompact(NiriOutputRequests(r, details))) },
			`[{"Output":{"output":"DP-1","action":"On"}},` +
				`{"Output":{"output":"DP-1","action":{"Mode":{"mode":{"Specific":{"width":3840,"height":2160,"refresh":60}}}}}},` +
				`{"Output":{"output":"DP-1","action":{"Scale":{"scale":{"Specific":1.5}}}}},` +
				`{"Output":{"output":"DP-1","action":{"Transform":{"transform":"_90"}}}},` +
				`{"Output":{"output":"DP-1","action":{"Position":{"position":{"Specific":{"x":0,"y":0}}}}}},` +
				`{"Output":{"output":"DP-1","action":{"Vrr":{"vrr":{"vrr":true,"on_demand":true}}}}},` +
				`{"Output":{"output":"HDMI-A-1","action":"Off"}}]`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := tt.got(parse(t, tt.rules)); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got  %v\nwant %v", got, tt.want)
			}
		})
	}
}
