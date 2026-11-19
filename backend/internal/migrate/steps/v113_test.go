package steps

import "testing"

func TestV113MovesModuleScaleIntoSizing(t *testing.T) {
	t.Parallel()
	runStepCases(t, 113, []stepCase{
		{"a menu", `{"Menus":{"items":[{"id":"a","layout":{"moduleScale":120,"modules":[]}}]}}`,
			`{"Menus":{"items":[{"id":"a","layout":{"modules":[],"sizing":{"cardSize":120}}}]}}`, true},
		{"a menu at 100", `{"Menus":{"items":[{"id":"a","layout":{"moduleScale":100}}]}}`,
			`{"Menus":{"items":[{"id":"a","layout":{}}]}}`, true},
		{"a desktop item", `{"Desktop":{"items":[{"id":"all","moduleScale":75,"modules":[]}]}}`,
			`{"Desktop":{"items":[{"id":"all","modules":[],"sizing":{"cardSize":75}}]}}`, true},
		{"a desktop item at 100", `{"Desktop":{"items":[{"id":"all","moduleScale":100}]}}`,
			`{"Desktop":{"items":[{"id":"all"}]}}`, true},
		{"the lock screen", `{"Lockscreen":{"layout":{"moduleScale":150}}}`,
			`{"Lockscreen":{"layout":{"sizing":{"cardSize":150}}}}`, true},
		{"the lock screen at 100", `{"Lockscreen":{"layout":{"moduleScale":100}}}`,
			`{"Lockscreen":{"layout":{}}}`, true},
		{"the login screen", `{"Greeter":{"layout":{"moduleScale":60}}}`,
			`{"Greeter":{"layout":{"sizing":{"cardSize":60}}}}`, true},
		{"the login screen at 100", `{"Greeter":{"layout":{"moduleScale":100}}}`,
			`{"Greeter":{"layout":{}}}`, true},
		{"every surface at once", `{"Menus":{"items":[{"id":"a","layout":{"moduleScale":90}},{"id":"b","layout":{"moduleScale":100}}]},"Lockscreen":{"layout":{"moduleScale":110}}}`,
			`{"Menus":{"items":[{"id":"a","layout":{"sizing":{"cardSize":90}}},{"id":"b","layout":{}}]},"Lockscreen":{"layout":{"sizing":{"cardSize":110}}}}`, true},
		{"beside an already set sizing", `{"Lockscreen":{"layout":{"moduleScale":150,"sizing":{"cardSize":80}}}}`,
			`{"Lockscreen":{"layout":{"sizing":{"cardSize":80}}}}`, true},
		{"already migrated", `{"Menus":{"items":[{"id":"a","layout":{"sizing":{"cardSize":120}}}]}}`,
			`{"Menus":{"items":[{"id":"a","layout":{"sizing":{"cardSize":120}}}]}}`, false},
		{"moduleScale not a number", `{"Menus":{"items":[{"id":"a","layout":{"moduleScale":"big"}}]}}`,
			`{"Menus":{"items":[{"id":"a","layout":{"moduleScale":"big"}}]}}`, false},
		{"layout not an object", `{"Menus":{"items":[{"id":"a","layout":3}]},"Greeter":{"layout":"x"}}`,
			`{"Menus":{"items":[{"id":"a","layout":3}]},"Greeter":{"layout":"x"}}`, false},
		{"items not a list", `{"Menus":{"items":3},"Desktop":{"items":{}}}`,
			`{"Menus":{"items":3},"Desktop":{"items":{}}}`, false},
		{"an item not an object", `{"Desktop":{"items":[3,{"id":"all","moduleScale":80}]}}`,
			`{"Desktop":{"items":[3,{"id":"all","sizing":{"cardSize":80}}]}}`, true},
		{"no surfaces", `{"Bars":{}}`, `{"Bars":{}}`, false},
	})
}
