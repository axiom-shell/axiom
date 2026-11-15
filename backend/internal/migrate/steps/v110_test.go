package steps

import "testing"

func TestV110MenuAndDockColoursToAuto(t *testing.T) {
	t.Parallel()
	runStepCases(t, 110, []stepCase{
		{"menus with both defaults",
			`{"Menus":{"items":[{"id":"a","backgroundColor":"base00","borderColor":"base05"}]}}`,
			`{"Menus":{"items":[{"id":"a","backgroundColor":"","borderColor":""}]}}`, true},
		{"docks with both defaults",
			`{"Dock":{"items":[{"id":"d","backgroundColor":"base00","borderColor":"base05"}]}}`,
			`{"Dock":{"items":[{"id":"d","backgroundColor":"","borderColor":""}]}}`, true},
		{"a user colour kept beside a default one changed",
			`{"Menus":{"items":[{"backgroundColor":"base01","borderColor":"#ff0000"},{"backgroundColor":"base00","borderColor":"base05"}]}}`,
			`{"Menus":{"items":[{"backgroundColor":"base01","borderColor":"#ff0000"},{"backgroundColor":"","borderColor":""}]}}`, true},
		{"already Auto",
			`{"Menus":{"items":[{"backgroundColor":"","borderColor":""}]}}`,
			`{"Menus":{"items":[{"backgroundColor":"","borderColor":""}]}}`, false},
		{"only one key a default",
			`{"Dock":{"items":[{"backgroundColor":"base03","borderColor":"base05"}]}}`,
			`{"Dock":{"items":[{"backgroundColor":"base03","borderColor":""}]}}`, true},
		{"no Menus or Dock", `{"Bars":{}}`, `{"Bars":{}}`, false},
		{"items not an array", `{"Menus":{"items":3},"Dock":{"items":"x"}}`, `{"Menus":{"items":3},"Dock":{"items":"x"}}`, false},
		{"an item that isn't an object",
			`{"Menus":{"items":[7,{"backgroundColor":"base00"}]}}`,
			`{"Menus":{"items":[7,{"backgroundColor":""}]}}`, true},
		{"a non-string colour left alone",
			`{"Menus":{"items":[{"backgroundColor":7,"borderColor":"base05"}]}}`,
			`{"Menus":{"items":[{"backgroundColor":7,"borderColor":""}]}}`, true},
		{"by value, not position",
			`{"Menus":{"items":[{"backgroundColor":"base0A"},{"backgroundColor":"base00"},{"backgroundColor":"base0B"}]}}`,
			`{"Menus":{"items":[{"backgroundColor":"base0A"},{"backgroundColor":""},{"backgroundColor":"base0B"}]}}`, true},
	})
}
