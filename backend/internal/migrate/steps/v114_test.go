package steps

import "testing"

func TestV114MovesOverlayModuleScaleOntoPages(t *testing.T) {
	t.Parallel()
	runStepCases(t, 114, []stepCase{
		{"a Custom page and a tool page", `{"Overlay":{"moduleScale":80,"items":[{"id":"home","type":"Custom"},{"id":"settings","type":"Settings"}]}}`,
			`{"Overlay":{"items":[{"id":"home","type":"Custom","sizing":{"cardSize":80}},{"id":"settings","type":"Settings","sizing":{"contentSize":80}}]}}`, true},
		{"at 100", `{"Overlay":{"moduleScale":100,"items":[{"id":"home","type":"Custom"}]}}`,
			`{"Overlay":{"items":[{"id":"home","type":"Custom"}]}}`, true},
		{"no items, the value is dropped", `{"Overlay":{"moduleScale":60,"navigator":"top"}}`,
			`{"Overlay":{"navigator":"top"}}`, true},
		{"items not a list", `{"Overlay":{"moduleScale":60,"items":3}}`,
			`{"Overlay":{"items":3}}`, true},
		{"an item not an object", `{"Overlay":{"moduleScale":70,"items":[3,{"id":"home","type":"Custom"}]}}`,
			`{"Overlay":{"items":[3,{"id":"home","type":"Custom","sizing":{"cardSize":70}}]}}`, true},
		{"beside an already set sizing", `{"Overlay":{"moduleScale":70,"items":[{"id":"home","type":"Custom","sizing":{"cardSize":90}}]}}`,
			`{"Overlay":{"items":[{"id":"home","type":"Custom","sizing":{"cardSize":90}}]}}`, true},
		{"already migrated", `{"Overlay":{"items":[{"id":"home","type":"Custom","sizing":{"cardSize":80}}]}}`,
			`{"Overlay":{"items":[{"id":"home","type":"Custom","sizing":{"cardSize":80}}]}}`, false},
		{"moduleScale not a number", `{"Overlay":{"moduleScale":"big","items":[{"id":"home","type":"Custom"}]}}`,
			`{"Overlay":{"moduleScale":"big","items":[{"id":"home","type":"Custom"}]}}`, false},
		{"Overlay not an object", `{"Overlay":"x"}`, `{"Overlay":"x"}`, false},
		{"no Overlay section", `{"Bars":{}}`, `{"Bars":{}}`, false},
	})
}
