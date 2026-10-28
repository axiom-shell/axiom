package render

import (
	"slices"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// A user's floating_modifier holds its mod's mouse buttons, so axiom's drag
// and resize binds on them are skipped, and taking axiom's back puts the
// user's (or sway's none) back.
func TestSwayFloatingModifier(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	drag := func(mod string) *jsonx.Array {
		return jsonx.Arr(jsonx.Obj("key", mod+" + mouse:272", "action", "mouseDrag"),
			jsonx.Obj("key", mod+" + mouse:273", "action", "mouseResize"))
	}
	cases := []struct {
		name, config, mod string
		skipped           int
		restore           string
	}{
		{"none of the user's", "bindsym Mod4+Return exec foot", "SUPER", 0, "floating_modifier none"},
		{"same mod", "set $mod Mod4\nfloating_modifier $mod normal", "SUPER", 2, ""},
		{"another mod", "floating_modifier Mod1 inverse", "SUPER", 0, "floating_modifier Mod1 inverse"},
		{"the last line", "floating_modifier Mod1\nfloating_modifier Mod5 normal", "SUPER", 0, "floating_modifier Mod5 normal"},
		{"turned off", "floating_modifier none", "SUPER", 0, "floating_modifier none"},
		{"in a mode", "mode resize {\n floating_modifier Mod4\n}", "SUPER", 0, "floating_modifier none"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			entries := SwayConfigBinds(c.config)
			plan := RuntimeBinds(drag(c.mod), entries)
			if got := len(items(plan.Value("skipped"))); got != c.skipped {
				t.Fatalf("skipped %d, want %d", got, c.skipped)
			}
			unbind := tab.SwayUnbindLines(plan.Value("apply"), nil, entries)
			last := ""
			if len(unbind) > 0 && !slices.Contains([]string{"unbindsym", "unbindcode"}, firstWord.FindString(unbind[len(unbind)-1])) {
				last = unbind[len(unbind)-1]
			}
			if last != c.restore {
				t.Errorf("unbind ends %q, want %q (%q)", last, c.restore, unbind)
			}
		})
	}
}
