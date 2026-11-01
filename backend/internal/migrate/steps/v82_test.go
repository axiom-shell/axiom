package steps

import "testing"

func TestV82MovesNirisHotCorner(t *testing.T) {
	t.Parallel()
	corner := func(id string) string {
		return `{"id":"` + id + `","corner":"topLeft","action":"workspaceOverview","argument":"","screen":{"mode":"all","names":[]},"delay":0}`
	}
	runStepCases(t, 82, []stepCase{
		{"on in managed mode",
			`{"Compositor":{"mode":"managed","niri":{"hotCorner":true,"animations":true}}}`,
			`{"Compositor":{"mode":"managed","niri":{"animations":true}},"HotCorners":{"items":[` + corner("niri-corner") + `]}}`, true},
		{"beside the user's own corners",
			`{"HotCorners":{"items":[{"id":"niri-corner"}]},"Compositor":{"mode":"managed","niri":{"hotCorner":true}}}`,
			`{"HotCorners":{"items":[{"id":"niri-corner"},` + corner("niri-corner-2") + `]},"Compositor":{"mode":"managed","niri":{}}}`, true},
		{"off", `{"Compositor":{"mode":"managed","niri":{"hotCorner":false}}}`, `{"Compositor":{"mode":"managed","niri":{}}}`, true},
		{"on in detached mode, where it wrote nothing",
			`{"Compositor":{"mode":"detached","niri":{"hotCorner":true}}}`, `{"Compositor":{"mode":"detached","niri":{}}}`, true},
		{"a section of another shape",
			`{"HotCorners":3,"Compositor":{"mode":"managed","niri":{"hotCorner":true}}}`, `{"HotCorners":3,"Compositor":{"mode":"managed","niri":{}}}`, true},
		{"already migrated", `{"Compositor":{"mode":"managed","niri":{}}}`, `{"Compositor":{"mode":"managed","niri":{}}}`, false},
		{"no niri section", `{"Compositor":{"mode":"managed"}}`, `{"Compositor":{"mode":"managed"}}`, false},
	})
}
