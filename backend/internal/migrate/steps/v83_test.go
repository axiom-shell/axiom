package steps

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// stepAt is the step of a version
func stepAt(t *testing.T, version int) Step {
	t.Helper()
	for _, s := range all {
		if s.Version == version {
			return s
		}
	}
	t.Fatalf("no step %d", version)
	return Step{}
}

func TestV83RenamesAppTimeouts(t *testing.T) {
	t.Parallel()
	step := stepAt(t, 83)
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"on", `{"Notifications":{"appTimeouts":true,"timeout":5000}}`, `{"Notifications":{"timeout":5000,"followApps":true}}`, true},
		{"off", `{"Notifications":{"appTimeouts":false}}`, `{"Notifications":{"followApps":false}}`, true},
		{"beside an already set followApps", `{"Notifications":{"appTimeouts":false,"followApps":true}}`, `{"Notifications":{"followApps":true}}`, true},
		{"already migrated", `{"Notifications":{"followApps":true}}`, `{"Notifications":{"followApps":true}}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
		{"a section of another shape", `{"Notifications":3}`, `{"Notifications":3}`, false},
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
