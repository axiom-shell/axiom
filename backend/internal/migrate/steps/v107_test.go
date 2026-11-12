package steps

import "testing"

func TestV107DropsSpecialWorkspacesMode(t *testing.T) {
	t.Parallel()
	runStepCases(t, 107, []stepCase{
		{"the key present", `{"Workspaces":{"specialWorkspaces":"workspace","other":1}}`,
			`{"Workspaces":{"other":1}}`, true},
		{"the default value", `{"Workspaces":{"specialWorkspaces":"scratchpad"}}`, `{"Workspaces":{}}`, true},
		{"the key absent", `{"Workspaces":{"other":1}}`, `{"Workspaces":{"other":1}}`, false},
		{"already an array", `{"Workspaces":{"specialWorkspaces":[{"id":"a"}]}}`,
			`{"Workspaces":{"specialWorkspaces":[{"id":"a"}]}}`, false},
		{"Workspaces not an object", `{"Workspaces":"x"}`, `{"Workspaces":"x"}`, false},
		{"no Workspaces section", `{"Bars":{}}`, `{"Bars":{}}`, false},
	})
}
