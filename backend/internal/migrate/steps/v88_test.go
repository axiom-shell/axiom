package steps

import "testing"

func TestV88DropsTheWallpaperBackend(t *testing.T) {
	t.Parallel()
	runStepCases(t, 88, []stepCase{
		{"the awww backend",
			`{"Appearance":{"wallpaper":{"mode":"fixed","backend":"awww","daemon":false}}}`,
			`{"Appearance":{"wallpaper":{"mode":"fixed"}}}`, true},
		{"the built-in backend",
			`{"Appearance":{"wallpaper":{"backend":"quickshell"}}}`,
			`{"Appearance":{"wallpaper":{}}}`, true},
		{"only the daemon", `{"Appearance":{"wallpaper":{"daemon":true}}}`, `{"Appearance":{"wallpaper":{}}}`, true},
		{"already migrated", `{"Appearance":{"wallpaper":{"mode":"rotate"}}}`, `{"Appearance":{"wallpaper":{"mode":"rotate"}}}`, false},
		{"no wallpaper", `{"Appearance":{}}`, `{"Appearance":{}}`, false},
		{"another shape", `{"Appearance":{"wallpaper":3}}`, `{"Appearance":{"wallpaper":3}}`, false},
	})
}
