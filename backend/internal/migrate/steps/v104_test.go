package steps

import "testing"

func TestV104RenamesEdgeMenusToMenus(t *testing.T) {
	t.Parallel()
	runStepCases(t, 104, []stepCase{
		{"the section, in its place", `{"Bars":{},"EdgeMenus":{"items":[{"id":"m","placement":"free"}]},"Desktop":{}}`,
			`{"Bars":{},"Menus":{"items":[{"id":"m","placement":"free","animation":"fade"}]},"Desktop":{}}`, true},
		{"an unknown Menus beside it", `{"Menus":{"items":[{"id":"x"}]},"EdgeMenus":{"items":[{"id":"m"}]}}`,
			`{"Menus":{"items":[{"id":"m"}]}}`, true},
		{"a free menu's animation, with and without freeAnimation",
			`{"EdgeMenus":{"items":[{"id":"a","placement":"free","freeAnimation":"scale"},{"id":"b","placement":"free"},{"id":"c","placement":"free","animation":"slide","freeAnimation":"slide"},{"id":"d","placement":"free","animation":"slide"},{"id":"e","placement":"free","freeAnimation":3}]}}`,
			`{"Menus":{"items":[{"id":"a","placement":"free","animation":"scale"},{"id":"b","placement":"free","animation":"fade"},{"id":"c","placement":"free","animation":"slide"},{"id":"d","placement":"free","animation":"fade"},{"id":"e","placement":"free","animation":"fade"}]}}`, true},
		{"an edge or strip menu keeps its animation",
			`{"EdgeMenus":{"items":[{"id":"a","animation":"fade","freeAnimation":"scale"},{"id":"b","placement":"edge"},{"id":"c","placement":"strip","freeAnimation":"fade"},1]}}`,
			`{"Menus":{"items":[{"id":"a","animation":"fade"},{"id":"b","placement":"edge"},{"id":"c","placement":"strip"},1]}}`, true},
		{"menus' items not a list", `{"EdgeMenus":{"items":3}}`, `{"Menus":{"items":3}}`, true},
		{"a Menus section left alone", `{"Menus":{"items":[{"id":"a","placement":"free","freeAnimation":"scale"}]}}`,
			`{"Menus":{"items":[{"id":"a","placement":"free","freeAnimation":"scale"}]}}`, false},
		{"keybinds, presets and hot corners",
			`{"Keybinds":{"binds":[{"key":"SUPER + E","action":"edgeMenu","argument":"left"},{"key":"SUPER + D","action":"dock"}],"presets":[{"id":"p","binds":[{"action":"edgeMenu","argument":"m"}]},"odd"]},"HotCorners":{"items":[{"corner":"topLeft","action":"edgeMenu","argument":"m"},3]}}`,
			`{"Keybinds":{"binds":[{"key":"SUPER + E","action":"menu","argument":"left"},{"key":"SUPER + D","action":"dock"}],"presets":[{"id":"p","binds":[{"action":"menu","argument":"m"}]},"odd"]},"HotCorners":{"items":[{"corner":"topLeft","action":"menu","argument":"m"},3]}}`, true},
		{"buttons wherever they sit",
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Button","properties":{"action":"edgeMenu","menu":"m"}},{"type":"Group","properties":{"widgets":[{"type":"Button","properties":{"action":"edgeMenu"}}]}}]}]}}`,
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Button","properties":{"action":"menu","menu":"m"}},{"type":"Group","properties":{"widgets":[{"type":"Button","properties":{"action":"menu"}}]}}]}]}}`, true},
		{"another type's action", `{"X":[{"type":"Clock","properties":{"action":"edgeMenu"}}],"Other":{"binds":[{"action":"edgeMenu"}]}}`,
			`{"X":[{"type":"Clock","properties":{"action":"edgeMenu"}}],"Other":{"binds":[{"action":"edgeMenu"}]}}`, false},
		{"already new", `{"Menus":{"items":[]},"Keybinds":{"binds":[{"action":"menu"}]},"Bars":{"items":[{"left":[{"type":"Button","properties":{"action":"menu"}}]}]}}`,
			`{"Menus":{"items":[]},"Keybinds":{"binds":[{"action":"menu"}]},"Bars":{"items":[{"left":[{"type":"Button","properties":{"action":"menu"}}]}]}}`, false},
		{"odd shapes", `{"Keybinds":{"binds":"x","presets":{}},"HotCorners":[]}`, `{"Keybinds":{"binds":"x","presets":{}},"HotCorners":[]}`, false},
		{"nothing", `{"General":{}}`, `{"General":{}}`, false},
	})
}
