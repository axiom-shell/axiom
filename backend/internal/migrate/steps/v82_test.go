package steps

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func TestV82MovesNirisHotCorner(t *testing.T) {
	t.Parallel()
	step := all[len(all)-1]
	if step.Version != 82 {
		t.Fatalf("step %d", step.Version)
	}
	corner := func(id string) string {
		return `{"id":"` + id + `","corner":"topLeft","action":"workspaceOverview","argument":"","screen":{"mode":"all","names":[]},"delay":0}`
	}
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"on in managed mode",
			`{"Compositor":{"mode":"managed","niri":{"hotCorner":true,"animations":true}}}`,
			`{"Compositor":{"mode":"managed","niri":{"animations":true}},"HotCorners":{"items":[` + corner("niri-corner") + `]}}`, true},
		{"beside the user's own corners",
			`{"HotCorners":{"items":[{"id":"niri-corner"}]},"Compositor":{"mode":"managed","niri":{"hotCorner":true}}}`,
			`{"HotCorners":{"items":[{"id":"niri-corner"},` + corner("niri-corner-2") + `]},"Compositor":{"mode":"managed","niri":{}}}`, true},
		{"off", `{"Compositor":{"mode":"managed","niri":{"hotCorner":false}}}`, `{"Compositor":{"mode":"managed","niri":{}}}`, true},
		{"on in detached mode, where it wrote nothing",
			`{"Compositor":{"mode":"detached","niri":{"hotCorner":true}}}`, `{"Compositor":{"mode":"detached","niri":{}}}`, true},
		{"a section of another shape",
			`{"HotCorners":3,"Compositor":{"mode":"managed","niri":{"hotCorner":true}}}`, `{"HotCorners":3,"Compositor":{"mode":"managed","niri":{}}}`, true},
		{"already migrated", `{"Compositor":{"mode":"managed","niri":{}}}`, `{"Compositor":{"mode":"managed","niri":{}}}`, false},
		{"no niri section", `{"Compositor":{"mode":"managed"}}`, `{"Compositor":{"mode":"managed"}}`, false},
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
