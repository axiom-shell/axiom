package steps

import "testing"

func TestV105DropsColorText(t *testing.T) {
	t.Parallel()
	runStepCases(t, 105, []stepCase{
		{"a bar widget and a custom widget",
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Battery","id":"b","properties":{"appearance":{"style":"icon","colorText":true,"width":0}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text","colorText":false,"popout":true}}]}}`,
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Battery","id":"b","properties":{"appearance":{"style":"icon","width":0}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text","popout":true}}]}}`, true},
		{"already migrated", `{"Bars":{"items":[{"left":[{"type":"Battery","properties":{"appearance":{"style":"icon"}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text"}}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"Battery","properties":{"appearance":{"style":"icon"}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text"}}]}}`, false},
		{"odd shapes", `{"X":[{"properties":{"appearance":"colorText"}},{"properties":[1]}],"CustomWidgets":{"items":["x",{"bar":3}]}}`,
			`{"X":[{"properties":{"appearance":"colorText"}},{"properties":[1]}],"CustomWidgets":{"items":["x",{"bar":3}]}}`, false},
		{"nothing", `{"General":{}}`, `{"General":{}}`, false},
	})
}
