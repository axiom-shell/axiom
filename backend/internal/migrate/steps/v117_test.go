package steps

import "testing"

func TestV117StyleToAuto(t *testing.T) {
	t.Parallel()
	runStepCases(t, 117, []stepCase{
		{"QuickActions tiles in an Overlay page", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"style":"tiles","labels":"show"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"style":"auto","labels":"show"}}]}]}}`, true},
		{"QuickActions tiles in a Menu", `{"Menus":{"items":[{"id":"m","layout":[{"type":"QuickActions","properties":{"style":"tiles"}}]}]}}`,
			`{"Menus":{"items":[{"id":"m","layout":[{"type":"QuickActions","properties":{"style":"auto"}}]}]}}`, true},
		{"QuickActions pills unchanged", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"style":"pills"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"style":"pills"}}]}]}}`, false},
		{"QuickActions without a style unchanged", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"labels":"hide"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"labels":"hide"}}]}]}}`, false},
		{"a Power module's tiles unchanged", `{"Lockscreen":{"layout":[{"type":"Power","properties":{"style":"tiles"}}]}}`,
			`{"Lockscreen":{"layout":[{"type":"Power","properties":{"style":"tiles"}}]}}`, false},
		{"Markets list in a lock screen layout", `{"Lockscreen":{"layout":[{"type":"Markets","properties":{"style":"list","showChart":false}}]}}`,
			`{"Lockscreen":{"layout":[{"type":"Markets","properties":{"style":"auto","showChart":false}}]}}`, true},
		{"Markets tiles and focus unchanged", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"Markets","properties":{"style":"tiles"}},{"type":"Markets","properties":{"style":"focus"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"Markets","properties":{"style":"tiles"}},{"type":"Markets","properties":{"style":"focus"}}]}]}}`, false},
		{"Cheatsheet list and keyboard", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"Cheatsheet","properties":{"style":"list"}},{"type":"Cheatsheet","properties":{"style":"keyboard"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"Cheatsheet","properties":{"style":"auto"}},{"type":"Cheatsheet","properties":{"style":"keyboard"}}]}]}}`, true},
		{"a bar widget's style list unchanged", `{"Bar":{"items":[{"id":"b","widgets":[{"type":"Markets","properties":{"style":"list"}}]}]}}`,
			`{"Bar":{"items":[{"id":"b","widgets":[{"type":"Markets","properties":{"style":"list"}}]}]}}`, false},
		{"already migrated", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"style":"auto"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":{"style":"auto"}}]}]}}`, false},
		{"properties not an object", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":3}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"QuickActions","properties":3}]}]}}`, false},
	})
}

func TestV117GreetingColor(t *testing.T) {
	t.Parallel()
	runStepCases(t, 117, []stepCase{
		{"base05 became empty", `{"Lockscreen":{"layout":[{"type":"Greeting","properties":{"color":"base05","bold":true}}]}}`,
			`{"Lockscreen":{"layout":[{"type":"Greeting","properties":{"color":"","bold":true}}]}}`, true},
		{"base08 unchanged", `{"Lockscreen":{"layout":[{"type":"Greeting","properties":{"color":"base08"}}]}}`,
			`{"Lockscreen":{"layout":[{"type":"Greeting","properties":{"color":"base08"}}]}}`, false},
		{"no color unchanged", `{"Lockscreen":{"layout":[{"type":"Greeting","properties":{"bold":true}}]}}`,
			`{"Lockscreen":{"layout":[{"type":"Greeting","properties":{"bold":true}}]}}`, false},
		{"a Clock's base05 unchanged", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"Clock","properties":{"color":"base05"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"Clock","properties":{"color":"base05"}}]}]}}`, false},
		{"a Greeting in an Overlay page", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"Greeting","properties":{"color":"base05"}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"Greeting","properties":{"color":""}}]}]}}`, true},
		{"a Greeting in a Menu", `{"Menus":{"items":[{"id":"m","layout":[{"type":"Greeting","properties":{"color":"base05"}}]}]}}`,
			`{"Menus":{"items":[{"id":"m","layout":[{"type":"Greeting","properties":{"color":""}}]}]}}`, true},
		{"a Greeting on the Desktop", `{"Desktop":{"modules":[{"type":"Greeting","properties":{"color":"base05"}}]}}`,
			`{"Desktop":{"modules":[{"type":"Greeting","properties":{"color":""}}]}}`, true},
		{"a Greeting on the greeter", `{"Greeter":{"layout":[{"type":"Greeting","properties":{"color":"base05"}}]}}`,
			`{"Greeter":{"layout":[{"type":"Greeting","properties":{"color":""}}]}}`, true},
		{"properties not an object", `{"Lockscreen":{"layout":[{"type":"Greeting","properties":3}]}}`,
			`{"Lockscreen":{"layout":[{"type":"Greeting","properties":3}]}}`, false},
	})
}
