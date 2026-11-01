package steps

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func TestV87SplitsTheOSDItems(t *testing.T) {
	t.Parallel()
	step := stepAt(t, 87)
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"the v86 default",
			`{"OSD":{"items":[{"id":"main","orientation":"horizontal","items":[{"type":"other","icon":"music_note","showOsd":true,"apps":[]},{"type":"master","icon":"","showOsd":true},{"type":"lockKeys","icon":"","showOsd":true},{"type":"keyboardLayout","icon":"","showOsd":true},{"type":"micMute","icon":"","showOsd":true},{"type":"outputDevice","icon":"","showOsd":true}],"timeout":900}]}}`,
			`{"OSD":{"items":[{"id":"main","bars":{"orientation":"horizontal","items":[{"type":"other","icon":"music_note","showOsd":true,"apps":[]},{"type":"master","icon":"","showOsd":true}]},"statuses":{"items":["capsLock","numLock","keyboardLayout","microphone","audio"],"quiet":[]},"timeout":900}]}}`, true},
		{"lock keys by their flags, quiet ones, media, an icon dropped",
			`{"OSD":{"items":[{"id":"a","showPercent":false,"items":[{"type":"lockKeys","caps":false,"scroll":true,"showOsd":false},{"type":"dnd","icon":"bell"},{"type":"media","onPlayPause":true},{"type":"message","icon":"chat"}]}]}}`,
			`{"OSD":{"items":[{"id":"a","bars":{"showPercent":false,"items":[]},"statuses":{"items":["numLock","scrollLock","dnd","message"],"quiet":["numLock","scrollLock"]},"media":{"enabled":true,"onPlayPause":true}}]}}`, true},
		{"the microphone muted and the input device are one status",
			`{"OSD":{"items":[{"id":"a","items":[{"type":"outputDevice","showOsd":false},{"type":"micMute"},{"type":"inputDevice"}]}]}}`,
			`{"OSD":{"items":[{"id":"a","bars":{"items":[]},"statuses":{"items":["audio","microphone"],"quiet":["audio"]}}]}}`, true},
		{"a v85 bars list beside items is replaced",
			`{"OSD":{"items":[{"id":"a","bars":[],"items":[{"type":"brightness","allMonitors":true}]}]}}`,
			`{"OSD":{"items":[{"id":"a","bars":{"items":[{"type":"brightness","allMonitors":true}]},"statuses":{"items":[],"quiet":[]}}]}}`, true},
		{"already migrated",
			`{"OSD":{"items":[{"id":"a","bars":{"items":[]},"statuses":{"items":[]}}]}}`,
			`{"OSD":{"items":[{"id":"a","bars":{"items":[]},"statuses":{"items":[]}}]}}`, false},
		{"default items, its own layout",
			`{"OSD":{"items":[{"id":"a","edge":"left","orientation":"horizontal","showPercent":false,"timeout":900}]}}`,
			`{"OSD":{"items":[{"id":"a","edge":"left","bars":{"orientation":"horizontal","showPercent":false},"timeout":900}]}}`, true},
		{"an OSD on its defaults", `{"OSD":{"items":[{"id":"a"}]}}`, `{"OSD":{"items":[{"id":"a"}]}}`, false},
		{"no OSD section", `{"General":{}}`, `{"General":{}}`, false},
		{"another shape", `{"OSD":{"items":[2,{"id":"a","items":[3]}]}}`, `{"OSD":{"items":[2,{"id":"a","bars":{"items":[]},"statuses":{"items":[],"quiet":[]}}]}}`, true},
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
