package steps

import "testing"

func TestV99StoresAutomaticAsNull(t *testing.T) {
	t.Parallel()
	runStepCases(t, 99, []stepCase{
		{"both automatic",
			`{"Notifications":{"gap":-1,"apps":[{"id":"a","timeout":-1},{"id":"b","timeout":3000},{"id":"c"}]}}`,
			`{"Notifications":{"gap":null,"apps":[{"id":"a","timeout":null},{"id":"b","timeout":3000},{"id":"c"}]}}`, true},
		{"a rule alone", `{"Notifications":{"gap":12,"apps":[{"id":"a","timeout":-1}]}}`, `{"Notifications":{"gap":12,"apps":[{"id":"a","timeout":null}]}}`, true},
		{"the gap alone", `{"Notifications":{"gap":-1}}`, `{"Notifications":{"gap":null}}`, true},
		{"already migrated", `{"Notifications":{"gap":null,"apps":[{"id":"a","timeout":null}]}}`, `{"Notifications":{"gap":null,"apps":[{"id":"a","timeout":null}]}}`, false},
		{"set values kept", `{"Notifications":{"gap":0,"apps":[{"id":"a","timeout":0}]}}`, `{"Notifications":{"gap":0,"apps":[{"id":"a","timeout":0}]}}`, false},
		{"apps not a list", `{"Notifications":{"apps":3}}`, `{"Notifications":{"apps":3}}`, false},
		{"a rule not an object", `{"Notifications":{"apps":[1]}}`, `{"Notifications":{"apps":[1]}}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
	})
}
