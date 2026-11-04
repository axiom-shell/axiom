package steps

import "testing"

func TestV94TurnsLayoutsIntoSources(t *testing.T) {
	t.Parallel()
	runStepCases(t, 94, []stepCase{
		{"one layout", `{"Input":{"keyboard":{"enabled":true,"layout":"us","variant":"","options":""}}}`,
			`{"Input":{"keyboard":{"enabled":true,"options":""},"sources":[{"id":"us","kind":"xkb","layout":"us","variant":"","engine":""}]}}`, true},
		{"two with a variant", `{"Input":{"keyboard":{"layout":"us, de","variant":",neo"}}}`,
			`{"Input":{"keyboard":{},"sources":[{"id":"us","kind":"xkb","layout":"us","variant":"","engine":""},{"id":"de-neo","kind":"xkb","layout":"de","variant":"neo","engine":""}]}}`, true},
		{"fewer variants than layouts", `{"Input":{"keyboard":{"layout":"us,de","variant":"dvorak"}}}`,
			`{"Input":{"keyboard":{},"sources":[{"id":"us-dvorak","kind":"xkb","layout":"us","variant":"dvorak","engine":""},{"id":"de","kind":"xkb","layout":"de","variant":"","engine":""}]}}`, true},
		{"a layout twice", `{"Input":{"keyboard":{"layout":"us,us,us"}}}`,
			`{"Input":{"keyboard":{},"sources":[{"id":"us","kind":"xkb","layout":"us","variant":"","engine":""},{"id":"us-2","kind":"xkb","layout":"us","variant":"","engine":""},{"id":"us-3","kind":"xkb","layout":"us","variant":"","engine":""}]}}`, true},
		{"empty layouts", `{"Input":{"keyboard":{"layout":" , ","variant":""}}}`, `{"Input":{"keyboard":{}}}`, true},
		{"not a string", `{"Input":{"keyboard":{"layout":5}}}`, `{"Input":{"keyboard":{}}}`, true},
		{"sources already there", `{"Input":{"keyboard":{"layout":"fr"},"sources":[{"id":"de","kind":"xkb","layout":"de"}]}}`,
			`{"Input":{"keyboard":{},"sources":[{"id":"de","kind":"xkb","layout":"de"}]}}`, true},
		{"already migrated", `{"Input":{"keyboard":{"enabled":true},"sources":[]}}`, `{"Input":{"keyboard":{"enabled":true},"sources":[]}}`, false},
		{"no keyboard", `{"Input":{"mouse":{}}}`, `{"Input":{"mouse":{}}}`, false},
		{"no Input", `{"OSD":{}}`, `{"OSD":{}}`, false},
	})
}
