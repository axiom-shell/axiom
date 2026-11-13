package steps

import "testing"

func TestV108SpecialWorkspaces(t *testing.T) {
	t.Parallel()
	runStepCases(t, 108, []stepCase{
		{"valid names",
			`{"Workspaces":{"layout":"grid","scratchpads":[{"id":"x1","name":"magic","icon":"star","text":"M"},{"id":"x2","name":"my-pad_2","icon":"","text":""}],"wrap":true}}`,
			`{"Workspaces":{"layout":"grid","specialWorkspaces":[{"id":"magic","icon":"star","text":"M"},{"id":"my-pad_2","icon":"","text":""}],"wrap":true}}`, true},
		{"a spaced name, its bind, preset and hot corner",
			`{"Workspaces":{"scratchpads":[{"id":"a","name":"my pad","icon":"x","text":"y"}]},"Keybinds":{"binds":[{"key":"SUPER + V","action":"toggleSpecial","argument":"my pad"},{"key":"SUPER + M","action":"moveToSpecial","argument":"my pad"},{"key":"SUPER + D","action":"dock","argument":"my pad"}],"presets":[{"id":"p","binds":[{"action":"toggleSpecial","argument":"a;b"}]},"odd"]},"HotCorners":{"items":[{"corner":"topLeft","action":"toggleSpecial","argument":"my pad"},3]}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"my-pad","icon":"x","text":"y"}]},"Keybinds":{"binds":[{"key":"SUPER + V","action":"toggleSpecial","argument":"my-pad"},{"key":"SUPER + M","action":"moveToSpecial","argument":"my-pad"},{"key":"SUPER + D","action":"dock","argument":"my pad"}],"presets":[{"id":"p","binds":[{"action":"toggleSpecial","argument":"a-b"}]},"odd"]},"HotCorners":{"items":[{"corner":"topLeft","action":"toggleSpecial","argument":"my-pad"},3]}}`, true},
		{"empty, unusable and non-object entries",
			`{"Workspaces":{"scratchpads":[{"id":"a","name":""},{"id":"b","name":"  "},{"id":"c","name":"!!!"},{"id":"d"},7,{"id":"e","name":"ok","icon":"i"}]}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"ok","icon":"i"}]}}`, true},
		{"duplicates, the first wins",
			`{"Workspaces":{"scratchpads":[{"id":"a","name":"my pad","text":"one"},{"id":"b","name":"my-pad","text":"two"},{"id":"c","name":"my pad","text":"three"}]}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"my-pad","text":"one"}]}}`, true},
		{"the reserved name",
			`{"Workspaces":{"scratchpads":[{"id":"a","name":"special"}]},"Keybinds":{"binds":[{"action":"toggleSpecial","argument":"special"}]}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"special-1"}]},"Keybinds":{"binds":[{"action":"toggleSpecial","argument":"special-1"}]}}`, true},
		{"long, leading and non-ASCII names",
			`{"Workspaces":{"scratchpads":[{"id":"a","name":"  --Ünï code  "},{"id":"b","name":"abcdefghijklmnopqrstuvwxyz0123456789"}]}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"n-code"},{"id":"abcdefghijklmnopqrstuvwxyz012345"}]}}`, true},
		{"an empty or unusable bind argument stays",
			`{"Keybinds":{"binds":[{"action":"toggleSpecial","argument":""},{"action":"toggleSpecial","argument":"!!"},{"action":"toggleSpecial"},{"action":"toggleSpecial","argument":3}]}}`,
			`{"Keybinds":{"binds":[{"action":"toggleSpecial","argument":""},{"action":"toggleSpecial","argument":"!!"},{"action":"toggleSpecial"},{"action":"toggleSpecial","argument":3}]}}`, false},
		{"no Workspaces section", `{"Bars":{}}`, `{"Bars":{}}`, false},
		{"Workspaces not an object", `{"Workspaces":3}`, `{"Workspaces":3}`, false},
		{"scratchpads not an array", `{"Workspaces":{"scratchpads":"x"}}`, `{"Workspaces":{"scratchpads":"x"}}`, false},
		{"specialWorkspaces not an array, replaced",
			`{"Workspaces":{"scratchpads":[{"id":"a","name":"magic"}],"specialWorkspaces":"x"}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"magic"}]}}`, true},
		{"specialWorkspaces already an array, untouched",
			`{"Workspaces":{"scratchpads":[{"id":"a","name":"old"}],"specialWorkspaces":[{"id":"new"}]}}`,
			`{"Workspaces":{"scratchpads":[{"id":"a","name":"old"}],"specialWorkspaces":[{"id":"new"}]}}`, false},
		{"the widget's options, in place, nested too",
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Workspaces","properties":{"layout":"x","scratchpads":"all","scratchpadLabel":"text","scratchpadSplit":true,"gap":2}},{"type":"Group","properties":{"widgets":[{"type":"Workspaces","properties":{"scratchpads":"off"}}]}},{"type":"Clock","properties":{"scratchpads":"keep"}}]}]}}`,
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Workspaces","properties":{"layout":"x","specialWorkspaces":"all","specialWorkspaceLabel":"text","specialWorkspaceSplit":true,"gap":2}},{"type":"Group","properties":{"widgets":[{"type":"Workspaces","properties":{"specialWorkspaces":"off"}}]}},{"type":"Clock","properties":{"scratchpads":"keep"}}]}]}}`, true},
		{"the overview's options",
			`{"WorkspaceOverlay":{"dim":1,"scratchpads":"all","scratchpadColor":"base0D"}}`,
			`{"WorkspaceOverlay":{"dim":1,"specialWorkspaces":"all","specialWorkspaceColor":"base0D"}}`, true},
		{"already migrated",
			`{"Workspaces":{"specialWorkspaces":[{"id":"magic"}]},"WorkspaceOverlay":{"specialWorkspaces":"all","specialWorkspaceColor":"base0E"},"Keybinds":{"binds":[{"action":"toggleSpecial","argument":"magic"}]},"Bars":{"items":[{"left":[{"type":"Workspaces","properties":{"specialWorkspaces":"all"}}]}]}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"magic"}]},"WorkspaceOverlay":{"specialWorkspaces":"all","specialWorkspaceColor":"base0E"},"Keybinds":{"binds":[{"action":"toggleSpecial","argument":"magic"}]},"Bars":{"items":[{"left":[{"type":"Workspaces","properties":{"specialWorkspaces":"all"}}]}]}}`, false},
		{"odd shapes", `{"Keybinds":{"binds":"x","presets":{}},"HotCorners":[],"WorkspaceOverlay":3}`, `{"Keybinds":{"binds":"x","presets":{}},"HotCorners":[],"WorkspaceOverlay":3}`, false},
	})
}
