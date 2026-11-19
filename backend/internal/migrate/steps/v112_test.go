package steps

import "testing"

func TestV112RenamesInterfaceScale(t *testing.T) {
	t.Parallel()
	runStepCases(t, 112, []stepCase{
		{"renamed", `{"Interface":{"scale":125,"density":"roomy"}}`,
			`{"Interface":{"density":"roomy","contentSize":125}}`, true},
		{"the default value", `{"Interface":{"scale":100}}`, `{"Interface":{"contentSize":100}}`, true},
		{"beside an already set contentSize", `{"Interface":{"scale":125,"contentSize":90}}`,
			`{"Interface":{"contentSize":90}}`, true},
		{"already migrated", `{"Interface":{"contentSize":125}}`, `{"Interface":{"contentSize":125}}`, false},
		{"no scale", `{"Interface":{"density":"roomy"}}`, `{"Interface":{"density":"roomy"}}`, false},
		{"scale not a number", `{"Interface":{"scale":"big"}}`, `{"Interface":{"scale":"big"}}`, false},
		{"Interface not an object", `{"Interface":"x"}`, `{"Interface":"x"}`, false},
		{"no Interface section", `{"Bars":{}}`, `{"Bars":{}}`, false},
	})
}
