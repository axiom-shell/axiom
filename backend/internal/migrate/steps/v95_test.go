package steps

import "testing"

func TestV95AddsInputSourceBinds(t *testing.T) {
	t.Parallel()
	next := `{"id":"ctrl-space","key":"CTRL + space","action":"inputSourceNext","argument":"","call":"toggle","compositor":"hyprland","repeating":false,"locked":true,"release":false,"paused":false,"description":""}`
	prev := `{"id":"ctrl-shift-space","key":"CTRL + SHIFT + space","action":"inputSourcePrev","argument":"","call":"toggle","compositor":"hyprland","repeating":false,"locked":true,"release":false,"paused":false,"description":""}`
	runStepCases(t, 95, []stepCase{
		{"both free",
			`{"Keybinds":{"binds":[{"id":"super-space","key":"SUPER + space","action":"launcher"}]}}`,
			`{"Keybinds":{"binds":[{"id":"super-space","key":"SUPER + space","action":"launcher"},` + next + `,` + prev + `]}}`, true},
		{"the key bound already, in another order",
			`{"Keybinds":{"binds":[{"id":"mine","key":"SPACE + CTRL","action":"launcher"}]}}`,
			`{"Keybinds":{"binds":[{"id":"mine","key":"SPACE + CTRL","action":"launcher"},` + prev + `]}}`, true},
		{"the action bound already",
			`{"Keybinds":{"binds":[{"id":"a","key":"ALT + space","action":"inputSourceNext"},{"id":"b","key":"ALT + SHIFT + space","action":"inputSourcePrev"}]}}`,
			`{"Keybinds":{"binds":[{"id":"a","key":"ALT + space","action":"inputSourceNext"},{"id":"b","key":"ALT + SHIFT + space","action":"inputSourcePrev"}]}}`, false},
		{"the id taken",
			`{"Keybinds":{"binds":[{"id":"ctrl-space","key":"F1","action":"lock"},` + prev + `]}}`,
			`{"Keybinds":{"binds":[{"id":"ctrl-space","key":"F1","action":"lock"},` + prev + `]}}`, false},
		{"no binds", `{"Keybinds":{}}`, `{"Keybinds":{}}`, false},
		{"binds not a list", `{"Keybinds":{"binds":3}}`, `{"Keybinds":{"binds":3}}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
	})
}
