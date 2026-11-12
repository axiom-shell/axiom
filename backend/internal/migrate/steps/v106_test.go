package steps

import "testing"

func TestV106DropsColorText(t *testing.T) {
	t.Parallel()
	runStepCases(t, 106, []stepCase{
		{"a bar widget and a custom widget",
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Battery","id":"b","properties":{"appearance":{"style":"icon","colorText":true,"width":null}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text","colorText":false,"popout":true}}]}}`,
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Battery","id":"b","properties":{"appearance":{"style":"icon","width":null}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text","popout":true}}]}}`, true},
		{"a widget in a group",
			`{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"Clock","properties":{"appearance":{"colorText":true}}}]}}]}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"Clock","properties":{"appearance":{}}}]}}]}]}}`, true},
		{"already migrated", `{"Bars":{"items":[{"left":[{"type":"Battery","properties":{"appearance":{"style":"icon"}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text"}}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"Battery","properties":{"appearance":{"style":"icon"}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text"}}]}}`, false},
		{"odd shapes", `{"X":[{"properties":{"appearance":"colorText"}},{"properties":[1]}],"CustomWidgets":{"items":["x",{"bar":3}]}}`,
			`{"X":[{"properties":{"appearance":"colorText"}},{"properties":[1]}],"CustomWidgets":{"items":["x",{"bar":3}]}}`, false},
		{"nothing", `{"General":{}}`, `{"General":{}}`, false},
	})
}
