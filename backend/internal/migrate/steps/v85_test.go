package steps

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func TestV85DropsTheTrayIconSize(t *testing.T) {
	t.Parallel()
	step := stepAt(t, 85)
	bar := func(widgets string) string {
		return `{"Bars":{"items":[{"id":"a","widgets":` + widgets + `}]}}`
	}
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"a tray's icon size",
			bar(`{"right":[{"id":"t","type":"SystemTray","properties":{"iconSize":24,"showPassive":false}}]}`),
			bar(`{"right":[{"id":"t","type":"SystemTray","properties":{"showPassive":false}}]}`), true},
		{"trays on two bars",
			`{"Bars":{"items":[{"id":"a","widgets":{"left":[{"id":"t","type":"SystemTray","properties":{"iconSize":18}}]}},{"id":"b","widgets":{"center":[{"id":"u","type":"SystemTray","properties":{"iconSize":30}}]}}]}}`,
			`{"Bars":{"items":[{"id":"a","widgets":{"left":[{"id":"t","type":"SystemTray","properties":{}}]}},{"id":"b","widgets":{"center":[{"id":"u","type":"SystemTray","properties":{}}]}}]}}`, true},
		{"another widget's iconSize stays",
			bar(`{"right":[{"id":"x","type":"Button","properties":{"iconSize":24}}]}`),
			bar(`{"right":[{"id":"x","type":"Button","properties":{"iconSize":24}}]}`), false},
		{"already migrated",
			bar(`{"right":[{"id":"t","type":"SystemTray","properties":{"showPassive":true}}]}`),
			bar(`{"right":[{"id":"t","type":"SystemTray","properties":{"showPassive":true}}]}`), false},
		{"no properties", bar(`{"right":[{"id":"t","type":"SystemTray"}]}`), bar(`{"right":[{"id":"t","type":"SystemTray"}]}`), false},
		{"no bars", `{"General":{}}`, `{"General":{}}`, false},
		{"another shape", `{"Bars":{"items":[{"widgets":{"right":[{"type":"SystemTray","properties":3}]}},2]}}`, `{"Bars":{"items":[{"widgets":{"right":[{"type":"SystemTray","properties":3}]}},2]}}`, false},
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
