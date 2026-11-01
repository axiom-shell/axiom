package steps

import "testing"

func TestV85DropsTheTrayIconSize(t *testing.T) {
	t.Parallel()
	bar := func(widgets string) string {
		return `{"Bars":{"items":[{"id":"a","widgets":` + widgets + `}]}}`
	}
	runStepCases(t, 85, []stepCase{
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
	})
}
