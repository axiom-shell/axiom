package steps

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func TestV84PlacesNotificationsOnAnEdge(t *testing.T) {
	t.Parallel()
	step := stepAt(t, 84)
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"top right, even gaps",
			`{"Notifications":{"position":"topRight","gaps":{"even":true,"all":18,"left":12,"right":12},"timeout":5000}}`,
			`{"Notifications":{"position":100,"timeout":5000,"edge":"top","detached":true,"gap":18}}`, true},
		{"bottom left, uneven gaps take the side's",
			`{"Notifications":{"position":"bottomLeft","gaps":{"even":false,"all":12,"left":30,"right":5}}}`,
			`{"Notifications":{"position":0,"edge":"bottom","detached":true,"gap":30}}`, true},
		{"bottom right, uneven",
			`{"Notifications":{"position":"bottomRight","gaps":{"even":false,"right":40}}}`,
			`{"Notifications":{"position":100,"edge":"bottom","detached":true,"gap":40}}`, true},
		{"the old default gap becomes Auto",
			`{"Notifications":{"position":"topLeft","gaps":{"even":true,"all":12}}}`,
			`{"Notifications":{"position":0,"edge":"top","detached":true}}`, true},
		{"no gaps",
			`{"Notifications":{"position":"topLeft"}}`,
			`{"Notifications":{"position":0,"edge":"top","detached":true}}`, true},
		{"an unknown corner goes top left",
			`{"Notifications":{"position":"middle"}}`,
			`{"Notifications":{"position":0,"edge":"top","detached":true}}`, true},
		{"already migrated",
			`{"Notifications":{"edge":"right","position":50,"detached":false}}`,
			`{"Notifications":{"edge":"right","position":50,"detached":false}}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
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
