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

// stepCase is a config before and after a step, and whether it changed
type stepCase struct {
	name, in, out string
	changed       bool
}

// runStepCases runs a version's step on each case's config: it must give
// out, report a change when it made one, and change nothing a second time.
func runStepCases(t *testing.T, version int, cases []stepCase) {
	t.Helper()
	step := stepAt(t, version)
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
				t.Errorf("got  %s\nwant %s", got, c.out)
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

func TestV83RenamesAppTimeouts(t *testing.T) {
	t.Parallel()
	runStepCases(t, 83, []stepCase{
		{"on", `{"Notifications":{"appTimeouts":true,"timeout":5000}}`, `{"Notifications":{"timeout":5000,"followApps":true}}`, true},
		{"off", `{"Notifications":{"appTimeouts":false}}`, `{"Notifications":{"followApps":false}}`, true},
		{"beside an already set followApps", `{"Notifications":{"appTimeouts":false,"followApps":true}}`, `{"Notifications":{"followApps":true}}`, true},
		{"already migrated", `{"Notifications":{"followApps":true}}`, `{"Notifications":{"followApps":true}}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
		{"a section of another shape", `{"Notifications":3}`, `{"Notifications":3}`, false},
	})
}
