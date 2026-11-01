package steps

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func TestV86RenamesTheOSDBars(t *testing.T) {
	t.Parallel()
	step := stepAt(t, 86)
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"one OSD",
			`{"OSD":{"items":[{"id":"main","bars":[{"type":"master"}],"timeout":900}]}}`,
			`{"OSD":{"items":[{"id":"main","items":[{"type":"master"}],"timeout":900}]}}`, true},
		{"the old default gets the new statuses",
			`{"OSD":{"items":[{"id":"main","bars":[{"type":"other","icon":"music_note","showOsd":true,"apps":[]},{"type":"master","icon":"","showOsd":true}]}]}}`,
			`{"OSD":{"items":[{"id":"main","items":[{"type":"other","icon":"music_note","showOsd":true,"apps":[]},{"type":"master","icon":"","showOsd":true},{"type":"lockKeys","icon":"","showOsd":true},{"type":"keyboardLayout","icon":"","showOsd":true},{"type":"micMute","icon":"","showOsd":true},{"type":"outputDevice","icon":"","showOsd":true}]}]}}`, true},
		{"the default bars edited stay as they are",
			`{"OSD":{"items":[{"id":"main","bars":[{"type":"other","icon":"music_note","showOsd":false},{"type":"master","icon":"","showOsd":true}]}]}}`,
			`{"OSD":{"items":[{"id":"main","items":[{"type":"other","icon":"music_note","showOsd":false},{"type":"master","icon":"","showOsd":true}]}]}}`, true},
		{"two OSDs, one with the default bars",
			`{"OSD":{"items":[{"id":"a","edge":"top","bars":[]},{"id":"b"}]}}`,
			`{"OSD":{"items":[{"id":"a","edge":"top","items":[]},{"id":"b"}]}}`, true},
		{"already migrated",
			`{"OSD":{"items":[{"id":"a","items":[{"type":"lockKeys"}]}]}}`,
			`{"OSD":{"items":[{"id":"a","items":[{"type":"lockKeys"}]}]}}`, false},
		{"both keys: items kept, bars left for pruning",
			`{"OSD":{"items":[{"id":"a","bars":[],"items":[{"type":"master"}]}]}}`,
			`{"OSD":{"items":[{"id":"a","bars":[],"items":[{"type":"master"}]}]}}`, false},
		{"no OSD section", `{"General":{}}`, `{"General":{}}`, false},
		{"another shape", `{"OSD":{"items":[2,{"id":"a"}]}}`, `{"OSD":{"items":[2,{"id":"a"}]}}`, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			v, err := jsonx.Unmarshal([]byte(c.in))
			if err != nil {
				t.Fatal(err)
			}
			cfg := v.(*jsonx.Object)
			changes := step.Run(cfg)
			if got := string(jsonx.MarshalCompact(cfg)); got != c.out {
				t.Errorf("got %s, want %s", got, c.out)
			}
			if (len(changes) > 0) != c.changed {
				t.Errorf("changes %v", changes)
			}
			if again := step.Run(cfg); len(again) > 0 {
				t.Errorf("a second run: %v", again)
			}
		})
	}
}
