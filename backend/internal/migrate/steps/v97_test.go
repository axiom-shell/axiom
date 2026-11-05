package steps

import "testing"

func TestV97DropsDetachedGaps(t *testing.T) {
	t.Parallel()
	runStepCases(t, 97, []stepCase{
		{"every list",
			`{"OSD":{"items":[{"id":"main","detached":true,"gap":12},{"id":"b"}]},"Dock":{"items":[{"id":"main","gap":-1}]},"EdgeMenus":{"items":[{"id":"m","gap":4,"detached":true}]}}`,
			`{"OSD":{"items":[{"id":"main","detached":true},{"id":"b"}]},"Dock":{"items":[{"id":"main"}]},"EdgeMenus":{"items":[{"id":"m","detached":true}]}}`, true},
		{"no gaps", `{"OSD":{"items":[{"id":"main"}]}}`, `{"OSD":{"items":[{"id":"main"}]}}`, false},
		{"Notifications keep theirs", `{"Notifications":{"gap":8}}`, `{"Notifications":{"gap":8}}`, false},
		{"items not a list", `{"Dock":{"items":3}}`, `{"Dock":{"items":3}}`, false},
		{"an entry not an object", `{"OSD":{"items":[1]}}`, `{"OSD":{"items":[1]}}`, false},
		{"no sections", `{"General":{}}`, `{"General":{}}`, false},
	})
}
