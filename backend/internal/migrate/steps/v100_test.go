package steps

import "testing"

func TestV100RenamesTilesAndButtonActions(t *testing.T) {
	t.Parallel()
	runStepCases(t, 100, []stepCase{
		{"a module and a button",
			`{"Overlay":{"views":[{"modules":[{"type":"QuickActions","id":"q","properties":{"actions":["wifi","caffeine","dnd","lock"]}}]}]},"Bars":{"items":[{"id":"main","left":[{"type":"Button","id":"b","properties":{"action":"appLauncher"}},{"type":"Button","id":"c","properties":{"action":"workspaceOverlay"}}]}]}}`,
			`{"Overlay":{"views":[{"modules":[{"type":"QuickActions","id":"q","properties":{"actions":["wifi","idleInhibit","toggleDnd","lock"]}}]}]},"Bars":{"items":[{"id":"main","left":[{"type":"Button","id":"b","properties":{"action":"launcher"}},{"type":"Button","id":"c","properties":{"action":"workspaceOverview"}}]}]}}`, true},
		{"an edge menu's module", `{"EdgeMenus":{"items":[{"id":"m","modules":[{"type":"QuickActions","properties":{"actions":["dnd"]}}]}]}}`,
			`{"EdgeMenus":{"items":[{"id":"m","modules":[{"type":"QuickActions","properties":{"actions":["toggleDnd"]}}]}]}}`, true},
		{"already new", `{"X":[{"type":"QuickActions","properties":{"actions":["idleInhibit","toggleDnd"]}},{"type":"Button","properties":{"action":"powerMenu"}}]}`,
			`{"X":[{"type":"QuickActions","properties":{"actions":["idleInhibit","toggleDnd"]}},{"type":"Button","properties":{"action":"powerMenu"}}]}`, false},
		{"another type's names", `{"X":[{"type":"Caffeine","properties":{"actions":["caffeine"],"action":"appLauncher"}}]}`,
			`{"X":[{"type":"Caffeine","properties":{"actions":["caffeine"],"action":"appLauncher"}}]}`, false},
		{"odd shapes", `{"X":[{"type":"QuickActions","properties":{"actions":"dnd"}},{"type":"QuickActions","properties":{"actions":[3,"dnd"]}}]}`,
			`{"X":[{"type":"QuickActions","properties":{"actions":"dnd"}},{"type":"QuickActions","properties":{"actions":[3,"toggleDnd"]}}]}`, true},
		{"nothing", `{"General":{}}`, `{"General":{}}`, false},
	})
}
