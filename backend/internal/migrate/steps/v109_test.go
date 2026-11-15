package steps

import "testing"

func TestV109AddsTheWindowRulesPage(t *testing.T) {
	t.Parallel()
	runStepCases(t, 109, []stepCase{
		{"appended last",
			`{"Overlay":{"items":[{"id":"keybinds","type":"Keybinds"}]}}`,
			`{"Overlay":{"items":[{"id":"keybinds","type":"Keybinds"},{"id":"windowRules","type":"WindowRules"}]}}`, true},
		{"already there, under any id",
			`{"Overlay":{"items":[{"id":"rules","type":"WindowRules"}]}}`,
			`{"Overlay":{"items":[{"id":"rules","type":"WindowRules"}]}}`, false},
		{"another type holding the id",
			`{"Overlay":{"items":[{"id":"windowRules","type":"Custom"}]}}`,
			`{"Overlay":{"items":[{"id":"windowRules","type":"Custom"},{"id":"windowRules-2","type":"WindowRules"}]}}`, true},
		{"no Overlay", `{"Bars":{}}`, `{"Bars":{}}`, false},
		{"items not an array", `{"Overlay":{"items":3}}`, `{"Overlay":{"items":3}}`, false},
		{"an item that isn't an object",
			`{"Overlay":{"items":[7,{"id":"a","type":"X"}]}}`,
			`{"Overlay":{"items":[7,{"id":"a","type":"X"},{"id":"windowRules","type":"WindowRules"}]}}`, true},
	})
}
