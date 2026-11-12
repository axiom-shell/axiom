package steps

import "testing"

func TestV105DropsSwaySpecialWorkspaces(t *testing.T) {
	t.Parallel()
	runStepCases(t, 105, []stepCase{
		{"the key present", `{"Compositor":{"mode":"managed","sway":{"specialWorkspaces":"workspace","workspaceLayout":"tabbed"}}}`,
			`{"Compositor":{"mode":"managed","sway":{"workspaceLayout":"tabbed"}}}`, true},
		{"the default value", `{"Compositor":{"sway":{"specialWorkspaces":"scratchpad"}}}`, `{"Compositor":{"sway":{}}}`, true},
		{"the key absent", `{"Compositor":{"sway":{"workspaceLayout":"tabbed"}}}`, `{"Compositor":{"sway":{"workspaceLayout":"tabbed"}}}`, false},
		{"sway not an object", `{"Compositor":{"sway":"x"}}`, `{"Compositor":{"sway":"x"}}`, false},
		{"no Compositor section", `{"Bars":{}}`, `{"Bars":{}}`, false},
	})
}
