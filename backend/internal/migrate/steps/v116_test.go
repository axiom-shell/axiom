package steps

import "testing"

func TestV116ModuleOptionRenames(t *testing.T) {
	t.Parallel()
	runStepCases(t, 116, []stepCase{
		{"Markets layout on an Overlay page, order kept", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"Markets","properties":{"layout":"tiles","range":"5d"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"Markets","properties":{"style":"tiles","range":"5d"}}]}]}}`, true},
		{"Markets on the lock screen", `{"Lockscreen":{"layout":[{"type":"Markets","properties":{"layout":"focus"}}]}}`,
			`{"Lockscreen":{"layout":[{"type":"Markets","properties":{"style":"focus"}}]}}`, true},
		{"Cheatsheet view in a Menu", `{"Menus":{"items":[{"id":"m","layout":[{"type":"Cheatsheet","properties":{"view":"keyboard"}}]}]}}`,
			`{"Menus":{"items":[{"id":"m","layout":[{"type":"Cheatsheet","properties":{"style":"keyboard"}}]}]}}`, true},
		{"Agenda maxEvents on the desktop", `{"Desktop":{"modules":[{"type":"Agenda","properties":{"maxEvents":5}}]}}`,
			`{"Desktop":{"modules":[{"type":"Agenda","properties":{"count":5}}]}}`, true},
		{"Favourites true becomes auto", `{"Desktop":{"modules":[{"type":"Favourites","properties":{"showLabels":true}}]}}`,
			`{"Desktop":{"modules":[{"type":"Favourites","properties":{"labels":"auto"}}]}}`, true},
		{"Favourites false becomes hide", `{"Desktop":{"modules":[{"type":"Favourites","properties":{"showLabels":false}}]}}`,
			`{"Desktop":{"modules":[{"type":"Favourites","properties":{"labels":"hide"}}]}}`, true},
		{"Favourites a string is removed", `{"Desktop":{"modules":[{"type":"Favourites","properties":{"showLabels":"yes"}}]}}`,
			`{"Desktop":{"modules":[{"type":"Favourites","properties":{}}]}}`, true},
		{"Favourites with labels set drops showLabels", `{"Desktop":{"modules":[{"type":"Favourites","properties":{"showLabels":true,"labels":"show"}}]}}`,
			`{"Desktop":{"modules":[{"type":"Favourites","properties":{"labels":"show"}}]}}`, true},
		{"both old and new keys of a rename", `{"Desktop":{"modules":[{"type":"Agenda","properties":{"maxEvents":5,"count":9}}]}}`,
			`{"Desktop":{"modules":[{"type":"Agenda","properties":{"count":9}}]}}`, true},
		{"already migrated", `{"Desktop":{"modules":[{"type":"Markets","properties":{"style":"list"}},{"type":"Favourites","properties":{"labels":"hide"}}]}}`,
			`{"Desktop":{"modules":[{"type":"Markets","properties":{"style":"list"}},{"type":"Favourites","properties":{"labels":"hide"}}]}}`, false},
		{"a Markets bar widget is untouched", `{"Bars":{"items":[{"id":"b","widgets":[{"type":"Markets","properties":{"layout":"x"}}]}]}}`,
			`{"Bars":{"items":[{"id":"b","widgets":[{"type":"Markets","properties":{"layout":"x"}}]}]}}`, false},
		{"properties not an object", `{"Desktop":{"modules":[{"type":"Markets","properties":3}]}}`,
			`{"Desktop":{"modules":[{"type":"Markets","properties":3}]}}`, false},
		{"Overlay not an object", `{"Overlay":"x"}`, `{"Overlay":"x"}`, false},
		{"no sections", `{}`, `{}`, false},
	})
}
