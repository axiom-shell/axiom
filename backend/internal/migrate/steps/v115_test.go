package steps

import "testing"

func TestV115DropsPopoutAtWidget(t *testing.T) {
	t.Parallel()
	runStepCases(t, 115, []stepCase{
		{"a menu with it on",
			`{"Menus":{"items":[{"id":"a","popoutAtWidget":true}]}}`,
			`{"Menus":{"items":[{"id":"a"}]}}`, true},
		{"on or off, only the key goes",
			`{"Menus":{"items":[{"id":"a","popoutAtWidget":false,"edge":"top"},{"id":"b","popoutAtWidget":true,"edge":"left"}]}}`,
			`{"Menus":{"items":[{"id":"a","edge":"top"},{"id":"b","edge":"left"}]}}`, true},
		{"a menu without it",
			`{"Menus":{"items":[{"id":"a"}]}}`,
			`{"Menus":{"items":[{"id":"a"}]}}`, false},
		{"no Menus", `{"Bars":{}}`, `{"Bars":{}}`, false},
		{"items not an array", `{"Menus":{"items":3}}`, `{"Menus":{"items":3}}`, false},
		{"an item that isn't an object",
			`{"Menus":{"items":[7,{"popoutAtWidget":true}]}}`,
			`{"Menus":{"items":[7,{}]}}`, true},
	})
}
