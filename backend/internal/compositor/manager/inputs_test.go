package manager

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// What buildInputs reads from the config beyond the goldens' (which hold
// the rest): paused binds left out, the strips by their screen targets,
// and the shell's previews laid over the config.
func TestBuildInputs(t *testing.T) {
	t.Parallel()
	strip := func(screen *jsonx.Object, direction string) *jsonx.Object {
		return jsonx.Obj("screen", screen, "direction", direction)
	}
	cfg := func(layout string) *jsonx.Object {
		return jsonx.Obj(
			"Keybinds", jsonx.Obj("binds", jsonx.Arr(jsonx.Obj("id", "a", "paused", false), jsonx.Obj("id", "b", "paused", true))),
			"Workspaces", jsonx.Obj("layout", layout, "stripColumnWidth", 50.0, "stripFollowFocus", true, "strips", jsonx.Arr(
				strip(jsonx.Obj("mode", "primary"), "vertical"),
				strip(jsonx.Obj("mode", "named", "names", jsonx.Arr("DP-1", "HDMI-A-1")), "horizontal"),
				strip(jsonx.Obj("mode", "all"), "horizontal"))))
	}
	cases := []struct {
		name, layout string
		previews     []config.Op
		binds        string
		strips       string
	}{
		{"strips by target", "perMonitor", nil, `[{"id":"a","paused":false}]`,
			`[{"monitor":"DP-1","direction":"vertical"},{"monitor":"HDMI-A-1","direction":"horizontal"},{"monitor":"*","direction":"horizontal"}]`},
		{"scrolling", "scrolling", nil, `[{"id":"a","paused":false}]`, `[{"monitor":"*","direction":"horizontal"}]`},
		{"previewed", "perMonitor", []config.Op{
			config.SetValue(config.Keys("Keybinds", "binds"), jsonx.Arr(jsonx.Obj("id", "c"))),
			config.SetValue(config.Keys("Workspaces", "layout"), "scrolling"),
			// No place for it (layout is a string): left out, the rest shown
			config.SetValue(config.Keys("Workspaces", "layout", "deeper"), 1.0),
		}, `[{"id":"c"}]`, `[{"monitor":"*","direction":"horizontal"}]`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			saved := cfg(c.layout)
			in := buildInputs(saved, &Facts{Kind: "hyprland", PrimaryMonitor: "DP-1", Previews: c.previews})
			if got := string(jsonx.MarshalCompact(in.get("binds"))); got != c.binds {
				t.Errorf("binds: got %s, want %s", got, c.binds)
			}
			if got := string(jsonx.MarshalCompact(in.get("strips"))); got != c.strips {
				t.Errorf("strips: got %s, want %s", got, c.strips)
			}
			if !jsonx.Equal(saved, cfg(c.layout)) {
				t.Error("the previews changed the config")
			}
		})
	}
}
