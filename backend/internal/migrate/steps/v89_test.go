package steps

import "testing"

func TestV89DropsUnsafeCornersAndTheInstantLogout(t *testing.T) {
	t.Parallel()
	runStepCases(t, 89, []stepCase{
		{"an unsafe corner among safe ones",
			`{"HotCorners":{"items":[{"id":"a","action":"workspaceOverview"},{"id":"b","corner":"topRight","action":"clearNotifications"},{"id":"c","action":"moveWindowNth","argument":"2"}]}}`,
			`{"HotCorners":{"items":[{"id":"a","action":"workspaceOverview"}]}}`, true},
		{"only safe corners",
			`{"HotCorners":{"items":[{"id":"a","action":"lock"},{"id":"b"}]}}`,
			`{"HotCorners":{"items":[{"id":"a","action":"lock"},{"id":"b"}]}}`, false},
		{"no items", `{"HotCorners":{}}`, `{"HotCorners":{}}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
		{"another shape", `{"HotCorners":{"items":[3,{"id":"a","action":2}]}}`, `{"HotCorners":{"items":[3,{"id":"a","action":2}]}}`, false},
		{"the old default log-out bind",
			`{"Keybinds":{"binds":[{"id":"super-escape","key":"SUPER + Escape","action":"powerMenu"},{"id":"super-shift-escape","key":"SUPER + SHIFT + Escape","action":"exitSession","release":true}]}}`,
			`{"Keybinds":{"binds":[{"id":"super-escape","key":"SUPER + Escape","action":"powerMenu"}]}}`, true},
		{"a log-out bind the user changed stays",
			`{"Keybinds":{"binds":[{"id":"super-shift-escape","key":"SUPER + SHIFT + Q","action":"exitSession"},{"id":"mine","key":"SUPER + SHIFT + Escape","action":"exitSession"}]}}`,
			`{"Keybinds":{"binds":[{"id":"super-shift-escape","key":"SUPER + SHIFT + Q","action":"exitSession"},{"id":"mine","key":"SUPER + SHIFT + Escape","action":"exitSession"}]}}`, false},
		{"binds not a list", `{"Keybinds":{"binds":3}}`, `{"Keybinds":{"binds":3}}`, false},
		{"an OSD on the old default status icons",
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["capsLock","numLock","keyboardLayout","microphone","audio"],"quiet":[]}},{"id":"b","statuses":{"items":["audio"]}},{"id":"c"}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["capsLock","numLock","keyboardLayout","microphone","audio","dnd","caffeine","nightLight","recording"],"quiet":[]}},{"id":"b","statuses":{"items":["audio"]}},{"id":"c"}]}}`, true},
		{"an OSD on the old default with drives",
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["capsLock","numLock","keyboardLayout","microphone","audio","drive"]}}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["capsLock","numLock","keyboardLayout","microphone","audio","dnd","caffeine","nightLight","recording","drive"]}}]}}`, true},
		{"status icons of the user's own order stay",
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["audio","microphone","keyboardLayout","numLock","capsLock"]}}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["audio","microphone","keyboardLayout","numLock","capsLock"]}}]}}`, false},
	})
}
