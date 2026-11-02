package steps

import "testing"

func TestV92TurnsAppRuleSwitchesIntoLevel(t *testing.T) {
	t.Parallel()
	runStepCases(t, 92, []stepCase{
		{"both on", `{"Notifications":{"apps":[{"id":"a","app":"x","toasts":true,"history":true}]}}`, `{"Notifications":{"apps":[{"id":"a","app":"x","level":"alert"}]}}`, true},
		{"toasts off", `{"Notifications":{"apps":[{"id":"a","toasts":false}]}}`, `{"Notifications":{"apps":[{"id":"a","level":"silent"}]}}`, true},
		{"history off", `{"Notifications":{"apps":[{"id":"a","history":false,"urgency":"low"}]}}`, `{"Notifications":{"apps":[{"id":"a","urgency":"low","level":"toast"}]}}`, true},
		{"both off", `{"Notifications":{"apps":[{"id":"a","toasts":false,"history":false}]}}`, `{"Notifications":{"apps":[{"id":"a","level":"off"}]}}`, true},
		{"already migrated", `{"Notifications":{"apps":[{"id":"a","level":"silent"}]}}`, `{"Notifications":{"apps":[{"id":"a","level":"silent"}]}}`, false},
		{"a rule with neither", `{"Notifications":{"apps":[{"id":"a","app":"x"}]}}`, `{"Notifications":{"apps":[{"id":"a","app":"x"}]}}`, false},
		{"no apps", `{"Notifications":{"dnd":{}}}`, `{"Notifications":{"dnd":{}}}`, false},
		{"no Notifications", `{"OSD":{}}`, `{"OSD":{}}`, false},
	})
}
