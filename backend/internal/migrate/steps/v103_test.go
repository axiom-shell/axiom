package steps

import "testing"

func TestV103MovesModeToPlacement(t *testing.T) {
	t.Parallel()
	runStepCases(t, 103, []stepCase{
		{"every value",
			`{"EdgeMenus":{"items":[{"id":"a","mode":"floating","edge":"left"},{"id":"b","mode":"integrated"},{"id":"c","mode":"submenu"}]}}`,
			`{"EdgeMenus":{"items":[{"id":"a","edge":"left","placement":"edge"},{"id":"b","placement":"strip"},{"id":"c","placement":"free"}]}}`, true},
		{"already migrated", `{"EdgeMenus":{"items":[{"id":"a","placement":"strip"}]}}`, `{"EdgeMenus":{"items":[{"id":"a","placement":"strip"}]}}`, false},
		{"a placement and a stale mode", `{"EdgeMenus":{"items":[{"id":"a","placement":"free","mode":"floating"}]}}`, `{"EdgeMenus":{"items":[{"id":"a","placement":"free","mode":"floating"}]}}`, false},
		{"no mode", `{"EdgeMenus":{"items":[{"id":"a","edge":"top"}]}}`, `{"EdgeMenus":{"items":[{"id":"a","edge":"top"}]}}`, false},
		{"an unknown mode", `{"EdgeMenus":{"items":[{"id":"a","mode":"sideways"}]}}`, `{"EdgeMenus":{"items":[{"id":"a","mode":"sideways"}]}}`, false},
		{"a mode not a string", `{"EdgeMenus":{"items":[{"id":"a","mode":3}]}}`, `{"EdgeMenus":{"items":[{"id":"a","mode":3}]}}`, false},
		{"an entry not an object", `{"EdgeMenus":{"items":[1,{"id":"b","mode":"submenu"}]}}`, `{"EdgeMenus":{"items":[1,{"id":"b","placement":"free"}]}}`, true},
		{"items not a list", `{"EdgeMenus":{"items":3}}`, `{"EdgeMenus":{"items":3}}`, false},
		{"the section not an object", `{"EdgeMenus":[]}`, `{"EdgeMenus":[]}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
	})
}
