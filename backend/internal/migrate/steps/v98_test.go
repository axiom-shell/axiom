package steps

import "testing"

func TestV98DropsTriggersAndEdgeMenuPadding(t *testing.T) {
	t.Parallel()
	runStepCases(t, 98, []stepCase{
		{"every place",
			`{"Popouts":{"padding":12,"trigger":{"size":5}},"Bars":{"items":[{"id":"main","trigger":{"size":3}},{"id":"b"}]},"Dock":{"items":[{"id":"main","trigger":{"size":4},"padding":6}]},"EdgeMenus":{"items":[{"id":"m","trigger":{"size":5,"length":0},"padding":-1}]}}`,
			`{"Popouts":{"padding":12},"Bars":{"items":[{"id":"main"},{"id":"b"}]},"Dock":{"items":[{"id":"main","padding":6}]},"EdgeMenus":{"items":[{"id":"m"}]}}`, true},
		{"an edge menu's padding alone", `{"EdgeMenus":{"items":[{"id":"m","padding":20}]}}`, `{"EdgeMenus":{"items":[{"id":"m"}]}}`, true},
		{"nothing to drop", `{"Popouts":{"padding":12},"Bars":{"items":[{"id":"main"}]}}`, `{"Popouts":{"padding":12},"Bars":{"items":[{"id":"main"}]}}`, false},
		{"items not a list", `{"Bars":{"items":3}}`, `{"Bars":{"items":3}}`, false},
		{"an entry not an object", `{"EdgeMenus":{"items":[1]}}`, `{"EdgeMenus":{"items":[1]}}`, false},
		{"no sections", `{"General":{}}`, `{"General":{}}`, false},
	})
}
