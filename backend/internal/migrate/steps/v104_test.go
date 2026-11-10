package steps

import "testing"

func TestV104RenamesEdgeMenusToMenus(t *testing.T) {
	t.Parallel()
	runStepCases(t, 104, []stepCase{
		{"the section, in its place", `{"Bars":{},"EdgeMenus":{"items":[{"id":"m","placement":"free"}]},"Desktop":{}}`,
			`{"Bars":{},"Menus":{"items":[{"id":"m","placement":"free"}]},"Desktop":{}}`, true},
		{"an unknown Menus beside it", `{"Menus":{"items":[{"id":"x"}]},"EdgeMenus":{"items":[{"id":"m"}]}}`,
			`{"Menus":{"items":[{"id":"m"}]}}`, true},
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
